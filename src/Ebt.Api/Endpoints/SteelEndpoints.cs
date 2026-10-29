using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record SteelLotIn(string LotCode, int SupplierId, DateOnly ReceivedDate, decimal WeightKg, decimal PricePerKg, string? PurchaseInvoice, string? Specification, decimal? Thickness, decimal? Width, string? Notes);
public record SteelLotOut(int Id, string LotCode, int SupplierId, string SupplierName, string? PurchaseInvoice, DateOnly ReceivedDate, string? Specification, decimal? Thickness, decimal? Width, decimal WeightKg, decimal PricePerKg,
    decimal PurchaseValue, decimal SentKg, decimal ReturnedKg, decimal ScrapKg, decimal UsedKg, decimal ServiceCost, decimal LaborCost, decimal BalanceKg, decimal BalanceValue, decimal TotalCost, int PendingJobs, string? Notes, DateTimeOffset CreatedAt);

public record SlitterJobIn(int LotId, int ProcessorId, DateOnly ShipmentDate, decimal SentKg, string? ShipmentInvoice, string? ReturnInvoice, DateOnly? ReturnDate, decimal? FinishedKg, decimal? ScrapKg, decimal? ServiceCost, string? Notes);
public record SlitterJobOut(int Id, int LotId, string LotCode, int ProcessorId, string ProcessorName, string? ShipmentInvoice, DateOnly ShipmentDate, decimal SentKg, string? ReturnInvoice, DateOnly? ReturnDate, decimal? FinishedKg,
    decimal? ScrapKg, decimal? LossPercent, decimal? ServiceCost, bool Returned, string? Notes);

public record SteelUsageIn(int LotId, DateOnly Date, decimal Kg, decimal LaborCost, string? Reference, string? Notes);
public record SteelUsageOut(int Id, int LotId, string LotCode, DateOnly Date, decimal Kg, decimal LaborCost, string? Reference, string? Notes);

public static class SteelPolicies
{
    public const string Write = "steel";
}

public static class SteelEndpoints
{
    public static IServiceCollection AddSteel(this IServiceCollection services)
    {
        services.AddAuthorization(o => o.AddPolicy(SteelPolicies.Write, p => p.RequireRole(nameof(UserRole.Admin), nameof(UserRole.Stock), nameof(UserRole.Purchasing))));
        return services;
    }

    public static void MapSteel(this WebApplication app)
    {
        var lots = app.MapGroup("/api/steel/lots").WithTags("Steel");
        lots.MapCrud(new CrudSpec<SteelLot, SteelLotIn, SteelLotOut>
        {
            WritePolicy = SteelPolicies.Write,
            Project = x => new SteelLotOut(x.Id, x.LotCode, x.SupplierId, x.Supplier!.Name, x.PurchaseInvoice, x.ReceivedDate, x.Specification, x.Thickness, x.Width, x.WeightKg, x.PricePerKg,
                Math.Round(x.WeightKg * x.PricePerKg, 2),
                x.SlitterJobs.Sum(j => j.SentKg), x.SlitterJobs.Sum(j => j.FinishedKg ?? 0m), x.SlitterJobs.Sum(j => j.ScrapKg ?? 0m), x.Usages.Sum(u => u.Kg),
                x.SlitterJobs.Sum(j => j.ServiceCost ?? 0m), x.Usages.Sum(u => u.LaborCost),
                x.WeightKg - x.SlitterJobs.Sum(j => j.SentKg) + x.SlitterJobs.Sum(j => j.FinishedKg ?? 0m) - x.Usages.Sum(u => u.Kg),
                Math.Round((x.WeightKg - x.SlitterJobs.Sum(j => j.SentKg) + x.SlitterJobs.Sum(j => j.FinishedKg ?? 0m) - x.Usages.Sum(u => u.Kg)) * x.PricePerKg, 2),
                Math.Round(x.WeightKg * x.PricePerKg + x.SlitterJobs.Sum(j => j.ServiceCost ?? 0m) + x.Usages.Sum(u => u.LaborCost), 2),
                x.SlitterJobs.Count(j => j.FinishedKg == null), x.Notes, x.CreatedAt),
            Create = i => Apply(i, new SteelLot { LotCode = i.LotCode.Trim(), CreatedAt = DateTimeOffset.UtcNow }),
            Apply = (i, x) => Apply(i, x),
            Search = (q, s) => q.Where(x => EF.Functions.ILike(x.LotCode, $"%{s}%") || EF.Functions.ILike(x.PurchaseInvoice ?? "", $"%{s}%") || EF.Functions.ILike(x.Supplier!.Name, $"%{s}%") || EF.Functions.ILike(x.Specification ?? "", $"%{s}%")),
            Order = q => q.OrderByDescending(x => x.ReceivedDate).ThenByDescending(x => x.Id),
            Validate = async (i, db, ct) =>
            {
                var e = Errors()
                    .Require(Has(i.LotCode), "lotCode", "Required")
                    .Require(i.WeightKg > 0, "weightKg", "Must be greater than zero")
                    .Require(i.PricePerKg >= 0, "pricePerKg", "Cannot be negative")
                    .Require(i.Thickness is null or >= 0, "thickness", "Cannot be negative")
                    .Require(i.Width is null or >= 0, "width", "Cannot be negative");
                return e.Require(await db.Suppliers.AnyAsync(s => s.Id == i.SupplierId, ct), "supplierId", "Supplier not found");
            },
            BeforeDelete = async (id, db, ct) => await db.SlitterJobs.AnyAsync(j => j.LotId == id, ct) || await db.SteelUsages.AnyAsync(u => u.LotId == id, ct) ? "Lot has slitter jobs or usage; remove them first" : null
        });
        lots.MapGet("/{id:int}/slitter", async (int id, EbtDbContext db, CancellationToken ct) =>
            Results.Ok(await db.SlitterJobs.AsNoTracking().Where(j => j.LotId == id).OrderBy(j => j.ShipmentDate).ThenBy(j => j.Id).Select(JobProject).ToListAsync(ct))).RequireAuthorization(Policies.Read);
        lots.MapGet("/{id:int}/usages", async (int id, EbtDbContext db, CancellationToken ct) =>
            Results.Ok(await db.SteelUsages.AsNoTracking().Where(u => u.LotId == id).OrderBy(u => u.Date).ThenBy(u => u.Id).Select(UsageProject).ToListAsync(ct))).RequireAuthorization(Policies.Read);

        app.MapGroup("/api/steel/slitter").WithTags("Steel").MapCrud(new CrudSpec<SlitterJob, SlitterJobIn, SlitterJobOut>
        {
            WritePolicy = SteelPolicies.Write,
            Project = JobProject,
            Create = i => Apply(i, new SlitterJob()),
            Apply = (i, x) => Apply(i, x),
            Search = (q, s) => q.Where(x => EF.Functions.ILike(x.Lot!.LotCode, $"%{s}%") || EF.Functions.ILike(x.ShipmentInvoice ?? "", $"%{s}%") || EF.Functions.ILike(x.ReturnInvoice ?? "", $"%{s}%") || EF.Functions.ILike(x.Processor!.Name, $"%{s}%")),
            Order = q => q.OrderBy(x => x.FinishedKg != null).ThenByDescending(x => x.ShipmentDate).ThenByDescending(x => x.Id),
            Validate = async (i, db, ct) =>
            {
                var lot = await db.SteelLots.AsNoTracking().FirstOrDefaultAsync(l => l.Id == i.LotId, ct);
                var e = Errors()
                    .Require(lot is not null, "lotId", "Lot not found")
                    .Require(i.SentKg > 0, "sentKg", "Must be greater than zero")
                    .Require(lot is null || i.SentKg <= lot.WeightKg, "sentKg", "Exceeds the lot weight")
                    .Require(i.FinishedKg is null or >= 0, "finishedKg", "Cannot be negative")
                    .Require(i.ScrapKg is null or >= 0, "scrapKg", "Cannot be negative")
                    .Require(i.ServiceCost is null or >= 0, "serviceCost", "Cannot be negative")
                    .Require((i.FinishedKg ?? 0) + (i.ScrapKg ?? 0) <= i.SentKg * 1.005m, "finishedKg", "Finished plus scrap exceeds what was sent")
                    .Require(i.ReturnDate is null || i.FinishedKg is not null, "finishedKg", "Required once the material returned")
                    .Require(i.ReturnDate is null || i.ReturnDate >= i.ShipmentDate, "returnDate", "Before the shipment date");
                return e.Require(await db.Suppliers.AnyAsync(s => s.Id == i.ProcessorId, ct), "processorId", "Processor not found");
            }
        });

        app.MapGroup("/api/steel/usages").WithTags("Steel").MapCrud(new CrudSpec<SteelUsage, SteelUsageIn, SteelUsageOut>
        {
            WritePolicy = SteelPolicies.Write,
            Project = UsageProject,
            Create = i => Apply(i, new SteelUsage()),
            Apply = (i, x) => Apply(i, x),
            Search = (q, s) => q.Where(x => EF.Functions.ILike(x.Lot!.LotCode, $"%{s}%") || EF.Functions.ILike(x.Reference ?? "", $"%{s}%")),
            Order = q => q.OrderByDescending(x => x.Date).ThenByDescending(x => x.Id),
            Validate = async (i, db, ct) => Errors()
                .Require(i.Kg > 0, "kg", "Must be greater than zero")
                .Require(i.LaborCost >= 0, "laborCost", "Cannot be negative")
                .Require(await db.SteelLots.AnyAsync(l => l.Id == i.LotId, ct), "lotId", "Lot not found")
        });
    }

    private static readonly System.Linq.Expressions.Expression<Func<SlitterJob, SlitterJobOut>> JobProject = x =>
        new SlitterJobOut(x.Id, x.LotId, x.Lot!.LotCode, x.ProcessorId, x.Processor!.Name, x.ShipmentInvoice, x.ShipmentDate, x.SentKg, x.ReturnInvoice, x.ReturnDate, x.FinishedKg, x.ScrapKg,
            x.FinishedKg == null ? null : Math.Round((x.SentKg - x.FinishedKg.Value) / x.SentKg * 100m, 2), x.ServiceCost, x.FinishedKg != null, x.Notes);

    private static readonly System.Linq.Expressions.Expression<Func<SteelUsage, SteelUsageOut>> UsageProject = x =>
        new SteelUsageOut(x.Id, x.LotId, x.Lot!.LotCode, x.Date, x.Kg, x.LaborCost, x.Reference, x.Notes);

    private static SteelLot Apply(SteelLotIn i, SteelLot x)
    {
        x.LotCode = i.LotCode.Trim();
        x.SupplierId = i.SupplierId;
        x.ReceivedDate = i.ReceivedDate;
        x.WeightKg = i.WeightKg;
        x.PricePerKg = i.PricePerKg;
        x.PurchaseInvoice = Clean(i.PurchaseInvoice);
        x.Specification = Clean(i.Specification);
        x.Thickness = i.Thickness;
        x.Width = i.Width;
        x.Notes = Clean(i.Notes);
        return x;
    }

    private static SlitterJob Apply(SlitterJobIn i, SlitterJob x)
    {
        x.LotId = i.LotId;
        x.ProcessorId = i.ProcessorId;
        x.ShipmentDate = i.ShipmentDate;
        x.SentKg = i.SentKg;
        x.ShipmentInvoice = Clean(i.ShipmentInvoice);
        x.ReturnInvoice = Clean(i.ReturnInvoice);
        x.ReturnDate = i.ReturnDate;
        x.FinishedKg = i.FinishedKg;
        x.ScrapKg = i.ScrapKg;
        x.ServiceCost = i.ServiceCost;
        x.Notes = Clean(i.Notes);
        return x;
    }

    private static SteelUsage Apply(SteelUsageIn i, SteelUsage x)
    {
        x.LotId = i.LotId;
        x.Date = i.Date;
        x.Kg = i.Kg;
        x.LaborCost = i.LaborCost;
        x.Reference = Clean(i.Reference);
        x.Notes = Clean(i.Notes);
        return x;
    }
}
