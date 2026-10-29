using System.Text.Json;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Diagnostics;

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
        typeof(FiscalSettings), typeof(Cfop), typeof(TaxRule), typeof(MonthlyPrice), typeof(PaymentTerm), typeof(PriceListEntry),
        typeof(SalesSettings), typeof(ProductionSettings), typeof(SteelLot), typeof(SlitterJob)
    ];

    private static readonly HashSet<string> Hidden = ["PasswordHash", "TokenVersion", "FailedLogins", "LockedUntil", "xmin", "NextNumber"];
    private static readonly JsonSerializerOptions Json = new() { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.Never };

    private readonly List<(EntityEntry Entry, Dictionary<string, object?> Values)> pendingInserts = [];
    private bool writing;

    public static bool IsAudited(Type type) => Audited.Contains(type);

    public override InterceptionResult<int> SavingChanges(DbContextEventData eventData, InterceptionResult<int> result)
    {
        if (eventData.Context is { } ctx && !writing) Capture(ctx);
        return result;
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData, InterceptionResult<int> result, CancellationToken ct = default)
    {
        if (eventData.Context is { } ctx && !writing) Capture(ctx);
        return ValueTask.FromResult(result);
    }

    public override int SavedChanges(SaveChangesCompletedEventData eventData, int result)
    {
        if (eventData.Context is { } ctx && pendingInserts.Count > 0 && !writing) FlushInserts(ctx).GetAwaiter().GetResult();
        return result;
    }

    public override async ValueTask<int> SavedChangesAsync(SaveChangesCompletedEventData eventData, int result, CancellationToken ct = default)
    {
        if (eventData.Context is { } ctx && pendingInserts.Count > 0 && !writing) await FlushInserts(ctx, ct);
        return result;
    }

    public override void SaveChangesFailed(DbContextErrorEventData eventData) => pendingInserts.Clear();

    public override Task SaveChangesFailedAsync(DbContextErrorEventData eventData, CancellationToken ct = default)
    {
        pendingInserts.Clear();
        return Task.CompletedTask;
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
