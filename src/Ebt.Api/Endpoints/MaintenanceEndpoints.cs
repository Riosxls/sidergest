using System.Text.Json;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;
using Ebt.Api.Infrastructure;
using Ebt.Core.Maintenance;

namespace Ebt.Api.Endpoints;

public record DataResetIn(List<ResetScope> Scopes, string? Confirm = null, string? Password = null);

public record DataResetOut(IReadOnlyList<ResetTableCount> Tables, long TotalRows);
/// <summary><c>AllManual</c> selects every row whose source is <c>From</c> (default Manual), so Test records can be turned back into Manual.</summary>
public record DataSourceIn(string? Entity, List<int>? Ids, bool AllManual = false, DataSource Target = DataSource.Test, bool Apply = false, DataSource? From = null);
public record DataSourceCount(string Entity, int Manual, int Imported, int Test);

public static class MaintenanceEndpoints
{
    /// <summary>The word the admin has to type before movement data is deleted.</summary>
    public const string ConfirmWord = "LIMPAR";

    /// <summary>The newest backup must be younger than this before movement data may be deleted.</summary>
    public static readonly TimeSpan BackupMaxAge = TimeSpan.FromHours(1);

    /// <summary>
    /// Why the wipe is refused for lack of a fresh backup, or null when it may go on. With no backup folder configured (development,
    /// tests) there is nothing to check.
    /// </summary>
    public static string? BackupBlock(string? directory, DateTimeOffset now)
    {
        if (string.IsNullOrWhiteSpace(directory)) return null;
        var last = SystemEndpoints.ScanBackups(directory).LastBackupAt;
        return last is { } at && now - at <= BackupMaxAge ? null : "Make a backup first: the newest one is missing or older than 1 hour";
    }

    public static void MapMaintenance(this WebApplication app)
    {
        var g = app.MapGroup("/api/admin/data-reset").WithTags("Maintenance").RequireAuthorization(Policies.Admin);

        g.MapPost("/preview", async (DataResetIn i, DataResetService svc, CancellationToken ct) =>
        {
            if (i.Scopes is not { Count: > 0 }) return Results.ValidationProblem(new Dictionary<string, string[]> { ["scopes"] = ["Choose at least one group"] });
            var tables = await svc.PreviewAsync(i.Scopes, ct);
            return Results.Ok(new DataResetOut(tables, tables.Sum(t => t.Rows)));
        });

        g.MapPost("/", async (DataResetIn i, DataResetService svc, EbtDbContext db, IConfiguration config, System.Security.Claims.ClaimsPrincipal principal, CancellationToken ct) =>
        {
            if (i.Scopes is not { Count: > 0 }) return Results.ValidationProblem(new Dictionary<string, string[]> { ["scopes"] = ["Choose at least one group"] });
            if (i.Confirm != ConfirmWord) return Results.ValidationProblem(new Dictionary<string, string[]> { ["confirm"] = [$"Type {ConfirmWord} to confirm"] });
            if (string.IsNullOrEmpty(i.Password)) return Results.ValidationProblem(new Dictionary<string, string[]> { ["password"] = ["Type your password to confirm"] });
            if (await AuthEndpoints.ReauthAsync(db, principal, i.Password, ct) is { } denied) return denied;
            if (BackupBlock(config["Backup:Directory"], DateTimeOffset.UtcNow) is { } block) return Results.Problem(block, statusCode: StatusCodes.Status409Conflict, title: "Cannot clear data");
            try
            {
                var tables = await svc.ResetAsync(i.Scopes, ct);
                return Results.Ok(new DataResetOut(tables, tables.Sum(t => t.Rows)));
            }
            catch (DataResetException e)
            {
                return Results.Problem(e.Message, statusCode: StatusCodes.Status409Conflict, title: "Cannot clear data");
            }
        }).RequireRateLimiting(Policies.AccountLimiter);
        var s = app.MapGroup("/api/admin/data-source").WithTags("Maintenance").RequireAuthorization(Policies.Admin);

        s.MapGet("/", async (EbtDbContext db, CancellationToken ct) =>
        {
            var rows = new List<DataSourceCount>();
            foreach (var (name, flag) in SourceEntities)
                rows.Add(await flag.CountAsync(db, name, ct));
            return Results.Ok(rows);
        });

        s.MapPost("/", async (DataSourceIn i, EbtDbContext db, ICurrentUser user, CancellationToken ct) =>
        {
            if (!SourceEntities.TryGetValue(i.Entity ?? "", out var flag)) return Results.ValidationProblem(new Dictionary<string, string[]> { ["entity"] = [$"One of: {string.Join(", ", SourceEntities.Keys)}"] });
            if (i.Ids is not { Count: > 0 } && !i.AllManual) return Results.ValidationProblem(new Dictionary<string, string[]> { ["ids"] = ["Pass ids or allManual"] });
            var count = await flag.ApplyAsync(db, i.Ids, i.AllManual, i.From ?? DataSource.Manual, i.Target, i.Apply, ct);
            if (i.Apply && count > 0)
            {
                db.AuditLog.Add(new AuditEntry
                {
                    At = DateTimeOffset.UtcNow, User = user.Name, Entity = "DataSource", EntityId = i.Entity!, Action = "Update",
                    Changes = JsonSerializer.Serialize(new { target = i.Target.ToString(), rows = count, allManual = i.AllManual, from = (i.From ?? DataSource.Manual).ToString(), ids = i.Ids })
                });
                await db.SaveChangesAsync(ct);
            }
            return Results.Ok(new { entity = i.Entity, rows = count, applied = i.Apply });
        });
    }

    private static readonly Dictionary<string, ISourceFlagger> SourceEntities = new()
    {
        ["Customer"] = new SourceFlagger<Customer>(d => d.Customers),
        ["Supplier"] = new SourceFlagger<Supplier>(d => d.Suppliers),
        ["Product"] = new SourceFlagger<Product>(d => d.Products),
        ["Material"] = new SourceFlagger<Material>(d => d.Materials),
        ["Quote"] = new SourceFlagger<Quote>(d => d.Quotes),
        ["SalesOrder"] = new SourceFlagger<SalesOrder>(d => d.SalesOrders),
        ["Delivery"] = new SourceFlagger<Delivery>(d => d.Deliveries),
        ["ProductionOrder"] = new SourceFlagger<ProductionOrder>(d => d.ProductionOrders),
        ["PurchaseRequisition"] = new SourceFlagger<PurchaseRequisition>(d => d.PurchaseRequisitions),
        ["PurchaseOrder"] = new SourceFlagger<PurchaseOrder>(d => d.PurchaseOrders),
        ["StockDocument"] = new SourceFlagger<StockDocument>(d => d.StockDocuments),
    };

    private interface ISourceFlagger
    {
        Task<DataSourceCount> CountAsync(EbtDbContext db, string name, CancellationToken ct);
        Task<int> ApplyAsync(EbtDbContext db, List<int>? ids, bool allManual, DataSource from, DataSource target, bool apply, CancellationToken ct);
    }

    private sealed class SourceFlagger<T>(Func<EbtDbContext, IQueryable<T>> set) : ISourceFlagger where T : class, IHasSource
    {
        public async Task<DataSourceCount> CountAsync(EbtDbContext db, string name, CancellationToken ct)
        {
            var q = set(db);
            return new DataSourceCount(name, await q.CountAsync(x => x.Source == DataSource.Manual, ct), await q.CountAsync(x => x.Source == DataSource.Imported, ct), await q.CountAsync(x => x.Source == DataSource.Test, ct));
        }

        public async Task<int> ApplyAsync(EbtDbContext db, List<int>? ids, bool allManual, DataSource from, DataSource target, bool apply, CancellationToken ct)
        {
            var q = set(db);
            q = ids is { Count: > 0 } ? q.Where(x => ids.Contains(EF.Property<int>(x, "Id"))) : q.Where(x => x.Source == from);
            q = q.Where(x => x.Source != target);
            return apply ? await q.ExecuteUpdateAsync(s => s.SetProperty(x => x.Source, target), ct) : await q.CountAsync(ct);
        }
    }
}
