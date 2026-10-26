using System.Security.Claims;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record StockLocationIn(string Code, string Name, StockLocationKind Kind, bool Active = true);
public record StockLocationOut(int Id, string Code, string Name, StockLocationKind Kind, bool Active);
public record StockMovementOut(long Id, int DocumentId, MovementType Type, DateOnly Date, int? MaterialId, int? ProductId, string ItemCode, int LocationId, string LocationCode, int? LotId, string? LotCode, decimal Quantity, decimal UnitCost, decimal IcmsRate, int? ReservationId, string? Reference, decimal? BalanceAfter = null);
public record StockDocumentOut(int Id, MovementType Type, DateOnly Date, string? Reference, int? SupplierId, int? CustomerId, string? Notes, int? ReversalOfId, bool Reversed, string CreatedBy, DateTimeOffset CreatedAt, IReadOnlyList<StockMovementOut> Movements);
public record StockDocumentSummary(int Id, MovementType Type, DateOnly Date, string? Reference, int? SupplierId, int? CustomerId, int? ReversalOfId, bool Reversed, string CreatedBy, DateTimeOffset CreatedAt, int Lines);
public record ReverseIn(string? Notes);
public record StockBalanceOut(int Id, int? MaterialId, int? ProductId, string ItemCode, string ItemDescription, int LocationId, string LocationCode, StockLocationKind LocationKind, int? LotId, string? LotCode, LotStatus? LotStatus, decimal Quantity);
public record LocationQuantity(int LocationId, string LocationCode, StockLocationKind Kind, decimal Quantity);
public record AvailabilityOut(int? MaterialId, int? ProductId, decimal OnHand, decimal Released, decimal Blocked, decimal AtThirdParty, decimal Reserved, decimal Free, decimal AverageCost, IReadOnlyList<LocationQuantity> ByLocation);
public record StockLotOut(int Id, int? MaterialId, int? ProductId, string ItemCode, string Code, LotStatus Status, int? SupplierId, string? InvoiceNumber, string? HeatNumber, DateOnly ReceivedOn, string? InspectionNote, string? InspectedBy, DateTimeOffset? InspectedAt, decimal Quantity);
public record InspectionIn(LotStatus Status, string? Note);
public record ReservationIn(int? MaterialId, int? ProductId, int? LocationId, decimal Quantity, string Reference, DateOnly? NeededOn);
public record ReservationOut(int Id, int? MaterialId, int? ProductId, int? LocationId, decimal Quantity, decimal Consumed, decimal Remaining, ReservationStatus Status, string Reference, DateOnly? NeededOn, string CreatedBy, DateTimeOffset CreatedAt);
public record StockSettingsIn(bool AllowNegativeStock, bool DeductIcmsFromAverage, decimal CuttingServicePerKg, decimal ScrapResalePerKg, decimal ScrapPercent);
public record ClosingOut(int Period, string ClosedBy, DateTimeOffset ClosedAt);
public record AverageCostOut(int Period, decimal? ThicknessMm, int? MaterialId, decimal OpeningQuantity, decimal OpeningAverage, decimal PurchaseQuantity, decimal PurchaseValue, decimal ServiceQuantity, decimal ServiceValue, decimal MonthAverage, decimal Average, decimal AverageGross, bool Imported);

public static class InventoryEndpoints
{
    public static void MapInventory(this WebApplication app)
    {
        app.MapGroup("/api/stock-locations").WithTags("Stock").MapCrud(new CrudSpec<StockLocation, StockLocationIn, StockLocationOut>
        {
            Project = l => new StockLocationOut(l.Id, l.Code, l.Name, l.Kind, l.Active),
            Create = i => new StockLocation { Code = i.Code.Trim().ToUpper(), Name = i.Name.Trim(), Kind = i.Kind, Active = i.Active },
            Apply = (i, l) => { l.Code = i.Code.Trim().ToUpper(); l.Name = i.Name.Trim(); l.Kind = i.Kind; l.Active = i.Active; },
            Validate = (i, _, _) => Task.FromResult(Errors().Require(Has(i.Code), "code", "Required").Require(Has(i.Name), "name", "Required")),
            Search = (q, s) => q.Where(l => EF.Functions.ILike(l.Code, $"%{s}%") || EF.Functions.ILike(l.Name, $"%{s}%")),
            Order = q => q.OrderBy(l => l.Code),
            BeforeDelete = async (id, db, ct) => await db.StockMovements.AnyAsync(m => m.LocationId == id, ct) ? "Location has movements; deactivate it instead" : null,
            WritePolicy = Policies.Stock
        });

        var stock = app.MapGroup("/api/stock").WithTags("Stock").RequireAuthorization(Policies.Read);

        stock.MapPost("/documents", async (StockPost post, StockService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var doc = await svc.PostAsync(post, User(user), ct);
            return Results.Created($"/api/stock/documents/{doc.Id}", await LoadDocument(db, doc.Id, ct));
        }).RequireAuthorization(Policies.Stock);

        stock.MapPost("/documents/{id:int}/reverse", async (int id, ReverseIn? body, StockService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var doc = await svc.ReverseAsync(id, User(user), body?.Notes, ct);
            return Results.Created($"/api/stock/documents/{doc.Id}", await LoadDocument(db, doc.Id, ct));
        }).RequireAuthorization(Policies.Stock);

        stock.MapGet("/documents", async (EbtDbContext db, MovementType? type, DateOnly? from, DateOnly? to, string? reference, int? skip, int? take, CancellationToken ct) =>
        {
            var q = db.StockDocuments.AsNoTracking();
            if (type is { } t) q = q.Where(d => d.Type == t);
            if (from is { } f) q = q.Where(d => d.Date >= f);
            if (to is { } u) q = q.Where(d => d.Date <= u);
            if (Has(reference)) q = q.Where(d => d.Reference == reference!.Trim());
            var total = await q.CountAsync(ct);
            var (s, n) = Paging(skip, take);
            var items = await q.OrderByDescending(d => d.Date).ThenByDescending(d => d.Id).Skip(s).Take(n)
                .Select(d => new StockDocumentSummary(d.Id, d.Type, d.Date, d.Reference, d.SupplierId, d.CustomerId, d.ReversalOfId, d.Reversed, d.CreatedBy, d.CreatedAt, d.Movements.Count))
                .ToListAsync(ct);
            return Results.Ok(new Page<StockDocumentSummary>(items, total, s, n));
        });

        stock.MapGet("/documents/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
            await LoadDocument(db, id, ct) is { } d ? Results.Ok(d) : Results.NotFound());

        stock.MapGet("/movements", async (EbtDbContext db, int? materialId, int? productId, int? locationId, int? lotId, DateOnly? from, DateOnly? to, int? skip, int? take, CancellationToken ct) =>
        {
            var q = db.StockMovements.AsNoTracking();
            if (materialId is { } m) q = q.Where(x => x.MaterialId == m);
            if (productId is { } p) q = q.Where(x => x.ProductId == p);
            if (locationId is { } l) q = q.Where(x => x.LocationId == l);
            if (lotId is { } lot) q = q.Where(x => x.LotId == lot);
            var opening = from is { } f0 ? await q.Where(x => x.Date < f0).SumAsync(x => x.Quantity, ct) : 0m;
            if (from is { } f) q = q.Where(x => x.Date >= f);
            if (to is { } u) q = q.Where(x => x.Date <= u);
            var total = await q.CountAsync(ct);
            var (s, n) = Paging(skip, take);
            var ordered = q.OrderBy(x => x.Date).ThenBy(x => x.Id);
            var running = opening + (s > 0 ? await ordered.Take(s).SumAsync(x => x.Quantity, ct) : 0m);
            var rows = await ordered.Skip(s).Take(n).Select(MovementProjection).ToListAsync(ct);
            var single = (materialId is null) != (productId is null);
            var items = rows.Select(r => single ? r with { BalanceAfter = running += r.Quantity } : r).ToList();
            return Results.Ok(new Page<StockMovementOut>(items, total, s, n));
        });

        stock.MapGet("/balances", async (EbtDbContext db, int? materialId, int? productId, int? locationId, int? lotId, string? q, bool? includeZero, int? skip, int? take, CancellationToken ct) =>
        {
            var b = db.StockBalances.AsNoTracking();
            if (materialId is { } m) b = b.Where(x => x.MaterialId == m);
            if (productId is { } p) b = b.Where(x => x.ProductId == p);
            if (locationId is { } l) b = b.Where(x => x.LocationId == l);
            if (lotId is { } lot) b = b.Where(x => x.LotId == lot);
            if (includeZero != true) b = b.Where(x => x.Quantity != 0);
            if (Has(q)) b = b.Where(x => EF.Functions.ILike(x.Material != null ? x.Material.Code : x.Product!.Code, $"%{q!.Trim()}%"));
            var total = await b.CountAsync(ct);
            var (s, n) = Paging(skip, take);
            var items = await b.OrderBy(x => x.Material != null ? x.Material.Code : x.Product!.Code).ThenBy(x => x.Location!.Code).ThenBy(x => x.LotId).Skip(s).Take(n)
                .Select(x => new StockBalanceOut(x.Id, x.MaterialId, x.ProductId, x.Material != null ? x.Material.Code : x.Product!.Code, x.Material != null ? x.Material.Description : x.Product!.Name,
                    x.LocationId, x.Location!.Code, x.Location.Kind, x.LotId, x.Lot != null ? x.Lot.Code : null, x.Lot != null ? x.Lot.Status : null, x.Quantity))
                .ToListAsync(ct);
            return Results.Ok(new Page<StockBalanceOut>(items, total, s, n));
        });

        stock.MapGet("/availability", async (EbtDbContext db, StockService svc, int? materialId, int? productId, CancellationToken ct) =>
        {
            if ((materialId is null) == (productId is null)) return Results.ValidationProblem(Errors().Require(false, "materialId", "Give either materialId or productId"));
            var exists = materialId is { } mid ? await db.Materials.AnyAsync(x => x.Id == mid, ct) : await db.Products.AnyAsync(x => x.Id == productId, ct);
            if (!exists) return Results.NotFound();
            var rows = await db.StockBalances.AsNoTracking().Where(b => b.MaterialId == materialId && b.ProductId == productId)
                .Select(b => new { b.LocationId, b.Location!.Code, b.Location.Kind, b.Quantity, Released = b.LotId == null || b.Lot!.Status == LotStatus.Released })
                .ToListAsync(ct);
            var own = rows.Where(r => r.Kind != StockLocationKind.ThirdParty).ToList();
            var released = own.Where(r => r.Released && r.Kind != StockLocationKind.Quarantine).Sum(r => r.Quantity);
            var reserved = await db.StockReservations.Where(r => r.MaterialId == materialId && r.ProductId == productId && r.Status == ReservationStatus.Open).SumAsync(r => r.Quantity - r.Consumed, ct);
            var avg = materialId is { } m ? await svc.CurrentAverageAsync(m, DateOnly.FromDateTime(DateTime.Today), ct) : 0m;
            var byLocation = rows.GroupBy(r => new { r.LocationId, r.Code, r.Kind }).Select(g => new LocationQuantity(g.Key.LocationId, g.Key.Code, g.Key.Kind, g.Sum(r => r.Quantity))).Where(x => x.Quantity != 0).OrderBy(x => x.LocationCode).ToList();
            return Results.Ok(new AvailabilityOut(materialId, productId, own.Sum(r => r.Quantity), released, own.Sum(r => r.Quantity) - released,
                rows.Where(r => r.Kind == StockLocationKind.ThirdParty).Sum(r => r.Quantity), reserved, await svc.FreeQuantityAsync(new StockItem(materialId, productId), null, ct), avg, byLocation));
        });

        stock.MapGet("/lots", async (EbtDbContext db, int? materialId, int? productId, LotStatus? status, string? q, int? skip, int? take, CancellationToken ct) =>
        {
            var l = db.StockLots.AsNoTracking();
            if (materialId is { } m) l = l.Where(x => x.MaterialId == m);
            if (productId is { } p) l = l.Where(x => x.ProductId == p);
            if (status is { } st) l = l.Where(x => x.Status == st);
            if (Has(q)) l = l.Where(x => x.Code == q!.Trim() || x.InvoiceNumber == q.Trim() || x.HeatNumber == q.Trim());
            var total = await l.CountAsync(ct);
            var (s, n) = Paging(skip, take);
            var items = await l.OrderByDescending(x => x.ReceivedOn).ThenByDescending(x => x.Id).Skip(s).Take(n).Select(LotProjection(db)).ToListAsync(ct);
            return Results.Ok(new Page<StockLotOut>(items, total, s, n));
        });

        stock.MapGet("/lots/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
            await db.StockLots.AsNoTracking().Where(x => x.Id == id).Select(LotProjection(db)).FirstOrDefaultAsync(ct) is { } lot ? Results.Ok(lot) : Results.NotFound());

        stock.MapPut("/lots/{id:int}/inspection", async (int id, InspectionIn body, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var lot = await db.StockLots.FindAsync([id], ct);
            if (lot is null) return Results.NotFound();
            if (body.Status == LotStatus.Rejected && !Has(body.Note)) return Results.ValidationProblem(Errors().Require(false, "note", "Required when rejecting"));
            lot.Status = body.Status;
            lot.InspectionNote = Clean(body.Note);
            lot.InspectedBy = User(user);
            lot.InspectedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
            return Results.Ok(await db.StockLots.AsNoTracking().Where(x => x.Id == id).Select(LotProjection(db)).FirstAsync(ct));
        }).RequireAuthorization(Policies.Stock);

        stock.MapGet("/reservations", async (EbtDbContext db, int? materialId, int? productId, string? reference, ReservationStatus? status, int? skip, int? take, CancellationToken ct) =>
        {
            var r = db.StockReservations.AsNoTracking();
            if (materialId is { } m) r = r.Where(x => x.MaterialId == m);
            if (productId is { } p) r = r.Where(x => x.ProductId == p);
            if (Has(reference)) r = r.Where(x => x.Reference == reference!.Trim());
            if (status is { } st) r = r.Where(x => x.Status == st);
            var total = await r.CountAsync(ct);
            var (s, n) = Paging(skip, take);
            var items = await r.OrderByDescending(x => x.Id).Skip(s).Take(n).Select(ReservationProjection).ToListAsync(ct);
            return Results.Ok(new Page<ReservationOut>(items, total, s, n));
        });

        stock.MapPost("/reservations", async (ReservationIn body, StockService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var r = await svc.ReserveAsync(new StockItem(body.MaterialId, body.ProductId), body.LocationId, body.Quantity, body.Reference, body.NeededOn, User(user), ct);
            return Results.Created($"/api/stock/reservations/{r.Id}", await db.StockReservations.AsNoTracking().Where(x => x.Id == r.Id).Select(ReservationProjection).FirstAsync(ct));
        }).RequireAuthorization(Policies.Stock);

        stock.MapPost("/reservations/{id:int}/release", async (int id, StockService svc, EbtDbContext db, CancellationToken ct) =>
        {
            await svc.ReleaseAsync(id, ct);
            return Results.Ok(await db.StockReservations.AsNoTracking().Where(x => x.Id == id).Select(ReservationProjection).FirstAsync(ct));
        }).RequireAuthorization(Policies.Stock);

        stock.MapGet("/settings", async (StockService svc, CancellationToken ct) => Results.Ok(ToIn(await svc.SettingsAsync(ct))));

        stock.MapPut("/settings", async (StockSettingsIn body, EbtDbContext db, StockService svc, CancellationToken ct) =>
        {
            var errors = Errors()
                .Require(body.CuttingServicePerKg >= 0, "cuttingServicePerKg", "Cannot be negative")
                .Require(body.ScrapResalePerKg >= 0, "scrapResalePerKg", "Cannot be negative")
                .Require(body.ScrapPercent is >= 0 and <= 100, "scrapPercent", "Between 0 and 100");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var s = await svc.SettingsAsync(ct);
            s.AllowNegativeStock = body.AllowNegativeStock;
            s.DeductIcmsFromAverage = body.DeductIcmsFromAverage;
            s.CuttingServicePerKg = body.CuttingServicePerKg;
            s.ScrapResalePerKg = body.ScrapResalePerKg;
            s.ScrapPercent = body.ScrapPercent;
            await db.SaveChangesAsync(ct);
            return Results.Ok(ToIn(s));
        }).RequireAuthorization(Policies.Admin);

        stock.MapGet("/closings", async (EbtDbContext db, CancellationToken ct) =>
            await db.StockClosings.AsNoTracking().OrderByDescending(c => c.Period).Select(c => new ClosingOut(c.Period, c.ClosedBy, c.ClosedAt)).ToListAsync(ct));

        stock.MapPost("/closings/{period:int}", async (int period, StockService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var c = await svc.ClosePeriodAsync(period, User(user), DateOnly.FromDateTime(DateTime.Today), ct);
            return Results.Created($"/api/stock/average-costs?period={period}", new ClosingOut(c.Period, c.ClosedBy, c.ClosedAt));
        }).RequireAuthorization(Policies.Stock);

        stock.MapDelete("/closings/{period:int}", async (int period, StockService svc, CancellationToken ct) =>
        {
            await svc.ReopenPeriodAsync(period, ct);
            return Results.NoContent();
        }).RequireAuthorization(Policies.Admin);

        stock.MapGet("/average-costs", async (EbtDbContext db, int? period, decimal? thicknessMm, int? materialId, CancellationToken ct) =>
        {
            var q = db.AverageCosts.AsNoTracking();
            if (period is { } p) q = q.Where(a => a.Period == p);
            if (thicknessMm is { } t) q = q.Where(a => a.ThicknessMm == t);
            if (materialId is { } m) q = q.Where(a => a.MaterialId == m);
            return await q.OrderByDescending(a => a.Period).ThenBy(a => a.ThicknessMm).ThenBy(a => a.MaterialId).Take(1000).Select(AverageProjection).ToListAsync(ct);
        });

        stock.MapGet("/average-costs/preview", async (int period, StockService svc, CancellationToken ct) =>
            (await svc.ComputeAveragesAsync(period, ct)).AsQueryable().Select(AverageProjection).ToList());
    }

    private static readonly System.Linq.Expressions.Expression<Func<StockMovement, StockMovementOut>> MovementProjection = x =>
        new StockMovementOut(x.Id, x.DocumentId, x.Type, x.Date, x.MaterialId, x.ProductId, x.Material != null ? x.Material.Code : x.Product!.Code, x.LocationId, x.Location!.Code,
            x.LotId, x.Lot != null ? x.Lot.Code : null, x.Quantity, x.UnitCost, x.IcmsRate, x.ReservationId, x.Document!.Reference, null);

    private static readonly System.Linq.Expressions.Expression<Func<StockReservation, ReservationOut>> ReservationProjection = r =>
        new ReservationOut(r.Id, r.MaterialId, r.ProductId, r.LocationId, r.Quantity, r.Consumed, r.Status == ReservationStatus.Open ? r.Quantity - r.Consumed : 0, r.Status, r.Reference, r.NeededOn, r.CreatedBy, r.CreatedAt);

    private static readonly System.Linq.Expressions.Expression<Func<AverageCost, AverageCostOut>> AverageProjection = a =>
        new AverageCostOut(a.Period, a.ThicknessMm, a.MaterialId, a.OpeningQuantity, a.OpeningAverage, a.PurchaseQuantity, a.PurchaseValue, a.ServiceQuantity, a.ServiceValue, a.MonthAverage, a.Average, a.AverageGross, a.Imported);

    private static System.Linq.Expressions.Expression<Func<StockLot, StockLotOut>> LotProjection(EbtDbContext db) => x =>
        new StockLotOut(x.Id, x.MaterialId, x.ProductId, x.Material != null ? x.Material.Code : x.Product!.Code, x.Code, x.Status, x.SupplierId, x.InvoiceNumber, x.HeatNumber, x.ReceivedOn,
            x.InspectionNote, x.InspectedBy, x.InspectedAt, db.StockBalances.Where(b => b.LotId == x.Id).Sum(b => b.Quantity));

    private static async Task<StockDocumentOut?> LoadDocument(EbtDbContext db, int id, CancellationToken ct)
    {
        var d = await db.StockDocuments.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        if (d is null) return null;
        var moves = await db.StockMovements.AsNoTracking().Where(m => m.DocumentId == id).OrderBy(m => m.Id).Select(MovementProjection).ToListAsync(ct);
        return new StockDocumentOut(d.Id, d.Type, d.Date, d.Reference, d.SupplierId, d.CustomerId, d.Notes, d.ReversalOfId, d.Reversed, d.CreatedBy, d.CreatedAt, moves);
    }

    private static StockSettingsIn ToIn(StockSettings s) => new(s.AllowNegativeStock, s.DeductIcmsFromAverage, s.CuttingServicePerKg, s.ScrapResalePerKg, s.ScrapPercent);
    private static (int, int) Paging(int? skip, int? take) => (Math.Max(skip ?? 0, 0), Math.Clamp(take ?? 50, 1, 500));
    private static string User(ClaimsPrincipal p) => p.Identity?.Name ?? "unknown";
}
