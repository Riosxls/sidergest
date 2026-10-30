using System.Security.Claims;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Sales;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record SalesSettingsDto(decimal MaxDiscountPercent, int DefaultValidityDays, decimal MinimumOrderValue, int? ShippingLocationId, string? DefaultConditions,
    bool OffListNeedsApproval = false, int FollowUpDays = 7, int ApprovalValidityDays = 30);
public record PaymentTermIn(string Code, string Name, string Days, decimal? CreditLimit, bool Active = true);
public record PaymentTermOut(int Id, string Code, string Name, string Days, decimal? CreditLimit, bool Active);
public record PriceListIn(int ProductId, int? CustomerId, decimal UnitPrice, decimal? IpiPercent, decimal? IcmsPercent, DateOnly ValidFrom, DateOnly? ValidTo);
public record PriceListOut(int Id, int ProductId, string ProductCode, string ProductName, int? CustomerId, string? CustomerName, decimal UnitPrice, decimal? IpiPercent, decimal? IcmsPercent, DateOnly ValidFrom, DateOnly? ValidTo);
public record PriceOut(int ProductId, int? CustomerId, decimal? UnitPrice, decimal? IpiPercent, decimal? IcmsPercent, bool CustomerSpecific, string ProductCode, string Description, string Unit, string? CustomerPartNumber);

public record SalesEventOut(long Id, string Action, string? FromStatus, string? ToStatus, string? Note, string? User, DateTimeOffset At);
public record QuoteActionIn(string? Note = null, string? SentTo = null, string? CustomerPo = null, LostReason? LostReason = null, DateOnly? ValidUntil = null, List<QuoteLineDate>? DeliveryDates = null);
public record LostReasonOut(LostReason? Reason, int Quotes, decimal Value);
public record SalesReasonIn(string? Reason);
public record OrderCancelIn(string? Reason, bool CancelProduction = false);
public record SalesOrderIn(int CustomerId, int AddressId, List<SalesLineInput> Lines, string? CustomerPo = null, int? PaymentTermId = null, FreightTerms Freight = FreightTerms.Cif, string? Notes = null, bool OverrideCredit = false, string? Company = null, string? CustomPaymentTerm = null,
    BillTo BillTo = BillTo.Ebt, OrderOrigin Origin = OrderOrigin.System, string? Salesperson = null);
public record SalesReleaseIn(bool UseStock = true);
public record ConfirmDeliveryIn(DateOnly? Date = null, string? ReceivedBy = null);

public record QuoteLineOut(int Id, int Sequence, int ProductId, string ProductCode, string? CustomerPartNumber, string Description, decimal Quantity, string Unit, decimal UnitPrice, decimal? ListPrice, decimal? DiscountPercent,
    decimal IpiPercent, decimal IcmsPercent, int? LeadTimeDays, DateOnly? DeliveryDate, decimal Total);
public record QuoteSummaryOut(int Id, int Number, int Revision, string Reference, int CustomerId, string CustomerName, QuoteStatus Status, bool NeedsApproval, decimal Total, DateOnly? ValidUntil,
    DateTimeOffset? SentAt, DateTimeOffset CreatedAt, string? CreatedBy, int? SalesOrderId, bool FollowUp = false, bool Expiring = false, LostReason? LostReason = null,
    int? SupersededById = null, string? SupersededBy = null);
public record QuoteOut(int Id, int Number, int Revision, string Reference, int CustomerId, string CustomerName, int? AddressId, string? AddressText, string? ContactName, string? ContactEmail, string? CustomerReference,
    int? PaymentTermId, string? PaymentTermName, string? CustomPaymentTerm, FreightTerms Freight, int ValidityDays, DateOnly? ValidUntil, string? Conditions, string? Notes, QuoteStatus Status, bool NeedsApproval, string? ApprovedBy, DateTimeOffset? ApprovedAt,
    DateTimeOffset? SentAt, string? SentTo, DateTimeOffset? DecidedAt, string? DecisionBy, string? DecisionNote, string? CustomerPo, int? SalesOrderId, string? SalesOrderReference, string? CreatedBy, DateTimeOffset CreatedAt,
    QuoteTotals Totals, IReadOnlyList<QuoteLineOut> Lines, IReadOnlyList<SalesEventOut> History, string? RequestText = null, string? RequestFileName = null, string? RequestFileType = null, long? RequestFileSize = null, LostReason? LostReason = null,
    int? SupersededById = null, string? SupersededBy = null);
public record QuoteRequestIn(string? Text);

public record SalesOrderLineOut(int Id, int Sequence, int ProductId, string ProductCode, string? CustomerPartNumber, string Description, decimal Quantity, string Unit, decimal UnitPrice, decimal IpiPercent, decimal IcmsPercent,
    DateOnly DueDate, decimal Total, decimal FromStock, int? ProductionOrderId, string? ProductionReference, ProductionOrderStatus? ProductionStatus, decimal Produced, decimal Shipped, decimal Planned, decimal Remaining, decimal Available, bool Ready,
    LineSpec? Spec = null, int? FeasibilityId = null, string? FeasibilityReference = null, decimal BalanceValue = 0);
public record SalesOrderSummaryOut(int Id, int Number, string Reference, int CustomerId, string CustomerName, string? CustomerPo, SalesOrderStatus Status, decimal Total, DateOnly? NextDue, decimal Progress, bool Ready, bool Late,
    DateTimeOffset CreatedAt, int? QuoteId,
    decimal BalanceValue = 0, decimal? BalanceKg = null, BillTo BillTo = BillTo.Ebt, string? Salesperson = null);
public record DeliverySummaryOut(int Id, int Number, string Reference, int OrderId, string OrderReference, int CustomerId, string CustomerName, DateOnly PlannedDate, DeliveryStatus Status, int Packages, decimal? GrossWeightKg,
    string? InvoiceNumber, string? Carrier, DateTimeOffset? ShippedAt, DateTimeOffset? DeliveredAt);
public record SalesOrderOut(int Id, int Number, string Reference, int CustomerId, string CustomerName, int AddressId, string AddressText, string? CustomerPo, int? PaymentTermId, string? PaymentTermName, string? CustomPaymentTerm, FreightTerms Freight,
    SalesOrderStatus Status, string? StatusReason, string? Notes, int? QuoteId, string? QuoteReference, string? CreatedBy, DateTimeOffset CreatedAt, string? ReleasedBy, DateTimeOffset? ReleasedAt,
    decimal Products, decimal Ipi, decimal Total, decimal Progress, bool Ready, bool Late, CreditCheck Credit, IReadOnlyList<SalesOrderLineOut> Lines, IReadOnlyList<DeliverySummaryOut> Deliveries, IReadOnlyList<SalesEventOut> History, bool CertificateWaived = false,
    BillTo BillTo = BillTo.Ebt, OrderOrigin Origin = OrderOrigin.System, string? Salesperson = null);
public record DeliveryLineOut(int Id, int OrderLineId, int Sequence, int ProductId, string ProductCode, string Description, decimal Quantity, string Unit, int Packages);
public record DeliveryOut(int Id, int Number, string Reference, int OrderId, string OrderReference, int CustomerId, string CustomerName, int AddressId, string AddressText, DateOnly PlannedDate, DeliveryStatus Status,
    string? Carrier, string? VehiclePlate, string? InvoiceNumber, int Packages, decimal? GrossWeightKg, int? StockDocumentId, string? Notes, string? CreatedBy, DateTimeOffset CreatedAt, string? ShippedBy, DateTimeOffset? ShippedAt,
    DateTimeOffset? DeliveredAt, string? ReceivedBy, IReadOnlyList<DeliveryLineOut> Lines, IReadOnlyList<SalesEventOut> History,
    string? LotNumber = null, decimal? InvoicedValue = null, decimal ValueExIpi = 0, decimal BalanceKg = 0, decimal BalanceValue = 0);

public record PipelineCard(SalesRecordKind Kind, int Id, string Reference, int CustomerId, string CustomerName, decimal Value, string Status, DateOnly? Date, decimal? Progress, IReadOnlyList<string> Badges);
public record PipelineStage(string Key, int Count, decimal Value, IReadOnlyList<PipelineCard> Cards);
public record PipelineKpis(decimal OpenQuotesValue, int OpenQuotes, decimal? WinRate, decimal OpenOrdersValue, int OpenOrders, int LateOrders, int ReadyToShip, int PendingApprovals);
public record PipelineOut(PipelineKpis Kpis, IReadOnlyList<PipelineStage> Stages);

public static class SalesPolicies
{
    public const string Customers = "customers";
    public const string Sell = "sales";
    public const string Approve = "sales-approve";
    public const string Release = "sales-release";
    public const string Ship = "sales-ship";
}

public sealed class SalesExceptionHandler : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception exception, CancellationToken ct)
    {
        if (exception is not SalesException e) return false;
        var result = e.Field is not null && e.Status == StatusCodes.Status400BadRequest
            ? Results.ValidationProblem(new Dictionary<string, string[]> { [e.Field] = [e.Message] })
            : Results.Problem(e.Message, statusCode: e.Status);
        await result.ExecuteAsync(http);
        return true;
    }
}

public static class SalesEndpoints
{
    private const int CardsPerStage = 60;
    private const int ExpiringDays = 3;

    public static IServiceCollection AddSales(this IServiceCollection services)
    {
        services.AddScoped<SalesService>();
        services.AddExceptionHandler<SalesExceptionHandler>();
        return services;
    }

    private static bool IsManager(ClaimsPrincipal user) => user.IsInRole(nameof(UserRole.Admin)) || user.IsInRole(nameof(UserRole.SalesManager));

    public static void MapSales(this WebApplication app)
    {
        MapMasters(app);
        MapQuotes(app);
        MapOrders(app);
        MapDeliveries(app);
        MapPipeline(app);
    }

    private static void MapMasters(WebApplication app)
    {
        var settings = app.MapGroup("/api/sales/settings").WithTags("Sales");
        settings.MapGet("/", async (SalesService svc, CancellationToken ct) => ToDto(await svc.SettingsAsync(ct))).RequireAuthorization(Policies.Read);
        settings.MapPut("/", async (SalesSettingsDto i, EbtDbContext db, SalesService svc, CancellationToken ct) =>
        {
            var errors = Errors()
                .Require(i.MaxDiscountPercent is >= 0 and <= 100, "maxDiscountPercent", "Between 0 and 100")
                .Require(i.DefaultValidityDays > 0, "defaultValidityDays", "Must be greater than zero")
                .Require(i.MinimumOrderValue >= 0, "minimumOrderValue", "Cannot be negative")
                .Require(i.FollowUpDays > 0, "followUpDays", "Must be greater than zero")
                .Require(i.ApprovalValidityDays > 0, "approvalValidityDays", "Must be greater than zero");
            if (i.ShippingLocationId is { } l)
                errors.Require(await db.StockLocations.AnyAsync(x => x.Id == l && x.Active && x.Kind != StockLocationKind.ThirdParty, ct), "shippingLocationId", "Unknown, inactive or third-party location");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var s = await svc.SettingsAsync(ct);
            s.MaxDiscountPercent = i.MaxDiscountPercent;
            s.DefaultValidityDays = i.DefaultValidityDays;
            s.MinimumOrderValue = i.MinimumOrderValue;
            s.ShippingLocationId = i.ShippingLocationId;
            s.DefaultConditions = Clean(i.DefaultConditions);
            s.OffListNeedsApproval = i.OffListNeedsApproval;
            s.FollowUpDays = i.FollowUpDays;
            s.ApprovalValidityDays = i.ApprovalValidityDays;
            await db.SaveChangesAsync(ct);
            return Results.Ok(ToDto(s));
        }).RequireAuthorization(Policies.Admin);

        app.MapGroup("/api/sales/payment-terms").WithTags("Sales").MapCrud(new CrudSpec<PaymentTerm, PaymentTermIn, PaymentTermOut>
        {
            Project = p => new PaymentTermOut(p.Id, p.Code, p.Name, p.Days, p.CreditLimit, p.Active),
            Create = i => new PaymentTerm { Code = i.Code.Trim().ToUpper(), Name = i.Name.Trim(), Days = i.Days.Trim(), CreditLimit = i.CreditLimit, Active = i.Active },
            Apply = (i, p) => { p.Code = i.Code.Trim().ToUpper(); p.Name = i.Name.Trim(); p.Days = i.Days.Trim(); p.CreditLimit = i.CreditLimit; p.Active = i.Active; },
            Validate = (i, _, _) => Task.FromResult(Errors().Require(Has(i.Code), "code", "Required").Require(Has(i.Name), "name", "Required")
                .Require(Has(i.Days) && i.Days.Split('/', StringSplitOptions.TrimEntries).All(d => int.TryParse(d, out var n) && n >= 0), "days", "Days separated by '/', e.g. 28/35/42 or 0")
                .Require(i.CreditLimit is null or >= 0, "creditLimit", "Cannot be negative")),
            Search = (q, s) => q.Where(p => EF.Functions.ILike(p.Code, Like(s)) || EF.Functions.ILike(p.Name, Like(s))),
            Order = q => q.OrderBy(p => p.Code),
            BeforeDelete = async (id, db, ct) => await db.Quotes.AnyAsync(q => q.PaymentTermId == id, ct) || await db.SalesOrders.AnyAsync(o => o.PaymentTermId == id, ct) ? "Payment term is in use; deactivate it instead" : null,
            WritePolicy = SalesPolicies.Approve
        });

        app.MapGroup("/api/sales/price-list").WithTags("Sales").MapCrud(new CrudSpec<PriceListEntry, PriceListIn, PriceListOut>
        {
            Project = p => new PriceListOut(p.Id, p.ProductId, p.Product!.Code, p.Product.Name, p.CustomerId, p.Customer != null ? p.Customer.Name : null, p.UnitPrice, p.IpiPercent, p.IcmsPercent, p.ValidFrom, p.ValidTo),
            Create = i => new PriceListEntry { ProductId = i.ProductId, CustomerId = i.CustomerId, UnitPrice = i.UnitPrice, IpiPercent = i.IpiPercent, IcmsPercent = i.IcmsPercent, ValidFrom = i.ValidFrom, ValidTo = i.ValidTo },
            Apply = (i, p) => { p.ProductId = i.ProductId; p.CustomerId = i.CustomerId; p.UnitPrice = i.UnitPrice; p.IpiPercent = i.IpiPercent; p.IcmsPercent = i.IcmsPercent; p.ValidFrom = i.ValidFrom; p.ValidTo = i.ValidTo; },
            Validate = async (i, db, ct) => Errors()
                .Require(await db.Products.AnyAsync(p => p.Id == i.ProductId, ct), "productId", "Not found")
                .Require(i.CustomerId is null || await db.Customers.AnyAsync(c => c.Id == i.CustomerId, ct), "customerId", "Not found")
                .Require(i.UnitPrice >= 0, "unitPrice", "Cannot be negative")
                .Require(i.IpiPercent is null or (>= 0 and <= 100), "ipiPercent", "Between 0 and 100")
                .Require(i.IcmsPercent is null or (>= 0 and <= 100), "icmsPercent", "Between 0 and 100")
                .Require(i.ValidTo is null || i.ValidTo >= i.ValidFrom, "validTo", "Before the start date"),
            Search = (q, s) => q.Where(p => EF.Functions.ILike(p.Product!.Code, Like(s)) || EF.Functions.ILike(p.Product.Name, Like(s)) || EF.Functions.ILike(p.Customer!.Name, Like(s))),
            Order = q => q.OrderBy(p => p.Product!.Code).ThenBy(p => p.CustomerId).ThenByDescending(p => p.ValidFrom),
            WritePolicy = SalesPolicies.Sell
        });

        app.MapGet("/api/sales/price", async (int productId, int? customerId, EbtDbContext db, SalesService svc, CancellationToken ct) =>
        {
            var p = await db.Products.AsNoTracking().FirstOrDefaultAsync(x => x.Id == productId, ct);
            if (p is null) return Results.NotFound();
            var price = await svc.PriceAsync(productId, customerId, SalesService.Today(), ct);
            var cp = customerId is { } cid ? await db.ProductCustomers.AsNoTracking().FirstOrDefaultAsync(x => x.ProductId == productId && x.CustomerId == cid, ct) : null;
            return Results.Ok(new PriceOut(productId, customerId, price?.UnitPrice, price?.IpiPercent, price?.IcmsPercent, price?.CustomerId != null, p.Code, cp?.CustomerDescription ?? p.Name, p.StockUnit, cp?.CustomerPartNumber));
        }).WithTags("Sales").RequireAuthorization(Policies.Read);
    }

    private static void MapQuotes(WebApplication app)
    {
        var g = app.MapGroup("/api/sales/quotes").WithTags("Sales").RequireAuthorization(Policies.Read).AddEndpointFilter(new RowVersionFilter<Quote>());

        g.MapGet("/", async (EbtDbContext db, SalesService svc, ClaimsPrincipal user, QuoteStatus? status, int? customerId, bool? open, bool? mine, bool? followUp, bool? expiring, string? q, int? skip, int? take, CancellationToken ct) =>
        {
            var settings = await svc.SettingsAsync(ct);
            var today = SalesService.Today();
            var followUpBefore = DateTimeOffset.UtcNow.AddDays(-settings.FollowUpDays);
            var x = db.Quotes.AsNoTracking();
            if (status is { } st) x = x.Where(o => o.Status == st);
            if (open == true) x = x.Where(o => SalesService.OpenQuote.Contains(o.Status));
            if (customerId is { } c) x = x.Where(o => o.CustomerId == c);
            if (mine == true && Who(user) is { } me) x = x.Where(o => o.CreatedBy == me);
            if (followUp == true) x = x.Where(o => o.Status == QuoteStatus.Sent && o.SentAt <= followUpBefore);
            if (expiring == true) x = x.Where(o => o.Status == QuoteStatus.Sent && o.ValidUntil <= today.AddDays(ExpiringDays));
            if (Has(q)) x = x.Where(o => EF.Functions.ILike(o.Reference, Like(q!)) || EF.Functions.ILike(o.Customer!.Name, Like(q)) || EF.Functions.ILike(o.CustomerReference!, Like(q)));
            var total = await x.CountAsync(ct);
            var (s, n) = Paging(skip, take);
            var items = await QuoteSummaries(db, x.OrderByDescending(o => o.CreatedAt).Skip(s).Take(n), settings.FollowUpDays, ct);
            return Results.Ok(new Page<QuoteSummaryOut>(items, total, s, n));
        });

        // Why quotes were lost in the last 90 days (customer declines only), for the commercial review.
        g.MapGet("/lost-reasons", async (EbtDbContext db, int? days, CancellationToken ct) =>
        {
            var since = DateTimeOffset.UtcNow.AddDays(-Math.Clamp(days ?? 90, 1, 730));
            var rows = await db.Quotes.AsNoTracking().Where(q => q.DecidedAt >= since && (q.Status == QuoteStatus.Rejected || q.LostReason != null))
                .Select(q => new { q.LostReason, Lines = q.Lines.Select(l => new { l.Quantity, l.UnitPrice, l.IpiPercent }).ToList() }).ToListAsync(ct);
            return Results.Ok(rows.GroupBy(r => r.LostReason).Select(gr => new LostReasonOut(gr.Key, gr.Count(), gr.Sum(r => SalesService.Totals(r.Lines.Select(l => (l.Quantity, l.UnitPrice, l.IpiPercent, (decimal?)null))).Total)))
                .OrderByDescending(r => r.Value).ToList());
        });

        // Soft credit warning while the quote is still open: the hard check stays at conversion to an order.
        g.MapGet("/{id:int}/credit", async (int id, EbtDbContext db, SalesService svc, CancellationToken ct) =>
        {
            var q = await db.Quotes.AsNoTracking().Include(x => x.Lines).FirstOrDefaultAsync(x => x.Id == id, ct);
            return q is null ? Results.NotFound() : Results.Ok(await svc.CreditAsync(q.CustomerId, q.PaymentTermId, SalesService.Totals(q).Total, null, ct));
        });

        g.MapPost("/{id:int}/duplicate", async (int id, DuplicateInput? i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var q = await svc.DuplicateAsync(id, i?.CustomerId, Who(user), ct);
            return Results.Created($"/api/sales/quotes/{q.Id}", await LoadQuote(db, q.Id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapGet("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) => await db.Quotes.AnyAsync(q => q.Id == id, ct) ? Results.Ok(await LoadQuote(db, id, ct)) : Results.NotFound());

        g.MapPost("/", async (QuoteInput i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var q = await svc.CreateQuoteAsync(i, Who(user), ct);
            return Results.Created($"/api/sales/quotes/{q.Id}", await LoadQuote(db, q.Id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapPut("/{id:int}", async (int id, QuoteInput i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.UpdateQuoteAsync(id, i, Who(user), ct);
            return Results.Ok(await LoadQuote(db, id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapDelete("/{id:int}", async (int id, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.DeleteQuoteAsync(id, user.IsInRole(nameof(UserRole.Admin)), ct);
            return Results.NoContent();
        }).RequireAuthorization(SalesPolicies.Sell);

        // Customer's purchase order (text and/or file): attached once the customer approved the quote, up to the conversion to a sales order.
        g.MapPut("/{id:int}/request", async (int id, QuoteRequestIn i, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var q = await db.Quotes.FirstOrDefaultAsync(x => x.Id == id, ct);
            if (q is null) return Results.NotFound();
            if (!PoOpen(q)) return PoClosed(q);
            q.RequestText = Clean(i.Text);
            QuoteEvent(db, q, "po-text", q.RequestText is null ? "Texto do pedido de compra removido" : "Texto do pedido de compra salvo", Who(user));
            await db.SaveChangesAsync(ct);
            return Results.Ok(await LoadQuote(db, id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapPost("/{id:int}/request-file", async (int id, IFormFile file, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var q = await db.Quotes.FirstOrDefaultAsync(x => x.Id == id, ct);
            if (q is null) return Results.NotFound();
            if (!PoOpen(q)) return PoClosed(q);
            if (file.Length is 0 or > MaxRequestFileBytes) return Results.BadRequest(new { message = "Arquivo vazio ou maior que 10 MB", field = "file" });
            var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
            if (!RequestFileTypes.TryGetValue(ext, out var type)) return Results.BadRequest(new { message = "Formato não aceito (PDF, imagem ou texto)", field = "file" });
            await using var ms = new MemoryStream();
            await file.CopyToAsync(ms, ct);
            var stored = await db.QuoteRequestFiles.FirstOrDefaultAsync(x => x.QuoteId == id, ct);
            if (stored is null) db.QuoteRequestFiles.Add(new QuoteRequestFile { QuoteId = id, Data = ms.ToArray() });
            else stored.Data = ms.ToArray();
            q.RequestFileName = Path.GetFileName(file.FileName);
            q.RequestFileType = type;
            q.RequestFileSize = file.Length;
            QuoteEvent(db, q, "po-file", $"Arquivo anexado: {q.RequestFileName}", Who(user));
            await db.SaveChangesAsync(ct);
            return Results.Ok(await LoadQuote(db, id, ct));
        }).RequireAuthorization(SalesPolicies.Sell).DisableAntiforgery();

        g.MapGet("/{id:int}/request-file", async (int id, EbtDbContext db, CancellationToken ct) =>
        {
            var q = await db.Quotes.AsNoTracking().Where(x => x.Id == id).Select(x => new { x.RequestFileName, x.RequestFileType }).FirstOrDefaultAsync(ct);
            var data = q?.RequestFileName is null ? null : await db.QuoteRequestFiles.AsNoTracking().Where(x => x.QuoteId == id).Select(x => x.Data).FirstOrDefaultAsync(ct);
            return data is null ? Results.NotFound() : Results.File(data, q!.RequestFileType ?? "application/octet-stream", q.RequestFileName);
        });

        g.MapDelete("/{id:int}/request-file", async (int id, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var q = await db.Quotes.FirstOrDefaultAsync(x => x.Id == id, ct);
            if (q is null) return Results.NotFound();
            if (!PoOpen(q)) return PoClosed(q);
            if (q.Status == QuoteStatus.PurchaseOrder && Clean(q.RequestText) is null) return Results.Conflict(new { message = "O pedido de compra precisa de arquivo ou texto" });
            QuoteEvent(db, q, "po-file-removed", $"Arquivo removido: {q.RequestFileName}", Who(user));
            await db.QuoteRequestFiles.Where(x => x.QuoteId == id).ExecuteDeleteAsync(ct);
            q.RequestFileName = null;
            q.RequestFileType = null;
            q.RequestFileSize = null;
            await db.SaveChangesAsync(ct);
            return Results.Ok(await LoadQuote(db, id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        QuoteAction(g, "send", SalesPolicies.Sell, (svc, id, i, u, ct) => svc.SendAsync(id, i.SentTo, i.Note, u, ct));
        QuoteAction(g, "approve", SalesPolicies.Approve, (svc, id, i, u, ct) => svc.ApproveAsync(id, i.Note, u, ct));
        QuoteAction(g, "reject-approval", SalesPolicies.Approve, (svc, id, i, u, ct) => svc.RejectApprovalAsync(id, i.Note, u, ct));
        QuoteAction(g, "purchase-order", SalesPolicies.Sell, (svc, id, i, u, ct) => svc.ReceivePurchaseOrderAsync(id, i.CustomerPo, i.Note, u, ct, i.DeliveryDates));
        QuoteAction(g, "accept", SalesPolicies.Sell, (svc, id, i, u, ct) => svc.AcceptAsync(id, i.CustomerPo, i.Note, u, ct));
        QuoteAction(g, "decline", SalesPolicies.Sell, (svc, id, i, u, ct) => svc.DeclineAsync(id, i.Note, i.LostReason, u, ct));
        // Cancels the quote (note = reason) and returns the NEW revision draft, linked by the shared quote number (PROP 4685-A → -B).
        g.MapPost("/{id:int}/revise", async (int id, QuoteActionIn i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var q = await svc.ReviseAsync(id, i.Note, i.CustomerPo, Who(user), ct);
            return Results.Created($"/api/sales/quotes/{q.Id}", await LoadQuote(db, q.Id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);
        QuoteAction(g, "cancel", SalesPolicies.Sell, (svc, id, i, u, ct) => svc.CancelQuoteAsync(id, i.Note, u, ct));
        QuoteAction(g, "reopen", SalesPolicies.Sell, (svc, id, i, u, ct) => svc.ReopenAsync(id, i.Note, u, ct));
        QuoteAction(g, "extend", SalesPolicies.Sell, (svc, id, i, u, ct) => svc.ExtendValidityAsync(id, i.ValidUntil, i.Note, u, ct));

        g.MapPost("/{id:int}/convert", async (int id, ConvertInput i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var o = await svc.ConvertAsync(id, i, IsManager(user), Who(user), ct);
            return Results.Created($"/api/sales/orders/{o.Id}", await LoadOrder(db, svc, o.Id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);
    }

    private static void QuoteEvent(EbtDbContext db, Quote q, string action, string note, string? user) =>
        db.SalesEvents.Add(new SalesEvent { Kind = SalesRecordKind.Quote, RecordId = q.Id, Action = action, FromStatus = q.Status.ToString(), ToStatus = q.Status.ToString(), Note = note, User = user, At = DateTimeOffset.UtcNow });

    private static bool PoOpen(Quote q) => q.Status is QuoteStatus.Accepted or QuoteStatus.PurchaseOrder;

    private static IResult PoClosed(Quote q) => Results.Conflict(new { message = $"Pedido de compra só pode ser anexado após a aprovação do cliente (status atual: {q.Status})" });

    private const long MaxRequestFileBytes = 10 * 1024 * 1024;

    private static readonly Dictionary<string, string> RequestFileTypes = new()
    {
        [".pdf"] = "application/pdf", [".png"] = "image/png", [".jpg"] = "image/jpeg", [".jpeg"] = "image/jpeg", [".webp"] = "image/webp", [".txt"] = "text/plain",
    };

    private static void QuoteAction(RouteGroupBuilder g, string action, string policy, Func<SalesService, int, QuoteActionIn, string?, CancellationToken, Task<Quote>> run) =>
        g.MapPost($"/{{id:int}}/{action}", async (int id, QuoteActionIn i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await run(svc, id, i, Who(user), ct);
            return Results.Ok(await LoadQuote(db, id, ct));
        }).RequireAuthorization(policy);

    private static void MapOrders(WebApplication app)
    {
        var g = app.MapGroup("/api/sales/orders").WithTags("Sales").RequireAuthorization(Policies.Read).AddEndpointFilter(new RowVersionFilter<SalesOrder>());

        g.MapGet("/", async (EbtDbContext db, SalesService svc, SalesOrderStatus? status, int? customerId, bool? open, string? month, bool? late, BillTo? billTo, string? q, int? skip, int? take, CancellationToken ct) =>
        {
            var x = db.SalesOrders.AsNoTracking();
            if (billTo is { } bt) x = x.Where(o => o.BillTo == bt);
            if (Has(month) && DateOnly.TryParseExact(month!.Trim() + "-01", "yyyy-MM-dd", out var m0))
            {
                var m1 = m0.AddMonths(1);
                x = x.Where(o => o.Lines.Any(l => l.DueDate >= m0 && l.DueDate < m1));
            }
            if (late == true) x = x.Where(o => SalesService.OpenOrder.Contains(o.Status) && o.Lines.Any(l => l.DueDate < DateOnly.FromDateTime(DateTime.UtcNow)));
            if (status is { } st) x = x.Where(o => o.Status == st);
            if (open == true) x = x.Where(o => SalesService.OpenOrder.Contains(o.Status));
            if (customerId is { } c) x = x.Where(o => o.CustomerId == c);
            if (Has(q)) x = x.Where(o => EF.Functions.ILike(o.Reference, Like(q!)) || EF.Functions.ILike(o.Customer!.Name, Like(q)) || EF.Functions.ILike(o.CustomerPo!, Like(q)));
            var total = await x.CountAsync(ct);
            var (s, n) = Paging(skip, take);
            var items = await OrderSummaries(db, svc, x.OrderByDescending(o => o.CreatedAt).Skip(s).Take(n), ct);
            return Results.Ok(new Page<SalesOrderSummaryOut>(items, total, s, n));
        });

        g.MapGet("/{id:int}", async (int id, EbtDbContext db, SalesService svc, CancellationToken ct) =>
            await db.SalesOrders.AnyAsync(o => o.Id == id, ct) ? Results.Ok(await LoadOrder(db, svc, id, ct)) : Results.NotFound());

        g.MapPost("/", async (SalesOrderIn i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var o = await svc.CreateOrderAsync(new SalesOrderInput(i.CustomerId, i.AddressId, i.Lines, i.CustomerPo, i.PaymentTermId, i.Freight, i.Notes, i.Company, i.CustomPaymentTerm, i.BillTo, i.Origin, i.Salesperson), i.OverrideCredit && IsManager(user), Who(user), ct);
            return Results.Created($"/api/sales/orders/{o.Id}", await LoadOrder(db, svc, o.Id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapPut("/{id:int}", async (int id, SalesOrderIn i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.UpdateOrderAsync(id, new SalesOrderInput(i.CustomerId, i.AddressId, i.Lines, i.CustomerPo, i.PaymentTermId, i.Freight, i.Notes, i.Company, i.CustomPaymentTerm, i.BillTo, i.Origin, i.Salesperson), Who(user), ct);
            return Results.Ok(await LoadOrder(db, svc, id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapPost("/{id:int}/release", async (int id, SalesReleaseIn i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.ReleaseAsync(id, i.UseStock, Who(user), ct);
            return Results.Ok(await LoadOrder(db, svc, id, ct));
        }).RequireAuthorization(SalesPolicies.Release);

        g.MapGet("/{id:int}/cancel-preview", async (int id, SalesService svc, CancellationToken ct) => Results.Ok(await svc.CancelPreviewAsync(id, ct)));

        g.MapPost("/{id:int}/cancel", async (int id, OrderCancelIn i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.CancelOrderAsync(id, i.Reason, Who(user), ct, i.CancelProduction);
            return Results.Ok(await LoadOrder(db, svc, id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapPost("/{id:int}/close-balance", async (int id, SalesReasonIn i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.CloseBalanceAsync(id, i.Reason, Who(user), ct);
            return Results.Ok(await LoadOrder(db, svc, id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapPost("/{id:int}/reschedule", async (int id, RescheduleInput i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.RescheduleAsync(id, i, Who(user), ct);
            return Results.Ok(await LoadOrder(db, svc, id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapPost("/{id:int}/deliveries", async (int id, DeliveryInput i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var d = await svc.CreateDeliveryAsync(id, i, Who(user), ct);
            return Results.Created($"/api/sales/deliveries/{d.Id}", await LoadDelivery(db, d.Id, ct));
        }).RequireAuthorization(SalesPolicies.Ship);
    }

    private static void MapDeliveries(WebApplication app)
    {
        var g = app.MapGroup("/api/sales/deliveries").WithTags("Sales").RequireAuthorization(Policies.Read).AddEndpointFilter(new RowVersionFilter<Delivery>());

        g.MapGet("/", async (EbtDbContext db, DeliveryStatus? status, int? orderId, int? customerId, DateOnly? from, DateOnly? to, string? q, int? skip, int? take, CancellationToken ct) =>
        {
            var x = db.Deliveries.AsNoTracking();
            if (status is { } st) x = x.Where(d => d.Status == st);
            if (orderId is { } o) x = x.Where(d => d.OrderId == o);
            if (customerId is { } c) x = x.Where(d => d.Order!.CustomerId == c);
            if (from is { } f) x = x.Where(d => d.PlannedDate >= f);
            if (to is { } t) x = x.Where(d => d.PlannedDate <= t);
            if (Has(q)) x = x.Where(d => EF.Functions.ILike(d.Reference, Like(q!)) || EF.Functions.ILike(d.Order!.Reference, Like(q)) || EF.Functions.ILike(d.Order.Customer!.Name, Like(q)) || EF.Functions.ILike(d.InvoiceNumber!, Like(q)));
            var total = await x.CountAsync(ct);
            var (s, n) = Paging(skip, take);
            var items = await x.OrderBy(d => d.Status).ThenBy(d => d.PlannedDate).ThenBy(d => d.Number).Skip(s).Take(n).Select(DeliverySummary).ToListAsync(ct);
            return Results.Ok(new Page<DeliverySummaryOut>(items, total, s, n));
        });

        g.MapGet("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) => await db.Deliveries.AnyAsync(d => d.Id == id, ct) ? Results.Ok(await LoadDelivery(db, id, ct)) : Results.NotFound());

        g.MapPost("/{id:int}/ship", async (int id, ShipInput i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.ShipAsync(id, i, Who(user), ct);
            return Results.Ok(await LoadDelivery(db, id, ct));
        }).RequireAuthorization(SalesPolicies.Ship);

        g.MapPost("/{id:int}/confirm", async (int id, ConfirmDeliveryIn i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.ConfirmAsync(id, i.Date, i.ReceivedBy, Who(user), ct);
            return Results.Ok(await LoadDelivery(db, id, ct));
        }).RequireAuthorization(SalesPolicies.Ship);

        g.MapPost("/{id:int}/cancel", async (int id, SalesReasonIn i, EbtDbContext db, SalesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.CancelDeliveryAsync(id, i.Reason, Who(user), ct);
            return Results.Ok(await LoadDelivery(db, id, ct));
        }).RequireAuthorization(SalesPolicies.Ship);
    }

    private static void MapPipeline(WebApplication app)
    {
        app.MapGet("/api/sales/pipeline", async (EbtDbContext db, SalesService svc, int? customerId, CancellationToken ct) =>
        {
            var today = SalesService.Today();
            var quotes = db.Quotes.AsNoTracking().Where(q => SalesService.OpenQuote.Contains(q.Status));
            var orders = db.SalesOrders.AsNoTracking().Where(o => SalesService.OpenOrder.Contains(o.Status) || o.Status == SalesOrderStatus.Shipped
                || o.Status == SalesOrderStatus.Delivered && o.CreatedAt >= DateTimeOffset.UtcNow.AddDays(-30));
            if (customerId is { } c)
            {
                quotes = quotes.Where(q => q.CustomerId == c);
                orders = orders.Where(o => o.CustomerId == c);
            }
            var quoteRows = await QuoteSummaries(db, quotes.OrderBy(q => q.ValidUntil ?? DateOnly.MaxValue).ThenByDescending(q => q.CreatedAt), (await svc.SettingsAsync(ct)).FollowUpDays, ct);
            var orderRows = await OrderSummaries(db, svc, orders.OrderBy(o => o.CreatedAt), ct);

            PipelineCard QuoteCard(QuoteSummaryOut q)
            {
                var badges = new List<string>();
                if (q.NeedsApproval) badges.Add("discount");
                if (q.Expiring) badges.Add("expiring");
                if (q.FollowUp) badges.Add("followup");
                return new PipelineCard(SalesRecordKind.Quote, q.Id, q.Reference, q.CustomerId, q.CustomerName, q.Total, q.Status.ToString(), q.ValidUntil ?? DateOnly.FromDateTime(q.CreatedAt.UtcDateTime), null, badges);
            }
            PipelineCard OrderCard(SalesOrderSummaryOut o)
            {
                var badges = new List<string>();
                if (o.Late) badges.Add("late");
                if (o.Ready && o.Status is SalesOrderStatus.Released or SalesOrderStatus.PartiallyShipped) badges.Add("ready");
                if (o.Status == SalesOrderStatus.PartiallyShipped) badges.Add("partial");
                return new PipelineCard(SalesRecordKind.Order, o.Id, o.Reference, o.CustomerId, o.CustomerName, o.Total, o.Status.ToString(), o.NextDue, o.Progress, badges);
            }
            PipelineStage Stage(string key, IEnumerable<PipelineCard> cards)
            {
                var list = cards.ToList();
                return new PipelineStage(key, list.Count, list.Sum(x => x.Value), list.Take(CardsPerStage).ToList());
            }

            var inProgress = orderRows.Where(o => o.Status is SalesOrderStatus.Released or SalesOrderStatus.PartiallyShipped).ToList();
            // Finished production waits in "certificate" until a quality certificate exists for the order (or the customer does not need one).
            var readyIds = inProgress.Where(o => o.Ready).Select(o => o.Id).ToList();
            var certified = await db.QualityCertificates.Where(c => readyIds.Contains(c.OrderId) && c.Status == CertificateStatus.Issued).Select(c => c.OrderId).Distinct().ToListAsync(ct);
            var waived = await db.SalesOrders.Where(o => readyIds.Contains(o.Id) && o.CertificateWaived).Select(o => o.Id).ToListAsync(ct);
            var needsCertificate = readyIds.Except(certified).Except(waived).ToHashSet();
            var stages = new List<PipelineStage>
            {
                Stage("quote", quoteRows.Where(q => q.Status is QuoteStatus.Draft or QuoteStatus.PendingApproval or QuoteStatus.Approved).Select(QuoteCard)),
                Stage("sent", quoteRows.Where(q => q.Status == QuoteStatus.Sent).Select(QuoteCard)),
                Stage("accepted", quoteRows.Where(q => q.Status == QuoteStatus.Accepted).Select(QuoteCard)),
                Stage("po", quoteRows.Where(q => q.Status == QuoteStatus.PurchaseOrder).Select(QuoteCard)),
                Stage("order", orderRows.Where(o => o.Status == SalesOrderStatus.Created).Select(OrderCard)),
                Stage("production", inProgress.Where(o => !o.Ready).Select(OrderCard)),
                Stage("certificate", inProgress.Where(o => needsCertificate.Contains(o.Id)).Select(OrderCard)),
                Stage("ready", inProgress.Where(o => o.Ready && !needsCertificate.Contains(o.Id)).Select(OrderCard)),
                Stage("shipped", orderRows.Where(o => o.Status == SalesOrderStatus.Shipped).Select(OrderCard)),
                Stage("delivered", orderRows.Where(o => o.Status == SalesOrderStatus.Delivered).Select(OrderCard).Reverse()),
            };

            var since = DateTimeOffset.UtcNow.AddDays(-90);
            var decided = await db.Quotes.AsNoTracking().Where(q => q.DecidedAt >= since || q.Status == QuoteStatus.Converted && q.CreatedAt >= since)
                .Where(q => customerId == null || q.CustomerId == customerId)
                .GroupBy(q => q.Status == QuoteStatus.Accepted || q.Status == QuoteStatus.PurchaseOrder || q.Status == QuoteStatus.Converted).Select(x => new { Won = x.Key, N = x.Count() }).ToListAsync(ct);
            var won = decided.Where(d => d.Won).Sum(d => d.N);
            var all = decided.Sum(d => d.N);
            var openOrders = orderRows.Where(o => SalesService.OpenOrder.Contains(o.Status)).ToList();
            var kpis = new PipelineKpis(quoteRows.Where(q => q.Status is not (QuoteStatus.Accepted or QuoteStatus.PurchaseOrder)).Sum(q => q.Total), quoteRows.Count(q => q.Status is not (QuoteStatus.Accepted or QuoteStatus.PurchaseOrder)),
                all == 0 ? null : Math.Round((decimal)won / all, 4), openOrders.Sum(o => o.Total), openOrders.Count, openOrders.Count(o => o.Late), inProgress.Count(o => o.Ready),
                quoteRows.Count(q => q.Status == QuoteStatus.PendingApproval));
            return Results.Ok(new PipelineOut(kpis, stages));
        }).WithTags("Sales").RequireAuthorization(Policies.Read);
    }

    /// <summary>The newest revision with the same number, when this one has been replaced by it.</summary>
    private static async Task<Dictionary<int, (int Id, string Reference)>> LatestRevisions(EbtDbContext db, IEnumerable<(int Number, int Revision)> cancelled, CancellationToken ct)
    {
        var numbers = cancelled.Select(c => c.Number).Distinct().ToList();
        if (numbers.Count == 0) return [];
        var all = await db.Quotes.AsNoTracking().Where(x => numbers.Contains(x.Number)).Select(x => new { x.Number, x.Revision, x.Id, x.Reference }).ToListAsync();
        return cancelled.Select(c => (c, newest: all.Where(x => x.Number == c.Number && x.Revision > c.Revision).OrderByDescending(x => x.Revision).FirstOrDefault()))
            .Where(p => p.newest is not null).ToDictionary(p => p.c.Number * 100 + p.c.Revision, p => (p.newest!.Id, p.newest.Reference));
    }

    private static async Task<List<QuoteSummaryOut>> QuoteSummaries(EbtDbContext db, IQueryable<Quote> q, int followUpDays, CancellationToken ct)
    {
        var rows = await q.Select(x => new
        {
            x.Id, x.Number, x.Revision, x.Reference, x.CustomerId, Customer = x.Customer!.Name, x.Status, x.NeedsApproval, x.ValidUntil, x.SentAt, x.CreatedAt, x.CreatedBy, x.SalesOrderId, x.LostReason,
            Lines = x.Lines.Select(l => new { l.Quantity, l.UnitPrice, l.IpiPercent, l.ListPrice }).ToList()
        }).ToListAsync(ct);
        var today = SalesService.Today();
        var followUpBefore = DateTimeOffset.UtcNow.AddDays(-followUpDays);
        var replaced = await LatestRevisions(db, rows.Where(r => r.Status == QuoteStatus.Cancelled).Select(r => (r.Number, r.Revision)), ct);
        return rows.Select(x => new QuoteSummaryOut(x.Id, x.Number, x.Revision, x.Reference, x.CustomerId, x.Customer, x.Status, x.NeedsApproval,
            SalesService.Totals(x.Lines.Select(l => (l.Quantity, l.UnitPrice, l.IpiPercent, l.ListPrice))).Total, x.ValidUntil, x.SentAt, x.CreatedAt, x.CreatedBy, x.SalesOrderId,
            FollowUp: x.Status == QuoteStatus.Sent && x.SentAt <= followUpBefore, Expiring: x.Status == QuoteStatus.Sent && x.ValidUntil is { } v && v <= today.AddDays(ExpiringDays), LostReason: x.LostReason,
            SupersededById: replaced.TryGetValue(x.Number * 100 + x.Revision, out var r) ? r.Id : null, SupersededBy: replaced.TryGetValue(x.Number * 100 + x.Revision, out var r2) ? r2.Reference : null)).ToList();
    }

    private static async Task<List<SalesOrderSummaryOut>> OrderSummaries(EbtDbContext db, SalesService svc, IQueryable<SalesOrder> q, CancellationToken ct)
    {
        var rows = await q.Select(x => new
        {
            x.Id, x.Number, x.Reference, x.CustomerId, Customer = x.Customer!.Name, x.CustomerPo, x.Status, x.CreatedAt, x.QuoteId, x.BillTo, x.Salesperson,
            Lines = x.Lines.Select(l => new { l.Id, l.Quantity, l.UnitPrice, l.IpiPercent, l.DueDate, l.SaleUnit, l.PieceWeightKg }).ToList()
        }).ToListAsync(ct);
        var progress = await svc.ProgressAsync(rows.Select(r => r.Id).ToList(), ct);
        return rows.Select(x =>
        {
            var p = progress.GetValueOrDefault(x.Id);
            var open = x.Lines.Select(l => (Line: l, Left: p?.Lines.FirstOrDefault(pl => pl.LineId == l.Id)?.Remaining ?? l.Quantity)).ToList();
            var kgs = open.Select(o => o.Line.SaleUnit == "KG" ? (decimal?)o.Left : o.Line.SaleUnit == "PC" && o.Line.PieceWeightKg is { } w ? o.Left * w : null).ToList();
            return new SalesOrderSummaryOut(x.Id, x.Number, x.Reference, x.CustomerId, x.Customer, x.CustomerPo, x.Status,
                SalesService.Totals(x.Lines.Select(l => (l.Quantity, l.UnitPrice, l.IpiPercent, (decimal?)null))).Total, x.Lines.Count == 0 ? null : x.Lines.Min(l => l.DueDate),
                p?.Progress ?? 0, p?.Ready ?? false, p?.Late ?? false, x.CreatedAt, x.QuoteId,
                Math.Round(open.Sum(o => o.Left * o.Line.UnitPrice), 2), kgs.Any(k => k is null) ? null : Math.Round(kgs.Sum(k => k!.Value), 3), x.BillTo, x.Salesperson);
        }).ToList();
    }

    private static async Task<List<SalesEventOut>> History(EbtDbContext db, SalesRecordKind kind, int id, CancellationToken ct) =>
        await db.SalesEvents.AsNoTracking().Where(e => e.Kind == kind && e.RecordId == id).OrderByDescending(e => e.At).ThenByDescending(e => e.Id)
            .Select(e => new SalesEventOut(e.Id, e.Action, e.FromStatus, e.ToStatus, e.Note, e.User, e.At)).ToListAsync(ct);

    private static string AddressText(CustomerAddress? a) => a is null ? "" :
        string.Join(", ", new[] { string.Join(" ", new[] { a.Street, a.Number }.Where(Has)), a.Complement, a.District, $"{a.City} - {a.Uf}".Trim(' ', '-'), a.ZipCode }.Where(Has));

    private static async Task<QuoteOut> LoadQuote(EbtDbContext db, int id, CancellationToken ct)
    {
        var q = await db.Quotes.AsNoTracking().Include(x => x.Customer).Include(x => x.Address).Include(x => x.PaymentTerm).Include(x => x.Lines).ThenInclude(l => l.Product).FirstAsync(x => x.Id == id, ct);
        var order = q.SalesOrderId is { } oid ? await db.SalesOrders.Where(o => o.Id == oid).Select(o => o.Reference).FirstOrDefaultAsync(ct) : null;
        var replaced = q.Status == QuoteStatus.Cancelled ? await LatestRevisions(db, [(q.Number, q.Revision)], ct) : [];
        var newer = replaced.TryGetValue(q.Number * 100 + q.Revision, out var n) ? n : default((int Id, string Reference)?);
        var lines = q.Lines.OrderBy(l => l.Sequence).Select(l => new QuoteLineOut(l.Id, l.Sequence, l.ProductId, l.Product!.Code, l.CustomerPartNumber, l.Description, l.Quantity, l.Unit, l.UnitPrice, l.ListPrice,
            l.ListPrice is > 0 ? Math.Round((1 - l.UnitPrice / l.ListPrice.Value) * 100m, 2) : null, l.IpiPercent, l.IcmsPercent, l.LeadTimeDays, l.DeliveryDate, Math.Round(l.Quantity * l.UnitPrice, 2))).ToList();
        return new QuoteOut(q.Id, q.Number, q.Revision, q.Reference, q.CustomerId, q.Customer!.Name, q.AddressId, q.Address is null ? null : AddressText(q.Address), q.ContactName, q.ContactEmail, q.CustomerReference,
            q.PaymentTermId, q.PaymentTerm?.Name, q.CustomPaymentTerm, q.Freight, q.ValidityDays, q.ValidUntil, q.Conditions, q.Notes, q.Status, q.NeedsApproval, q.ApprovedBy, q.ApprovedAt, q.SentAt, q.SentTo, q.DecidedAt, q.DecisionBy, q.DecisionNote,
            q.CustomerPo, q.SalesOrderId, order, q.CreatedBy, q.CreatedAt, SalesService.Totals(q), lines, await History(db, SalesRecordKind.Quote, id, ct), q.RequestText, q.RequestFileName, q.RequestFileType, q.RequestFileSize, q.LostReason,
            newer?.Id, newer?.Reference);
    }

    private static async Task<SalesOrderOut> LoadOrder(EbtDbContext db, SalesService svc, int id, CancellationToken ct)
    {
        var o = await db.SalesOrders.AsNoTracking().Include(x => x.Customer).Include(x => x.Address).Include(x => x.PaymentTerm).Include(x => x.Quote).Include(x => x.Lines).ThenInclude(l => l.Product).Include(x => x.Lines).ThenInclude(l => l.FeasibilityStudy).FirstAsync(x => x.Id == id, ct);
        var progress = (await svc.ProgressAsync([id], ct)).GetValueOrDefault(id);
        var lines = o.Lines.OrderBy(l => l.Sequence).Select(l =>
        {
            var p = progress?.Lines.First(x => x.LineId == l.Id);
            return new SalesOrderLineOut(l.Id, l.Sequence, l.ProductId, l.Product!.Code, l.CustomerPartNumber, l.Description, l.Quantity, l.Unit, l.UnitPrice, l.IpiPercent, l.IcmsPercent, l.DueDate,
                Math.Round(l.Quantity * l.UnitPrice, 2), l.FromStock, l.ProductionOrderId, p?.ProductionReference, p?.ProductionStatus, p?.Produced ?? 0, p?.Shipped ?? 0, p?.Planned ?? 0, p?.Remaining ?? l.Quantity, p?.Available ?? 0, p?.Ready ?? false,
                l.ToSpec(), l.FeasibilityStudyId, l.FeasibilityStudy?.Reference, Math.Round((p?.Remaining ?? l.Quantity) * l.UnitPrice, 2));
        }).ToList();
        var totals = SalesService.Totals(o.Lines.Select(l => (l.Quantity, l.UnitPrice, l.IpiPercent, (decimal?)null)));
        var credit = await svc.CreditAsync(o.CustomerId, o.PaymentTermId, 0m, null, ct);
        var deliveries = await db.Deliveries.AsNoTracking().Where(d => d.OrderId == id).OrderBy(d => d.Number).Select(DeliverySummary).ToListAsync(ct);
        return new SalesOrderOut(o.Id, o.Number, o.Reference, o.CustomerId, o.Customer!.Name, o.AddressId, AddressText(o.Address), o.CustomerPo, o.PaymentTermId, o.PaymentTerm?.Name, o.CustomPaymentTerm, o.Freight, o.Status, o.StatusReason, o.Notes,
            o.QuoteId, o.Quote?.Reference, o.CreatedBy, o.CreatedAt, o.ReleasedBy, o.ReleasedAt, totals.Products, totals.Ipi, totals.Total, progress?.Progress ?? 0, progress?.Ready ?? false, progress?.Late ?? false,
            credit, lines, deliveries, await History(db, SalesRecordKind.Order, id, ct), o.CertificateWaived, o.BillTo, o.Origin, o.Salesperson);
    }

    private static async Task<DeliveryOut> LoadDelivery(EbtDbContext db, int id, CancellationToken ct)
    {
        var d = await db.Deliveries.AsNoTracking().Include(x => x.Address).Include(x => x.Order).ThenInclude(o => o!.Customer).Include(x => x.Lines).ThenInclude(l => l.OrderLine).ThenInclude(l => l!.Product)
            .FirstAsync(x => x.Id == id, ct);
        var orderLines = await db.SalesOrderLines.AsNoTracking().Include(l => l.Product).Where(l => l.OrderId == d.OrderId).ToListAsync(ct);
        var upTo = await db.DeliveryLines.AsNoTracking().Where(l => l.Delivery!.OrderId == d.OrderId && l.Delivery.Status != DeliveryStatus.Cancelled && l.Delivery.Number <= d.Number)
            .GroupBy(l => l.OrderLineId).Select(g => new { LineId = g.Key, Quantity = g.Sum(x => x.Quantity) }).ToDictionaryAsync(x => x.LineId, x => x.Quantity, ct);
        static decimal KgPerUnit(SalesOrderLine l) => l.SaleUnit == "KG" || (l.SaleUnit is null && l.Unit.Equals("KG", StringComparison.OrdinalIgnoreCase)) ? 1m : l.PieceWeightKg ?? l.Product?.NetWeightKg ?? 0m;
        var valueExIpi = Math.Round(d.Lines.Sum(l => l.Quantity * l.OrderLine!.UnitPrice), 2);
        var balanceKg = Math.Round(orderLines.Sum(l => Math.Max(0, l.Quantity - upTo.GetValueOrDefault(l.Id)) * KgPerUnit(l)), 3);
        var balanceValue = Math.Round(orderLines.Sum(l => Math.Max(0, l.Quantity - upTo.GetValueOrDefault(l.Id)) * l.UnitPrice), 2);
        var lines = d.Lines.OrderBy(l => l.OrderLine!.Sequence).Select(l => new DeliveryLineOut(l.Id, l.OrderLineId, l.OrderLine!.Sequence, l.OrderLine.ProductId, l.OrderLine.Product!.Code, l.OrderLine.Description,
            l.Quantity, l.OrderLine.Unit, l.Packages)).ToList();
        return new DeliveryOut(d.Id, d.Number, d.Reference, d.OrderId, d.Order!.Reference, d.Order.CustomerId, d.Order.Customer!.Name, d.AddressId, AddressText(d.Address), d.PlannedDate, d.Status, d.Carrier, d.VehiclePlate,
            d.InvoiceNumber, d.Packages, d.GrossWeightKg, d.StockDocumentId, d.Notes, d.CreatedBy, d.CreatedAt, d.ShippedBy, d.ShippedAt, d.DeliveredAt, d.ReceivedBy, lines, await History(db, SalesRecordKind.Delivery, id, ct),
            d.LotNumber, d.InvoicedValue, valueExIpi, balanceKg, balanceValue);
    }

    private static readonly System.Linq.Expressions.Expression<Func<Delivery, DeliverySummaryOut>> DeliverySummary = d =>
        new DeliverySummaryOut(d.Id, d.Number, d.Reference, d.OrderId, d.Order!.Reference, d.Order.CustomerId, d.Order.Customer!.Name, d.PlannedDate, d.Status, d.Packages, d.GrossWeightKg, d.InvoiceNumber, d.Carrier, d.ShippedAt, d.DeliveredAt);

    private static SalesSettingsDto ToDto(SalesSettings s) => new(s.MaxDiscountPercent, s.DefaultValidityDays, s.MinimumOrderValue, s.ShippingLocationId, s.DefaultConditions, s.OffListNeedsApproval, s.FollowUpDays, s.ApprovalValidityDays);
}
