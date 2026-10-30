using static Ebt.Core.Services.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Viability;
using Ebt.Core.Inventory;
using Ebt.Core.Production;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Sales;

public sealed partial class SalesService(EbtDbContext db, StockService stock, ProductionService production, FiscalService fiscal)
{
    public static readonly QuoteStatus[] OpenQuote = [QuoteStatus.Draft, QuoteStatus.PendingApproval, QuoteStatus.Approved, QuoteStatus.Sent, QuoteStatus.PurchaseOrder, QuoteStatus.Accepted];
    public static readonly SalesOrderStatus[] OpenOrder = [SalesOrderStatus.Created, SalesOrderStatus.Released, SalesOrderStatus.PartiallyShipped];
    private static readonly QuoteStatus[] Revisable = [QuoteStatus.PendingApproval, QuoteStatus.Approved, QuoteStatus.Sent, QuoteStatus.Accepted, QuoteStatus.PurchaseOrder, QuoteStatus.Rejected, QuoteStatus.Expired];
    private static readonly ProductionOrderStatus[] ProductionDone = [ProductionOrderStatus.Finished, ProductionOrderStatus.Closed];

    /// <summary>"PROP 4685" until revised; once revised every version carries a letter: -A (original), -B, -C...</summary>
    public static string QuoteReference(int number, int revision, bool revised = false) => revision == 0 && !revised ? $"PROP {number}" : $"PROP {number}-{(char)('A' + revision)}";
    public static string OrderReference(int number) => $"PV {number}";
    public static string DeliveryReference(int number) => $"ENT {number}";

    public async Task<SalesSettings> SettingsAsync(CancellationToken ct = default) =>
        await db.SalesSettings.FirstOrDefaultAsync(ct) ?? throw new InvalidOperationException("sales_settings row missing");

    public async Task<PriceListEntry?> PriceAsync(int productId, int? customerId, DateOnly date, CancellationToken ct = default) =>
        await db.PriceList.AsNoTracking()
            .Where(p => p.ProductId == productId && (p.CustomerId == customerId || p.CustomerId == null) && p.ValidFrom <= date && (p.ValidTo == null || p.ValidTo >= date))
            .OrderBy(p => p.CustomerId == null).ThenByDescending(p => p.ValidFrom)
            .FirstOrDefaultAsync(ct);

    public static string CompanyOf(string? company) => Clean(company)?.ToUpperInvariant() switch
    {
        null or "EBT" => "EBT",
        "BST" => "BST",
        _ => throw SalesException.Invalid("company", "EBT or BST")
    };

    public static QuoteTotals Totals(IEnumerable<(decimal Qty, decimal Price, decimal Ipi, decimal? List)> lines) =>
        Totals(lines.Select(l => (l.Qty, l.Price, l.Ipi, l.List, 0m)));

    public static QuoteTotals Totals(IEnumerable<(decimal Qty, decimal Price, decimal Ipi, decimal? List, decimal Icms)> lines)
    {
        var list = lines.ToList();
        var products = list.Sum(l => Money(l.Qty * l.Price));
        var ipi = list.Sum(l => Money(l.Qty * l.Price * l.Ipi / 100m));
        var icms = list.Sum(l => Money(l.Qty * l.Price * l.Icms / 100m));
        var discount = list.Where(l => l.List is > 0).Select(l => Math.Round((1 - l.Price / l.List!.Value) * 100m, 2)).DefaultIfEmpty(0).Max();
        return new QuoteTotals(products, ipi, products + ipi, discount, list.Count(l => l.List is not > 0), icms);
    }

    public static QuoteTotals Totals(Quote q) => Totals(q.Lines.Select(l => (l.Quantity, l.UnitPrice, l.IpiPercent, l.ListPrice, l.IcmsPercent)));

    /// <summary>A quote needs the manager when a discount passes the limit, or (if the setting is on) when a price was typed by hand with no list price to compare.</summary>
    public static bool NeedsApprovalFor(QuoteTotals t, SalesSettings s) => t.MaxDiscountPercent > s.MaxDiscountPercent || s.OffListNeedsApproval && t.OffListLines > 0;

    private async Task RefreshOrderStatusAsync(SalesOrder o, string note, string? user, CancellationToken ct)
    {
        if (o.Status is SalesOrderStatus.Created or SalesOrderStatus.Cancelled) return;
        var ids = o.Lines.Select(l => l.Id).ToList();
        var shipped = await ShippedAsync(ids, ct);
        var all = o.Lines.All(l => shipped.GetValueOrDefault(l.Id) >= l.Quantity);
        var any = shipped.Values.Any(v => v > 0);
        var allDelivered = all && !await db.Deliveries.AnyAsync(d => d.OrderId == o.Id && d.Status == DeliveryStatus.Shipped, ct);
        var next = allDelivered ? SalesOrderStatus.Delivered : all ? SalesOrderStatus.Shipped : any ? SalesOrderStatus.PartiallyShipped : SalesOrderStatus.Released;
        foreach (var line in o.Lines.Where(l => shipped.GetValueOrDefault(l.Id) >= l.Quantity && l.ReservationId is not null))
            if (await db.StockReservations.FirstOrDefaultAsync(r => r.Id == line.ReservationId && r.Status == ReservationStatus.Open, ct) is { } r)
                r.Status = ReservationStatus.Released;
        if (next != o.Status) Log(SalesRecordKind.Order, o.Id, "status", o.Status, next, note, user);
        else Log(SalesRecordKind.Order, o.Id, "delivery", o.Status, o.Status, note, user);
        o.Status = next;
        await db.SaveChangesAsync(ct);
    }

    private async Task<int> ShippingLocationAsync(CancellationToken ct)
    {
        if ((await SettingsAsync(ct)).ShippingLocationId is { } s) return s;
        if ((await production.SettingsAsync(ct)).ReceiptLocationId is { } r) return r;
        return await db.StockLocations.Where(l => l.Code == ProductionService.DefaultReceiptLocationCode && l.Active).Select(l => (int?)l.Id).FirstOrDefaultAsync(ct)
               ?? throw SalesException.Conflict($"Set the shipping location in /api/sales/settings or create stock location {ProductionService.DefaultReceiptLocationCode}");
    }

    private sealed record ResolvedLine(int ProductId, string? CustomerPartNumber, string Description, decimal Quantity, string Unit, decimal UnitPrice, decimal? ListPrice, decimal IpiPercent, decimal IcmsPercent, int? LeadTimeDays, DateOnly? DeliveryDate, LineSpec? Spec = null, int? FeasibilityId = null);

    private async Task<List<ResolvedLine>> BuildLinesAsync(int customerId, IReadOnlyList<SalesLineInput>? input, CancellationToken ct)
    {
        if (input is null || input.Count == 0) throw SalesException.Invalid("lines", "At least one item");
        var today = Today();
        var ids = input.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.Products.AsNoTracking().Where(p => ids.Contains(p.Id)).ToDictionaryAsync(p => p.Id, ct);
        var customerParts = await db.ProductCustomers.AsNoTracking().Where(pc => pc.CustomerId == customerId && ids.Contains(pc.ProductId)).ToDictionaryAsync(pc => pc.ProductId, ct);
        var result = new List<ResolvedLine>();
        foreach (var (l, n) in input.Select((l, n) => (l, n)))
        {
            var f = $"lines[{n}]";
            if (!products.TryGetValue(l.ProductId, out var p)) throw SalesException.Invalid($"{f}.productId", "Product not found");
            if (p.Blocked) throw SalesException.Invalid($"{f}.productId", $"Product {p.Code} is blocked");
            if (l.Quantity <= 0) throw SalesException.Invalid($"{f}.quantity", "Must be greater than zero");
            if (l.UnitPrice < 0) throw SalesException.Invalid($"{f}.unitPrice", "Cannot be negative");
            if (l.IpiPercent is < 0 or > 100) throw SalesException.Invalid($"{f}.ipiPercent", "Between 0 and 100");
            if (l.IcmsPercent is < 0 or > 100) throw SalesException.Invalid($"{f}.icmsPercent", "Between 0 and 100");
            if (l.LeadTimeDays is < 0) throw SalesException.Invalid($"{f}.leadTimeDays", "Cannot be negative");
            var price = await PriceAsync(p.Id, customerId, today, ct);
            var unitPrice = l.UnitPrice ?? price?.UnitPrice ?? throw SalesException.Invalid($"{f}.unitPrice", $"No price for {p.Code}; give one or register it in the price list");
            customerParts.TryGetValue(p.Id, out var cp);
            result.Add(new ResolvedLine(p.Id, cp?.CustomerPartNumber, Clean(l.Description) ?? cp?.CustomerDescription ?? p.Name, l.Quantity, p.StockUnit, unitPrice, price?.UnitPrice,
                l.IpiPercent ?? price?.IpiPercent ?? 0m, l.IcmsPercent ?? price?.IcmsPercent ?? 0m, l.LeadTimeDays, l.DeliveryDate, l.Spec, l.FeasibilityId));
        }
        return result;
    }

    private static QuoteLine ToQuoteLine(ResolvedLine l, int n) => new()
    {
        Sequence = (n + 1) * 10, ProductId = l.ProductId, CustomerPartNumber = l.CustomerPartNumber, Description = l.Description, Quantity = l.Quantity, Unit = l.Unit,
        UnitPrice = l.UnitPrice, ListPrice = l.ListPrice, IpiPercent = l.IpiPercent, IcmsPercent = l.IcmsPercent, LeadTimeDays = l.LeadTimeDays, DeliveryDate = l.DeliveryDate
    };

    private static void ApplyHeader(Quote q, QuoteInput i)
    {
        q.AddressId = i.AddressId;
        q.PaymentTermId = i.PaymentTermId;
        q.CustomPaymentTerm = Clean(i.CustomPaymentTerm);
        q.Freight = i.Freight;
        q.ContactName = Clean(i.ContactName);
        q.ContactEmail = Clean(i.ContactEmail);
        q.CustomerReference = Clean(i.CustomerReference);
        q.Notes = Clean(i.Notes);
    }

    private async Task ValidateHeaderAsync(int customerId, int? addressId, int? paymentTermId, CancellationToken ct)
    {
        var customer = await db.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.Id == customerId, ct) ?? throw SalesException.Invalid("customerId", "Customer not found");
        if (!customer.Active) throw SalesException.Invalid("customerId", $"Customer {customer.Name} is inactive");
        if (addressId is { } a && !await db.CustomerAddresses.AnyAsync(x => x.Id == a && x.CustomerId == customerId, ct)) throw SalesException.Invalid("addressId", "Address does not belong to the customer");
        if (paymentTermId is { } p && !await db.PaymentTerms.AnyAsync(x => x.Id == p && x.Active, ct)) throw SalesException.Invalid("paymentTermId", "Unknown or inactive payment term");
    }

    private async Task<Quote> QuoteStep(int id, string action, string? note, string? user, CancellationToken ct, Func<Quote, Task<string?>> change) =>
        await InTransaction(async () =>
        {
            var q = await LockQuoteAsync(id, ct);
            var from = q.Status;
            var overridden = await change(q);
            Log(SalesRecordKind.Quote, q.Id, overridden ?? action, from, q.Status, Clean(note), user);
            await db.SaveChangesAsync(ct);
            return q;
        }, ct);

    private void Log(SalesRecordKind kind, int id, string action, object? from, object? to, string? note, string? user) =>
        db.SalesEvents.Add(new SalesEvent { Kind = kind, RecordId = id, Action = action, FromStatus = from?.ToString(), ToStatus = to?.ToString(), Note = Clean(note), User = user, At = DateTimeOffset.UtcNow });

    private async Task<int> NextAsync(string sequence, CancellationToken ct) =>
        await db.Database.SqlQueryRaw<int>("SELECT nextval('" + SqlIdentifier.Safe(sequence) + "')::int AS \"Value\"").SingleAsync(ct);

    private async Task<Quote> LockQuoteAsync(int id, CancellationToken ct)
    {
        if ((await db.Database.SqlQuery<int>($"SELECT id AS \"Value\" FROM quotes WHERE id = {id} FOR UPDATE").ToListAsync(ct)).Count == 0) throw SalesException.NotFound("Quote");
        var q = await db.Quotes.Include(x => x.Lines).FirstAsync(x => x.Id == id, ct);
        await db.Entry(q).ReloadAsync(ct);
        return q;
    }

    private async Task<SalesOrder> LockOrderAsync(int id, CancellationToken ct)
    {
        if ((await db.Database.SqlQuery<int>($"SELECT id AS \"Value\" FROM sales_orders WHERE id = {id} FOR UPDATE").ToListAsync(ct)).Count == 0) throw SalesException.NotFound("Order");
        var o = await db.SalesOrders.Include(x => x.Lines).FirstAsync(x => x.Id == id, ct);
        await db.Entry(o).ReloadAsync(ct);
        return o;
    }

    private async Task<Delivery> LockDeliveryAsync(int id, CancellationToken ct)
    {
        if ((await db.Database.SqlQuery<int>($"SELECT id AS \"Value\" FROM deliveries WHERE id = {id} FOR UPDATE").ToListAsync(ct)).Count == 0) throw SalesException.NotFound("Delivery");
        var d = await db.Deliveries.Include(x => x.Lines).FirstAsync(x => x.Id == id, ct);
        await db.Entry(d).ReloadAsync(ct);
        return d;
    }

    private Task<T> InTransaction<T>(Func<Task<T>> work, CancellationToken ct) => db.InTransactionAsync(work, ct);

    public static DateOnly Today() => Ebt.Core.Services.Clock.Today();
    private static decimal Money(decimal d) => Math.Round(d, 2, MidpointRounding.AwayFromZero);
}
