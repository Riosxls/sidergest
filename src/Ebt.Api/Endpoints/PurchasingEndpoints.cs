using System.Security.Claims;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Purchasing;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record PurchasingSettingsDto(decimal ReceivingTolerancePercent, bool AllowEarlyReceipt, int EarlyReceiptGraceDays, int? ReceivingLocationId = null);

public record RequisitionIn(int? MaterialId, string? Description, string? Unit, decimal Quantity, string? Department, DateOnly? NeededBy, string? Application, string? Notes);
public record RequisitionDecisionIn(decimal? ApprovedQuantity, string? Note);
public record RequisitionOut(int Id, int Number, int? MaterialId, string? MaterialCode, string Description, string Unit, decimal Quantity, decimal? ApprovedQuantity, string? Department, DateOnly? NeededBy, string? Application, string? Notes, RequisitionStatus Status, string? RequestedBy, DateTimeOffset RequestedAt, string? DecidedBy, DateTimeOffset? DecidedAt, string? DecisionNote, int? QuotationId, int? QuotationNumber, int? PurchaseOrderId, int? PurchaseOrderNumber);

public record QuotationIn(IReadOnlyList<int> RequisitionIds, IReadOnlyList<int> SupplierIds, string? Notes);
public record QuotationSupplierIn(int SupplierId);
public record AwardIn(int BidId);
public record BidOut(int Id, int SupplierId, string SupplierName, decimal? UnitPrice, decimal DiscountPercent, decimal IcmsPercent, decimal IpiPercent, int? LeadTimeDays, string? PaymentTerms, string? Notes, BidStatus Status, DateTimeOffset? RespondedAt);
public record QuotationItemOut(int Id, int Item, int? MaterialId, string? MaterialCode, string Description, string Unit, decimal Quantity, IReadOnlyList<int> RequisitionNumbers, IReadOnlyList<BidOut> Bids);
public record QuotationOut(int Id, int Number, QuotationStatus Status, string? Notes, string? CreatedBy, DateTimeOffset CreatedAt, IReadOnlyList<QuotationItemOut> Items);
public record QuotationSummaryOut(int Id, int Number, QuotationStatus Status, DateTimeOffset CreatedAt, int ItemCount, int SupplierCount);
public record ComparisonBidOut(int BidId, int SupplierId, string SupplierName, decimal UnitPrice, decimal NetUnitPrice, decimal LandedUnitPrice, decimal LineTotal, int? LeadTimeDays, string? PaymentTerms, int Rank, BidStatus Status);
public record ComparisonItemOut(int ItemId, int Item, string Description, string Unit, decimal Quantity, decimal? LastUnitPrice, DateOnly? LastPurchaseDate, string? LastSupplierName, IReadOnlyList<ComparisonBidOut> Bids, IReadOnlyList<int> PendingSupplierIds);

public record OrderLineIn(int? MaterialId, string? Description, string? Unit, decimal Quantity, decimal UnitPrice, decimal DiscountPercent, decimal IcmsPercent, decimal IpiPercent, DateOnly DueDate, IReadOnlyList<int>? RequisitionIds);
public record OrderIn(int SupplierId, string? PaymentTerms, string? Notes, IReadOnlyList<OrderLineIn> Lines);
public record OrderFromQuotationIn(int QuotationId, int SupplierId, string? Notes);
public record ReasonIn(string? Reason);
public record DueDateIn(DateOnly DueDate);
public record OrderLineOut(int Id, int LineNumber, int? MaterialId, string? MaterialCode, string Description, string Unit, decimal Quantity, decimal UnitPrice, decimal DiscountPercent, decimal IcmsPercent, decimal IpiPercent, DateOnly DueDate, decimal ReceivedQuantity, decimal OpenQuantity, bool Closed, int? QuotationBidId, decimal Total);
public record OrderOut(int Id, int Number, int SupplierId, string SupplierName, PurchaseOrderStatus Status, string? PaymentTerms, string? Notes, string? IssuedBy, DateTimeOffset IssuedAt, string? ClosedBy, DateTimeOffset? ClosedAt, string? CloseReason, decimal Total, IReadOnlyList<OrderLineOut> Lines);
public record OrderSummaryOut(int Id, int Number, int SupplierId, string SupplierName, PurchaseOrderStatus Status, DateTimeOffset IssuedAt, DateOnly? NextDueDate, int LineCount);

public record ReceiptLineIn(int PurchaseOrderLineId, decimal Quantity, decimal? UnitPrice, string? LotCode);
public record ReceiptIn(int SupplierId, string InvoiceNumber, string? InvoiceSeries, DateOnly InvoiceDate, DateTimeOffset? ReceivedAt, decimal? InvoiceTotal, string? DivergenceJustification, string? Notes, IReadOnlyList<ReceiptLineIn> Lines);
public record ReceiptLineOut(int Id, int PurchaseOrderId, int PurchaseOrderNumber, int PurchaseOrderLineId, int? MaterialId, string? MaterialCode, string Description, decimal Quantity, string Unit, decimal UnitPrice, decimal DiscountPercent, decimal IcmsPercent, decimal IpiPercent, decimal Total, string? LotCode);
public record InstallmentOut(int Sequence, DateOnly DueDate, decimal Amount);
public record ReceiptOut(int Id, int Number, int SupplierId, string SupplierName, string InvoiceNumber, string InvoiceSeries, DateOnly InvoiceDate, DateTimeOffset ReceivedAt, string? ReceivedBy, decimal? InvoiceTotal, decimal CalculatedTotal, bool Divergent, string? DivergenceJustification, string? Notes, IReadOnlyList<ReceiptLineOut> Lines, IReadOnlyList<InstallmentOut> Installments);
public record ReceiptSummaryOut(int Id, int Number, int SupplierId, string SupplierName, string InvoiceNumber, string InvoiceSeries, DateOnly InvoiceDate, DateTimeOffset ReceivedAt, decimal CalculatedTotal, bool Divergent);

public record OverdueLineOut(int PurchaseOrderId, int PurchaseOrderNumber, int LineId, int LineNumber, int SupplierId, string SupplierName, string Description, string Unit, decimal Quantity, decimal ReceivedQuantity, decimal OpenQuantity, DateOnly DueDate, int DaysLate);
public record SupplierMaterialIn(string? Qualification, DateOnly? QualifiedAt, string? Notes);
public record SupplierMaterialOut(int SupplierId, int MaterialId, string MaterialCode, string MaterialDescription, string? Qualification, DateOnly? QualifiedAt, decimal? LastUnitPrice, DateOnly? LastPurchaseDate, string? Notes);
public record SupplierPerformanceOut(int SupplierId, string SupplierName, int Orders, int OpenOrders, decimal OrderedValue, int Receipts, decimal ReceivedValue, int ReceivedLines, int OnTimeLines, decimal OnTimePercent, decimal AverageDaysLate, int OverdueLines);
public record PurchaseHistoryOut(int ReceiptId, int ReceiptNumber, DateOnly InvoiceDate, string InvoiceNumber, int SupplierId, string SupplierName, int PurchaseOrderNumber, decimal Quantity, string Unit, decimal NetUnitPrice, decimal Total);

public static class PurchasingPolicies
{
    public const string Request = "purchasing-request";
    public const string Buy = "purchasing";
    public const string Receive = "receiving";
}

public sealed class PurchasingExceptionHandler : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception exception, CancellationToken ct)
    {
        if (exception is not PurchasingException e) return false;
        var result = e.Field is not null && e.Status == StatusCodes.Status400BadRequest
            ? Results.ValidationProblem(new Dictionary<string, string[]> { [e.Field] = [e.Message] })
            : Results.Problem(e.Message, statusCode: e.Status);
        await result.ExecuteAsync(http);
        return true;
    }
}

public static class PurchasingEndpoints
{
    public static IServiceCollection AddPurchasing(this IServiceCollection services)
    {
        services.AddScoped<PurchasingService>();
        services.AddScoped<IGoodsReceiptHandler, StockReceiptHandler>();
        services.AddExceptionHandler<PurchasingExceptionHandler>();
        services.AddAuthorization(o =>
        {
            o.AddPolicy(PurchasingPolicies.Request, p => p.RequireRole(nameof(UserRole.Admin), nameof(UserRole.Engineering), nameof(UserRole.Stock), nameof(UserRole.Purchasing)));
            o.AddPolicy(PurchasingPolicies.Buy, p => p.RequireRole(nameof(UserRole.Admin), nameof(UserRole.Purchasing)));
            o.AddPolicy(PurchasingPolicies.Receive, p => p.RequireRole(nameof(UserRole.Admin), nameof(UserRole.Purchasing), nameof(UserRole.Stock)));
        });
        return services;
    }

    private static string? Who(ClaimsPrincipal user) => user.Identity?.Name;

    public static void MapPurchasing(this WebApplication app)
    {
        MapSettings(app);
        MapRequisitions(app);
        MapQuotations(app);
        MapOrders(app);
        MapReceipts(app);
        MapTracking(app);
    }

    private static void MapSettings(WebApplication app)
    {
        var g = app.MapGroup("/api/purchasing/settings").WithTags("Purchasing");
        g.MapGet("/", async (EbtDbContext db, CancellationToken ct) =>
            await db.PurchasingSettings.AsNoTracking().Select(s => new PurchasingSettingsDto(s.ReceivingTolerancePercent, s.AllowEarlyReceipt, s.EarlyReceiptGraceDays, s.ReceivingLocationId)).FirstAsync(ct))
            .RequireAuthorization(Policies.Read);
        g.MapPut("/", async (PurchasingSettingsDto i, EbtDbContext db, CancellationToken ct) =>
        {
            var errors = Errors()
                .Require(i.ReceivingTolerancePercent is >= 0 and <= 100, "receivingTolerancePercent", "Between 0 and 100")
                .Require(i.EarlyReceiptGraceDays is >= 0 and <= 365, "earlyReceiptGraceDays", "Between 0 and 365");
            if (i.ReceivingLocationId is { } lid)
                errors.Require(await db.StockLocations.AnyAsync(l => l.Id == lid && l.Active && l.Kind != StockLocationKind.ThirdParty, ct), "receivingLocationId", "Unknown, inactive or third-party location");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var s = await db.PurchasingSettings.FirstAsync(ct);
            s.ReceivingTolerancePercent = i.ReceivingTolerancePercent;
            s.AllowEarlyReceipt = i.AllowEarlyReceipt;
            s.EarlyReceiptGraceDays = i.EarlyReceiptGraceDays;
            s.ReceivingLocationId = i.ReceivingLocationId;
            await db.SaveChangesAsync(ct);
            return Results.Ok(i);
        }).RequireAuthorization(Policies.Admin);
    }

    private static IQueryable<RequisitionOut> ProjectRequisitions(IQueryable<PurchaseRequisition> q) => q.Select(r => new RequisitionOut(
        r.Id, r.Number, r.MaterialId, r.Material != null ? r.Material.Code : null, r.Description, r.Unit, r.Quantity, r.ApprovedQuantity, r.Department, r.NeededBy,
        r.Application, r.Notes, r.Status, r.RequestedBy, r.RequestedAt, r.DecidedBy, r.DecidedAt, r.DecisionNote,
        r.QuotationItem != null ? r.QuotationItem.QuotationId : null, r.QuotationItem != null ? r.QuotationItem.Quotation!.Number : null,
        r.PurchaseOrderLine != null ? r.PurchaseOrderLine.PurchaseOrderId : null, r.PurchaseOrderLine != null ? r.PurchaseOrderLine.PurchaseOrder!.Number : null));

    private static async Task<RequisitionOut> RequisitionAsync(EbtDbContext db, int id, CancellationToken ct) =>
        await ProjectRequisitions(db.PurchaseRequisitions.AsNoTracking().Where(r => r.Id == id)).FirstAsync(ct);

    private static void MapRequisitions(WebApplication app)
    {
        var g = app.MapGroup("/api/requisitions").WithTags("Requisitions");

        g.MapGet("/", async (EbtDbContext db, string? q, RequisitionStatus? status, int? materialId, string? department, int? skip, int? take, CancellationToken ct) =>
        {
            var query = db.PurchaseRequisitions.AsNoTracking();
            if (status is { } st) query = query.Where(r => r.Status == st);
            if (materialId is { } m) query = query.Where(r => r.MaterialId == m);
            if (Clean(department) is { } d) query = query.Where(r => r.Department == d);
            if (Clean(q) is { } s) query = query.Where(r => EF.Functions.ILike(r.Description, $"%{s}%") || r.Number.ToString() == s);
            return await PageAsync(ProjectRequisitions(query.OrderByDescending(r => r.Number)), query, skip, take, ct);
        }).RequireAuthorization(Policies.Read);

        g.MapGet("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
            await ProjectRequisitions(db.PurchaseRequisitions.AsNoTracking().Where(r => r.Id == id)).FirstOrDefaultAsync(ct) is { } r ? Results.Ok(r) : Results.NotFound())
            .RequireAuthorization(Policies.Read);

        g.MapPost("/", async (RequisitionIn i, PurchasingService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var r = await svc.CreateRequisitionAsync(new RequisitionInput(i.MaterialId, i.Description, i.Unit, i.Quantity, i.Department, i.NeededBy, i.Application, i.Notes), Who(user), ct);
            return Results.Created($"/api/requisitions/{r.Id}", await RequisitionAsync(db, r.Id, ct));
        }).RequireAuthorization(PurchasingPolicies.Request);

        g.MapPost("/{id:int}/approve", async (int id, RequisitionDecisionIn i, PurchasingService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.DecideRequisitionAsync(id, true, i.ApprovedQuantity, i.Note, Who(user), ct);
            return Results.Ok(await RequisitionAsync(db, id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);

        g.MapPost("/{id:int}/reject", async (int id, RequisitionDecisionIn i, PurchasingService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.DecideRequisitionAsync(id, false, null, i.Note, Who(user), ct);
            return Results.Ok(await RequisitionAsync(db, id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);

        g.MapPost("/{id:int}/cancel", async (int id, ReasonIn i, PurchasingService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.CancelRequisitionAsync(id, i.Reason, Who(user), ct);
            return Results.Ok(await RequisitionAsync(db, id, ct));
        }).RequireAuthorization(PurchasingPolicies.Request);
    }

    private static async Task<QuotationOut?> QuotationAsync(EbtDbContext db, int id, CancellationToken ct)
    {
        var q = await db.Quotations.AsNoTracking().AsSplitQuery()
            .Include(x => x.Items).ThenInclude(i => i.Material)
            .Include(x => x.Items).ThenInclude(i => i.Requisitions)
            .Include(x => x.Items).ThenInclude(i => i.Bids).ThenInclude(b => b.Supplier)
            .FirstOrDefaultAsync(x => x.Id == id, ct);
        return q is null ? null : new QuotationOut(q.Id, q.Number, q.Status, q.Notes, q.CreatedBy, q.CreatedAt, q.Items.OrderBy(i => i.Item).Select(i => new QuotationItemOut(
            i.Id, i.Item, i.MaterialId, i.Material?.Code, i.Description, i.Unit, i.Quantity, i.Requisitions.Select(r => r.Number).Order().ToList(),
            i.Bids.OrderBy(b => b.Supplier!.Name).Select(b => new BidOut(b.Id, b.SupplierId, b.Supplier!.Name, b.UnitPrice, b.DiscountPercent, b.IcmsPercent, b.IpiPercent, b.LeadTimeDays, b.PaymentTerms, b.Notes, b.Status, b.RespondedAt)).ToList())).ToList());
    }

    private static void MapQuotations(WebApplication app)
    {
        var g = app.MapGroup("/api/quotations").WithTags("Quotations");

        g.MapGet("/", async (EbtDbContext db, QuotationStatus? status, int? supplierId, int? skip, int? take, CancellationToken ct) =>
        {
            var query = db.Quotations.AsNoTracking();
            if (status is { } st) query = query.Where(q => q.Status == st);
            if (supplierId is { } sid) query = query.Where(q => q.Items.Any(i => i.Bids.Any(b => b.SupplierId == sid)));
            var projected = query.OrderByDescending(q => q.Number).Select(q => new QuotationSummaryOut(q.Id, q.Number, q.Status, q.CreatedAt, q.Items.Count, q.Items.SelectMany(i => i.Bids).Select(b => b.SupplierId).Distinct().Count()));
            return await PageAsync(projected, query, skip, take, ct);
        }).RequireAuthorization(Policies.Read);

        g.MapGet("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
            await QuotationAsync(db, id, ct) is { } q ? Results.Ok(q) : Results.NotFound()).RequireAuthorization(Policies.Read);

        g.MapPost("/", async (QuotationIn i, PurchasingService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var q = await svc.CreateQuotationAsync(i.RequisitionIds ?? [], i.SupplierIds ?? [], i.Notes, Who(user), ct);
            return Results.Created($"/api/quotations/{q.Id}", await QuotationAsync(db, q.Id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);

        g.MapPost("/{id:int}/suppliers", async (int id, QuotationSupplierIn i, PurchasingService svc, EbtDbContext db, CancellationToken ct) =>
        {
            await svc.AddQuotationSupplierAsync(id, i.SupplierId, ct);
            return Results.Ok(await QuotationAsync(db, id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);

        g.MapPut("/{id:int}/bids/{bidId:int}", async (int id, int bidId, BidInput i, PurchasingService svc, EbtDbContext db, CancellationToken ct) =>
        {
            if (!await db.QuotationBids.AnyAsync(b => b.Id == bidId && b.QuotationItem!.QuotationId == id, ct)) return Results.NotFound();
            await svc.RecordBidAsync(bidId, i, ct);
            return Results.Ok(await QuotationAsync(db, id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);

        g.MapPost("/{id:int}/items/{itemId:int}/award", async (int id, int itemId, AwardIn i, PurchasingService svc, EbtDbContext db, CancellationToken ct) =>
        {
            await svc.AwardAsync(id, itemId, i.BidId, ct);
            return Results.Ok(await QuotationAsync(db, id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);

        g.MapPost("/{id:int}/items/{itemId:int}/reject", async (int id, int itemId, PurchasingService svc, EbtDbContext db, CancellationToken ct) =>
        {
            await svc.RejectItemAsync(id, itemId, ct);
            return Results.Ok(await QuotationAsync(db, id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);

        g.MapPost("/{id:int}/cancel", async (int id, PurchasingService svc, EbtDbContext db, CancellationToken ct) =>
        {
            await svc.CancelQuotationAsync(id, ct);
            return Results.Ok(await QuotationAsync(db, id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);

        g.MapGet("/{id:int}/comparison", async (int id, EbtDbContext db, CancellationToken ct) =>
        {
            var q = await db.Quotations.AsNoTracking().AsSplitQuery().Include(x => x.Items).ThenInclude(i => i.Bids).ThenInclude(b => b.Supplier).FirstOrDefaultAsync(x => x.Id == id, ct);
            if (q is null) return Results.NotFound();
            var materialIds = q.Items.Where(i => i.MaterialId != null).Select(i => i.MaterialId!.Value).ToList();
            var last = (await db.SupplierMaterials.AsNoTracking().Where(s => materialIds.Contains(s.MaterialId) && s.LastPurchaseDate != null)
                    .Select(s => new { s.MaterialId, s.LastUnitPrice, s.LastPurchaseDate, s.Supplier!.Name }).ToListAsync(ct))
                .GroupBy(s => s.MaterialId).ToDictionary(g => g.Key, g => g.OrderByDescending(s => s.LastPurchaseDate).First());
            return Results.Ok(q.Items.OrderBy(i => i.Item).Select(i =>
            {
                var priced = i.Bids.Where(b => b.UnitPrice != null).Select(b =>
                {
                    var net = PurchasingService.NetUnitPrice(b.UnitPrice!.Value, b.DiscountPercent);
                    return (b, net, landed: net * (1 + b.IpiPercent / 100m));
                }).OrderBy(x => x.landed).ThenBy(x => x.b.LeadTimeDays ?? int.MaxValue).ToList();
                var l = i.MaterialId is { } mid && last.TryGetValue(mid, out var x) ? x : null;
                return new ComparisonItemOut(i.Id, i.Item, i.Description, i.Unit, i.Quantity, l?.LastUnitPrice, l?.LastPurchaseDate, l?.Name,
                    priced.Select((p, idx) => new ComparisonBidOut(p.b.Id, p.b.SupplierId, p.b.Supplier!.Name, p.b.UnitPrice!.Value, Math.Round(p.net, 6), Math.Round(p.landed, 6),
                        PurchasingService.LineTotal(i.Quantity, p.b.UnitPrice!.Value, p.b.DiscountPercent, p.b.IpiPercent), p.b.LeadTimeDays, p.b.PaymentTerms, idx + 1, p.b.Status)).ToList(),
                    i.Bids.Where(b => b.UnitPrice == null).Select(b => b.SupplierId).ToList());
            }).ToList());
        }).RequireAuthorization(Policies.Read);
    }

    private static async Task<OrderOut?> OrderAsync(EbtDbContext db, int id, CancellationToken ct)
    {
        var o = await db.PurchaseOrders.AsNoTracking().Include(x => x.Supplier).Include(x => x.Lines).ThenInclude(l => l.Material).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (o is null) return null;
        var lines = o.Lines.OrderBy(l => l.LineNumber).Select(l => new OrderLineOut(l.Id, l.LineNumber, l.MaterialId, l.Material?.Code, l.Description, l.Unit, l.Quantity, l.UnitPrice,
            l.DiscountPercent, l.IcmsPercent, l.IpiPercent, l.DueDate, l.ReceivedQuantity, l.Closed ? 0 : Math.Max(l.Quantity - l.ReceivedQuantity, 0), l.Closed, l.QuotationBidId,
            PurchasingService.LineTotal(l.Quantity, l.UnitPrice, l.DiscountPercent, l.IpiPercent))).ToList();
        return new OrderOut(o.Id, o.Number, o.SupplierId, o.Supplier!.Name, o.Status, o.PaymentTerms, o.Notes, o.IssuedBy, o.IssuedAt, o.ClosedBy, o.ClosedAt, o.CloseReason, lines.Sum(l => l.Total), lines);
    }

    private static void MapOrders(WebApplication app)
    {
        var g = app.MapGroup("/api/purchase-orders").WithTags("Purchase orders");

        g.MapGet("/", async (EbtDbContext db, PurchaseOrderStatus? status, int? supplierId, int? materialId, bool? open, int? skip, int? take, CancellationToken ct) =>
        {
            var query = db.PurchaseOrders.AsNoTracking();
            if (status is { } st) query = query.Where(o => o.Status == st);
            if (open == true) query = query.Where(o => o.Status == PurchaseOrderStatus.Open || o.Status == PurchaseOrderStatus.PartiallyReceived);
            if (supplierId is { } sid) query = query.Where(o => o.SupplierId == sid);
            if (materialId is { } mid) query = query.Where(o => o.Lines.Any(l => l.MaterialId == mid));
            var projected = query.OrderByDescending(o => o.Number).Select(o => new OrderSummaryOut(o.Id, o.Number, o.SupplierId, o.Supplier!.Name, o.Status, o.IssuedAt,
                o.Lines.Where(l => !l.Closed && l.ReceivedQuantity < l.Quantity).Min(l => (DateOnly?)l.DueDate), o.Lines.Count));
            return await PageAsync(projected, query, skip, take, ct);
        }).RequireAuthorization(Policies.Read);

        g.MapGet("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
            await OrderAsync(db, id, ct) is { } o ? Results.Ok(o) : Results.NotFound()).RequireAuthorization(Policies.Read);

        g.MapPost("/", async (OrderIn i, PurchasingService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var o = await svc.CreateOrderAsync(new OrderInput(i.SupplierId, i.PaymentTerms, i.Notes, (i.Lines ?? []).Select(l => new OrderLineInput(
                l.MaterialId, l.Description, l.Unit, l.Quantity, l.UnitPrice, l.DiscountPercent, l.IcmsPercent, l.IpiPercent, l.DueDate, l.RequisitionIds)).ToList()), Who(user), ct);
            return Results.Created($"/api/purchase-orders/{o.Id}", await OrderAsync(db, o.Id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);

        g.MapPost("/from-quotation", async (OrderFromQuotationIn i, PurchasingService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var o = await svc.CreateOrderFromQuotationAsync(i.QuotationId, i.SupplierId, i.Notes, Who(user), ct);
            return Results.Created($"/api/purchase-orders/{o.Id}", await OrderAsync(db, o.Id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);

        g.MapPost("/{id:int}/cancel", async (int id, ReasonIn i, PurchasingService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.CancelOrderAsync(id, i.Reason, Who(user), ct);
            return Results.Ok(await OrderAsync(db, id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);

        g.MapPost("/{id:int}/close", async (int id, ReasonIn i, PurchasingService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.CloseOrderAsync(id, i.Reason, Who(user), ct);
            return Results.Ok(await OrderAsync(db, id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);

        g.MapPut("/{id:int}/lines/{lineId:int}/due-date", async (int id, int lineId, DueDateIn i, PurchasingService svc, EbtDbContext db, CancellationToken ct) =>
        {
            await svc.RescheduleLineAsync(id, lineId, i.DueDate, ct);
            return Results.Ok(await OrderAsync(db, id, ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);
    }

    private static async Task<ReceiptOut?> ReceiptAsync(EbtDbContext db, int id, CancellationToken ct)
    {
        var r = await db.GoodsReceipts.AsNoTracking().AsSplitQuery().Include(x => x.Supplier).Include(x => x.Installments)
            .Include(x => x.Lines).ThenInclude(l => l.Material).Include(x => x.Lines).ThenInclude(l => l.PurchaseOrderLine!).ThenInclude(l => l.PurchaseOrder)
            .FirstOrDefaultAsync(x => x.Id == id, ct);
        return r is null ? null : new ReceiptOut(r.Id, r.Number, r.SupplierId, r.Supplier!.Name, r.InvoiceNumber, r.InvoiceSeries, r.InvoiceDate, r.ReceivedAt, r.ReceivedBy,
            r.InvoiceTotal, r.CalculatedTotal, Divergent(r.InvoiceTotal, r.CalculatedTotal), r.DivergenceJustification, r.Notes,
            r.Lines.OrderBy(l => l.Id).Select(l => new ReceiptLineOut(l.Id, l.PurchaseOrderLine!.PurchaseOrderId, l.PurchaseOrderLine.PurchaseOrder!.Number, l.PurchaseOrderLineId, l.MaterialId,
                l.Material?.Code, l.PurchaseOrderLine.Description, l.Quantity, l.Unit, l.UnitPrice, l.DiscountPercent, l.IcmsPercent, l.IpiPercent, l.Total, l.LotCode)).ToList(),
            r.Installments.OrderBy(x => x.Sequence).Select(x => new InstallmentOut(x.Sequence, x.DueDate, x.Amount)).ToList());
    }

    private static bool Divergent(decimal? typed, decimal calculated) => typed is { } t && Math.Abs(t - calculated) > PurchasingService.DivergenceTolerance;

    private static void MapReceipts(WebApplication app)
    {
        var g = app.MapGroup("/api/goods-receipts").WithTags("Receiving");

        g.MapGet("/", async (EbtDbContext db, int? supplierId, int? purchaseOrderId, DateOnly? from, DateOnly? to, int? skip, int? take, CancellationToken ct) =>
        {
            var query = db.GoodsReceipts.AsNoTracking();
            if (supplierId is { } sid) query = query.Where(r => r.SupplierId == sid);
            if (purchaseOrderId is { } oid) query = query.Where(r => r.Lines.Any(l => l.PurchaseOrderLine!.PurchaseOrderId == oid));
            if (from is { } f) query = query.Where(r => r.InvoiceDate >= f);
            if (to is { } t) query = query.Where(r => r.InvoiceDate <= t);
            var projected = query.OrderByDescending(r => r.Number).Select(r => new ReceiptSummaryOut(r.Id, r.Number, r.SupplierId, r.Supplier!.Name, r.InvoiceNumber, r.InvoiceSeries,
                r.InvoiceDate, r.ReceivedAt, r.CalculatedTotal, r.InvoiceTotal != null && Math.Abs(r.InvoiceTotal.Value - r.CalculatedTotal) > PurchasingService.DivergenceTolerance));
            return await PageAsync(projected, query, skip, take, ct);
        }).RequireAuthorization(Policies.Read);

        g.MapGet("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
            await ReceiptAsync(db, id, ct) is { } r ? Results.Ok(r) : Results.NotFound()).RequireAuthorization(Policies.Read);

        g.MapPost("/", async (ReceiptIn i, PurchasingService svc, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var r = await svc.ReceiveAsync(new ReceiptInput(i.SupplierId, i.InvoiceNumber ?? "", i.InvoiceSeries, i.InvoiceDate, i.ReceivedAt, i.InvoiceTotal, i.DivergenceJustification, i.Notes,
                (i.Lines ?? []).Select(l => new ReceiptLineInput(l.PurchaseOrderLineId, l.Quantity, l.UnitPrice, l.LotCode)).ToList()), Who(user), ct);
            return Results.Created($"/api/goods-receipts/{r.Id}", await ReceiptAsync(db, r.Id, ct));
        }).RequireAuthorization(PurchasingPolicies.Receive);
    }

    private static void MapTracking(WebApplication app)
    {
        app.MapGet("/api/purchasing/overdue", async (EbtDbContext db, DateOnly? asOf, int? supplierId, CancellationToken ct) =>
        {
            var day = asOf ?? DateOnly.FromDateTime(DateTime.UtcNow);
            var query = db.PurchaseOrderLines.AsNoTracking().Where(l => !l.Closed && l.ReceivedQuantity < l.Quantity && l.DueDate < day
                && (l.PurchaseOrder!.Status == PurchaseOrderStatus.Open || l.PurchaseOrder.Status == PurchaseOrderStatus.PartiallyReceived));
            if (supplierId is { } sid) query = query.Where(l => l.PurchaseOrder!.SupplierId == sid);
            var rows = await query.OrderBy(l => l.DueDate).Select(l => new { l, o = l.PurchaseOrder!, s = l.PurchaseOrder!.Supplier!.Name }).ToListAsync(ct);
            return rows.Select(x => new OverdueLineOut(x.o.Id, x.o.Number, x.l.Id, x.l.LineNumber, x.o.SupplierId, x.s, x.l.Description, x.l.Unit, x.l.Quantity, x.l.ReceivedQuantity,
                x.l.Quantity - x.l.ReceivedQuantity, x.l.DueDate, day.DayNumber - x.l.DueDate.DayNumber)).ToList();
        }).WithTags("Purchasing").RequireAuthorization(Policies.Read);

        app.MapGet("/api/purchasing/materials/{id:int}/history", async (int id, EbtDbContext db, int? take, CancellationToken ct) =>
            await db.GoodsReceiptLines.AsNoTracking().Where(l => l.MaterialId == id).OrderByDescending(l => l.GoodsReceipt!.InvoiceDate).ThenByDescending(l => l.Id)
                .Take(Math.Clamp(take ?? 50, 1, 500))
                .Select(l => new PurchaseHistoryOut(l.GoodsReceiptId, l.GoodsReceipt!.Number, l.GoodsReceipt.InvoiceDate, l.GoodsReceipt.InvoiceNumber, l.GoodsReceipt.SupplierId,
                    l.GoodsReceipt.Supplier!.Name, l.PurchaseOrderLine!.PurchaseOrder!.Number, l.Quantity, l.Unit, l.UnitPrice * (1 - l.DiscountPercent / 100m), l.Total))
                .ToListAsync(ct)).WithTags("Purchasing").RequireAuthorization(Policies.Read);

        var sm = app.MapGroup("/api/suppliers/{supplierId:int}/materials").WithTags("Suppliers");
        sm.MapGet("/", async (int supplierId, EbtDbContext db, CancellationToken ct) =>
            await db.SupplierMaterials.AsNoTracking().Where(s => s.SupplierId == supplierId).OrderBy(s => s.Material!.Code)
                .Select(s => new SupplierMaterialOut(s.SupplierId, s.MaterialId, s.Material!.Code, s.Material.Description, s.Qualification, s.QualifiedAt, s.LastUnitPrice, s.LastPurchaseDate, s.Notes))
                .ToListAsync(ct)).RequireAuthorization(Policies.Read);
        sm.MapPut("/{materialId:int}", async (int supplierId, int materialId, SupplierMaterialIn i, EbtDbContext db, CancellationToken ct) =>
        {
            if (!await db.Suppliers.AnyAsync(s => s.Id == supplierId, ct) || !await db.Materials.AnyAsync(m => m.Id == materialId, ct)) return Results.NotFound();
            var s = await db.SupplierMaterials.FindAsync([supplierId, materialId], ct);
            if (s is null) db.SupplierMaterials.Add(s = new SupplierMaterial { SupplierId = supplierId, MaterialId = materialId });
            s.Qualification = Clean(i.Qualification)?.ToUpperInvariant();
            s.QualifiedAt = i.QualifiedAt;
            s.Notes = Clean(i.Notes);
            await db.SaveChangesAsync(ct);
            return Results.Ok(await db.SupplierMaterials.AsNoTracking().Where(x => x.SupplierId == supplierId && x.MaterialId == materialId)
                .Select(x => new SupplierMaterialOut(x.SupplierId, x.MaterialId, x.Material!.Code, x.Material.Description, x.Qualification, x.QualifiedAt, x.LastUnitPrice, x.LastPurchaseDate, x.Notes)).FirstAsync(ct));
        }).RequireAuthorization(PurchasingPolicies.Buy);
        sm.MapDelete("/{materialId:int}", async (int supplierId, int materialId, EbtDbContext db, CancellationToken ct) =>
            await db.SupplierMaterials.Where(x => x.SupplierId == supplierId && x.MaterialId == materialId).ExecuteDeleteAsync(ct) > 0 ? Results.NoContent() : Results.NotFound())
            .RequireAuthorization(PurchasingPolicies.Buy);

        app.MapGet("/api/suppliers/{supplierId:int}/performance", async (int supplierId, EbtDbContext db, DateOnly? from, DateOnly? to, CancellationToken ct) =>
        {
            var supplier = await db.Suppliers.AsNoTracking().FirstOrDefaultAsync(s => s.Id == supplierId, ct);
            if (supplier is null) return Results.NotFound();
            var f = from ?? DateOnly.MinValue;
            var t = to ?? DateOnly.MaxValue;
            var fromTs = from is { } fd ? new DateTimeOffset(fd.ToDateTime(TimeOnly.MinValue), TimeSpan.Zero) : DateTimeOffset.MinValue;
            var toTs = to is { } td ? new DateTimeOffset(td.ToDateTime(TimeOnly.MaxValue), TimeSpan.Zero) : DateTimeOffset.MaxValue;
            var orders = await db.PurchaseOrders.AsNoTracking().Where(o => o.SupplierId == supplierId && o.Status != PurchaseOrderStatus.Cancelled && o.IssuedAt >= fromTs && o.IssuedAt <= toTs)
                .Select(o => new { o.Status, Lines = o.Lines.Select(l => new { l.Quantity, l.UnitPrice, l.DiscountPercent, l.IpiPercent }).ToList() }).ToListAsync(ct);
            var lines = await db.GoodsReceiptLines.AsNoTracking().Where(l => l.GoodsReceipt!.SupplierId == supplierId && l.GoodsReceipt.InvoiceDate >= f && l.GoodsReceipt.InvoiceDate <= t)
                .Select(l => new { l.GoodsReceiptId, l.Total, l.GoodsReceipt!.ReceivedAt, l.PurchaseOrderLine!.DueDate }).ToListAsync(ct);
            var today = DateOnly.FromDateTime(DateTime.UtcNow);
            var overdue = await db.PurchaseOrderLines.CountAsync(l => l.PurchaseOrder!.SupplierId == supplierId && !l.Closed && l.ReceivedQuantity < l.Quantity && l.DueDate < today
                && (l.PurchaseOrder.Status == PurchaseOrderStatus.Open || l.PurchaseOrder.Status == PurchaseOrderStatus.PartiallyReceived), ct);
            var delays = lines.Select(l => Math.Max(DateOnly.FromDateTime(l.ReceivedAt.UtcDateTime).DayNumber - l.DueDate.DayNumber, 0)).ToList();
            var onTime = delays.Count(d => d == 0);
            return Results.Ok(new SupplierPerformanceOut(supplierId, supplier.Name, orders.Count,
                orders.Count(o => o.Status is PurchaseOrderStatus.Open or PurchaseOrderStatus.PartiallyReceived),
                orders.Sum(o => o.Lines.Sum(l => PurchasingService.LineTotal(l.Quantity, l.UnitPrice, l.DiscountPercent, l.IpiPercent))),
                lines.Select(l => l.GoodsReceiptId).Distinct().Count(), lines.Sum(l => l.Total), lines.Count, onTime,
                lines.Count == 0 ? 0 : Math.Round(100m * onTime / lines.Count, 1), delays.Count == 0 ? 0 : Math.Round((decimal)delays.Average(), 1), overdue));
        }).WithTags("Suppliers").RequireAuthorization(Policies.Read);
    }

    private static async Task<IResult> PageAsync<TOut, TEntity>(IQueryable<TOut> projected, IQueryable<TEntity> filtered, int? skip, int? take, CancellationToken ct)
    {
        var s = Math.Max(skip ?? 0, 0);
        var t = Math.Clamp(take ?? 50, 1, 500);
        var total = await filtered.CountAsync(ct);
        var items = await projected.Skip(s).Take(t).ToListAsync(ct);
        return Results.Ok(new Page<TOut>(items, total, s, t));
    }
}
