using System.Text.Json;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Storage;

namespace Ebt.Core.Data;

public class AuditEntry
{
    public long Id { get; set; }
    public DateTimeOffset At { get; set; }
    public string? User { get; set; }
    public required string Entity { get; set; }
    public required string EntityId { get; set; }
    public required string Action { get; set; }
    /// <summary>JSON: insert/delete = {field: value}; update = {field: {from, to}}.</summary>
    public required string Changes { get; set; }
}

/// <summary>Who is making the change; implemented by the API from the request principal.</summary>
public interface ICurrentUser
{
    string? Name { get; }
}

/// <summary>
/// Records inserts, updates and deletes of master data and configuration (not the high-volume transactional tables,
/// which keep their own history). Secrets and bookkeeping columns are never written to the log.
/// </summary>
public sealed class AuditInterceptor(ICurrentUser user) : SaveChangesInterceptor
{
    private static readonly HashSet<Type> Audited =
    [
        typeof(Customer), typeof(CustomerAddress), typeof(Supplier), typeof(SupplierAddress), typeof(Material), typeof(Product),
        typeof(AppUser), typeof(StockLocation), typeof(StockSettings), typeof(StockClosing),
        typeof(FiscalSettings), typeof(FiscalInutilization), typeof(Cfop), typeof(TaxRule), typeof(MonthlyPrice), typeof(PaymentTerm), typeof(PriceListEntry),
        typeof(ReceivablePayment), typeof(SalesSettings), typeof(ProductionSettings), typeof(BackupSettings), typeof(PurchasingSettings), typeof(SteelLot), typeof(SlitterJob),
        // Engineering and shop-floor master data: a changed routing or BOM changes what gets built.
        typeof(BomItem), typeof(RoutingOperation), typeof(ProductCustomer), typeof(WorkCenter), typeof(Machine), typeof(Tool),
        typeof(Shift), typeof(Employee), typeof(Holiday)
    ];

    /// <summary>
    /// Transactional documents whose full edits are not logged (they keep their own history) but whose status changes must show who made them:
    /// production orders (release, stop, cancel, close), quality certificates (issue, cancel, delete), and the sales, purchasing, fiscal and stock
    /// documents. The listed fields are what a Status row carries when they change and what a Delete row records (so the number of a deleted quote
    /// stays traceable); stock documents are never edited, their only change is being reversed.
    /// </summary>
    private static readonly Dictionary<Type, string[]> Transitions = new()
    {
        [typeof(ProductionOrder)] = ["Status", "StatusReason"],
        [typeof(QualityCertificate)] = ["Status"],
        [typeof(Quote)] = ["Status", "Reference"],
        [typeof(SalesOrder)] = ["Status", "StatusReason", "Reference"],
        [typeof(Delivery)] = ["Status", "Reference"],
        [typeof(PurchaseOrder)] = ["Status", "Number"],
        [typeof(FiscalDocument)] = ["Status", "Series", "Number"],
        [typeof(StockDocument)] = ["Reversed", "Reference"]
    };

    private static readonly HashSet<string> Hidden = ["PasswordHash", "TokenVersion", "FailedLogins", "LockedUntil", "xmin", "NextNumber", "LastActivityAt"];
    private static readonly JsonSerializerOptions Json = new() { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.Never };

    private readonly List<(EntityEntry Entry, Dictionary<string, object?> Values)> pendingInserts = [];
    private bool writing;

    // Insert rows need the generated keys, so they are written by a second SaveChanges after the first one. When the caller has no transaction of
    // its own, this one wraps both: the entity and its audit row commit together or not at all.
    private IDbContextTransaction? ownTransaction;

    public static bool IsAudited(Type type) => Audited.Contains(type);

    public override InterceptionResult<int> SavingChanges(DbContextEventData eventData, InterceptionResult<int> result)
    {
        if (eventData.Context is { } ctx && !writing)
        {
            Capture(ctx);
            if (pendingInserts.Count > 0 && ctx.Database.CurrentTransaction is null) ownTransaction = ctx.Database.BeginTransaction();
        }
        return result;
    }

    public override async ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData, InterceptionResult<int> result, CancellationToken ct = default)
    {
        if (eventData.Context is { } ctx && !writing)
        {
            Capture(ctx);
            if (pendingInserts.Count > 0 && ctx.Database.CurrentTransaction is null) ownTransaction = await ctx.Database.BeginTransactionAsync(ct);
        }
        return result;
    }

    public override int SavedChanges(SaveChangesCompletedEventData eventData, int result)
    {
        if (eventData.Context is { } ctx && !writing)
        {
            try
            {
                if (pendingInserts.Count > 0) FlushInserts(ctx).GetAwaiter().GetResult();
                ownTransaction?.Commit();
            }
            catch
            {
                ownTransaction?.Rollback();
                throw;
            }
            finally { EndOwnTransaction(); }
        }
        return result;
    }

    public override async ValueTask<int> SavedChangesAsync(SaveChangesCompletedEventData eventData, int result, CancellationToken ct = default)
    {
        if (eventData.Context is { } ctx && !writing)
        {
            try
            {
                if (pendingInserts.Count > 0) await FlushInserts(ctx, ct);
                if (ownTransaction is { } tx) await tx.CommitAsync(ct);
            }
            catch
            {
                if (ownTransaction is { } tx) await tx.RollbackAsync(CancellationToken.None);
                throw;
            }
            finally { EndOwnTransaction(); }
        }
        return result;
    }

    public override void SaveChangesFailed(DbContextErrorEventData eventData)
    {
        pendingInserts.Clear();
        try { ownTransaction?.Rollback(); }
        finally { EndOwnTransaction(); }
    }

    public override async Task SaveChangesFailedAsync(DbContextErrorEventData eventData, CancellationToken ct = default)
    {
        pendingInserts.Clear();
        try { if (ownTransaction is { } tx) await tx.RollbackAsync(CancellationToken.None); }
        finally { EndOwnTransaction(); }
    }

    private void EndOwnTransaction()
    {
        ownTransaction?.Dispose();
        ownTransaction = null;
    }

    private void Capture(DbContext ctx)
    {
        pendingInserts.Clear();
        ctx.ChangeTracker.DetectChanges();
        foreach (var entry in ctx.ChangeTracker.Entries().Where(e => e.State is EntityState.Added or EntityState.Modified or EntityState.Deleted && Audited.Contains(e.Entity.GetType())).ToList())
        {
            switch (entry.State)
            {
                case EntityState.Added:
                    pendingInserts.Add((entry, Values(entry, current: true)));
                    break;
                case EntityState.Deleted:
                    ctx.Set<AuditEntry>().Add(Row(entry, "Delete", Values(entry, current: false)));
                    break;
                case EntityState.Modified:
                    var diff = entry.Properties
                        .Where(p => p.IsModified && !Hidden.Contains(p.Metadata.Name) && !Equals(p.OriginalValue, p.CurrentValue))
                        .ToDictionary(p => p.Metadata.Name, p => (object?)new { from = p.OriginalValue, to = p.CurrentValue });
                    if (diff.Count > 0) ctx.Set<AuditEntry>().Add(Row(entry, "Update", diff));
                    break;
            }
        }
        foreach (var entry in ctx.ChangeTracker.Entries().Where(e => e.State is EntityState.Modified or EntityState.Deleted && Transitions.ContainsKey(e.Entity.GetType())).ToList())
        {
            var fields = Transitions[entry.Entity.GetType()];
            if (entry.State == EntityState.Deleted)
            {
                ctx.Set<AuditEntry>().Add(Row(entry, "Delete", fields.ToDictionary(f => f, f => entry.Property(f).OriginalValue)));
                continue;
            }
            var diff = entry.Properties
                .Where(p => fields.Contains(p.Metadata.Name) && p.IsModified && !Equals(p.OriginalValue, p.CurrentValue))
                .ToDictionary(p => p.Metadata.Name, p => (object?)new { from = p.OriginalValue, to = p.CurrentValue });
            if (diff.Count > 0) ctx.Set<AuditEntry>().Add(Row(entry, "Status", diff));
        }
    }

    private async Task FlushInserts(DbContext ctx, CancellationToken ct = default)
    {
        var rows = pendingInserts.Select(p => Row(p.Entry, "Insert", p.Values)).ToList();
        pendingInserts.Clear();
        writing = true;
        try
        {
            ctx.Set<AuditEntry>().AddRange(rows);
            await ctx.SaveChangesAsync(ct);
        }
        finally { writing = false; }
    }

    private static Dictionary<string, object?> Values(EntityEntry entry, bool current) =>
        entry.Properties.Where(p => !Hidden.Contains(p.Metadata.Name))
            .ToDictionary(p => p.Metadata.Name, p => current ? p.CurrentValue : p.OriginalValue);

    private AuditEntry Row(EntityEntry entry, string action, Dictionary<string, object?> changes) => new()
    {
        At = DateTimeOffset.UtcNow,
        User = user.Name,
        Entity = entry.Metadata.ClrType.Name,
        EntityId = string.Join(",", entry.Metadata.FindPrimaryKey()!.Properties.Select(p => entry.Property(p.Name).CurrentValue)),
        Action = action,
        Changes = JsonSerializer.Serialize(changes, Json)
    };
}
