using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Sales;

namespace Ebt.Tests;

[Collection("api")]
public class ViabilitySteelTests(ApiFixture api)
{
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.Today);

    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();

    private sealed record Setup(CustomerOut Customer, CustomerAddressOut Address, ProductOut Tube);

    private static async Task<Setup> Arrange(HttpClient admin)
    {
        var customer = await (await admin.Post("/api/customers", new CustomerIn("Cliente " + Code("C"), null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var address = await (await admin.Post($"/api/customers/{customer.Id}/addresses", new CustomerAddressIn("26133636000103", "SP", null, "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", null, "06800000", null, null, null, null))).Read<CustomerAddressOut>();
        var tube = await (await admin.Post("/api/products", new ProductIn(Code("T"), "Tubo", ProductKind.Part, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, null, null, "73063010", "PC", 50, false, null, null))).Read<ProductOut>();
        (await admin.Post("/api/sales/price-list", new PriceListIn(tube.Id, null, 100m, 5m, 18m, Today.AddDays(-1), null))).EnsureSuccessStatusCode();
        return new Setup(customer, address, tube);
    }

    private static SalesOrderIn Order(Setup s, int? studyId = null, LineSpec? spec = null) =>
        new(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 10m, Spec: spec, FeasibilityId: studyId)], BillTo: BillTo.Bts, Origin: OrderOrigin.Email, Salesperson: "Marcos");

    [Fact]
    public async Task Order_carries_header_and_line_specs()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var spec = new LineSpec(25.4m, 1.5m, 6000m, "NBR 5599", DeliveryCondition.Nbk, "PC", 2.5m, null, 0.05m, 0.05m, 30m);
        var order = await (await admin.Post("/api/sales/orders", Order(s, spec: spec))).Read<SalesOrderOut>();
        Assert.Equal(BillTo.Bts, order.BillTo);
        Assert.Equal(OrderOrigin.Email, order.Origin);
        Assert.Equal("Marcos", order.Salesperson);
        var line = order.Lines[0];
        Assert.Equal("NBR 5599", line.Spec!.Standard);
        Assert.Equal(DeliveryCondition.Nbk, line.Spec.Condition);
        Assert.Equal(25m, line.Spec.MaterialNeedKg);
        Assert.Equal(1000m, line.BalanceValue);

        var bad = await admin.Post("/api/sales/orders", Order(s, spec: spec with { SaleUnit = "XX" }));
        Assert.Equal(HttpStatusCode.BadRequest, bad.StatusCode);

        var late = await (await admin.GetAsync($"/api/sales/orders?customerId={s.Customer.Id}&billTo=Bts&month={DateTime.Today.AddDays(30):yyyy-MM}")).Read<Page<SalesOrderSummaryOut>>();
        Assert.All(late.Items, o => Assert.Equal(BillTo.Bts, o.BillTo));
    }

    [Fact]
    public async Task Feasibility_needs_three_signoffs_and_covers_three_orders()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var sales = await api.UserAsync(UserRole.Sales);
        var eng = await api.UserAsync(UserRole.Engineering);
        var prod = await api.UserAsync(UserRole.Production);

        var study = await (await sales.Post("/api/viability", new FeasibilityIn(s.Customer.Id, "Tubo 25,4", ProductId: s.Tube.Id, Characteristics: "Ø25,4 x 1,5", Transformations: "Corte + furação", Packaging: "Fardo", MonthlyConsumptionKg: 800m))).Read<FeasibilityOut>();
        Assert.StartsWith("FAV ", study.Reference);
        Assert.Equal(FeasibilityStatus.Draft, study.Status);
        Assert.Equal(HttpStatusCode.Conflict, (await eng.Post($"/api/viability/{study.Id}/sign/quality", new FeasibilityNoteIn())).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post("/api/sales/orders", Order(s, study.Id))).StatusCode);

        (await sales.Post($"/api/viability/{study.Id}/submit", new { })).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Forbidden, (await sales.Post($"/api/viability/{study.Id}/sign/quality", new FeasibilityNoteIn())).StatusCode);
        study = await (await eng.Post($"/api/viability/{study.Id}/sign/quality", new FeasibilityNoteIn("Capaz"))).Read<FeasibilityOut>();
        Assert.Equal(FeasibilityStatus.InReview, study.Status);
        Assert.Equal(HttpStatusCode.Conflict, (await eng.Post($"/api/viability/{study.Id}/sign/quality", new FeasibilityNoteIn())).StatusCode);
        study = await (await prod.Post($"/api/viability/{study.Id}/sign/production", new FeasibilityNoteIn())).Read<FeasibilityOut>();
        study = await (await sales.Post($"/api/viability/{study.Id}/sign/commercial", new FeasibilityNoteIn())).Read<FeasibilityOut>();
        Assert.Equal(FeasibilityStatus.Approved, study.Status);
        Assert.All(study.Signoffs, x => Assert.NotNull(x.At));

        for (var n = 1; n <= 3; n++)
        {
            var o = await (await admin.Post("/api/sales/orders", Order(s, study.Id))).Read<SalesOrderOut>();
            Assert.Equal(study.Id, o.Lines[0].FeasibilityId);
        }
        Assert.Equal(HttpStatusCode.Conflict, (await admin.Post("/api/sales/orders", Order(s, study.Id))).StatusCode);
        study = await (await admin.GetAsync($"/api/viability/{study.Id}")).Read<FeasibilityOut>();
        Assert.Equal(3, study.OrdersUsed);
        Assert.Equal(0, study.OrdersRemaining);
        Assert.Equal(3, study.Orders.Count);
        Assert.Equal(HttpStatusCode.Conflict, (await sales.Post($"/api/viability/{study.Id}/reopen", new { })).StatusCode);
    }

    [Fact]
    public async Task Feasibility_rejection_and_quote_conversion()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var study = await (await admin.Post("/api/viability", new FeasibilityIn(s.Customer.Id, "Rejeitável", ProductId: s.Tube.Id, Characteristics: "x"))).Read<FeasibilityOut>();
        (await admin.Post($"/api/viability/{study.Id}/submit", new { })).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post($"/api/viability/{study.Id}/reject/quality", new FeasibilityNoteIn())).StatusCode);
        study = await (await admin.Post($"/api/viability/{study.Id}/reject/quality", new FeasibilityNoteIn("Tolerância inviável"))).Read<FeasibilityOut>();
        Assert.Equal(FeasibilityStatus.Rejected, study.Status);
        Assert.Contains("Tolerância", study.RejectionReason);

        var quote = await (await admin.Post("/api/sales/quotes", new QuoteInput(s.Customer.Id, [new SalesLineInput(s.Tube.Id, 10m)], s.Address.Id))).Read<QuoteOut>();
        var linked = await (await admin.Post("/api/viability", new FeasibilityIn(s.Customer.Id, "Da proposta", QuoteId: quote.Id, ProductId: s.Tube.Id, Characteristics: "y"))).Read<FeasibilityOut>();
        Assert.Equal(quote.Reference, linked.QuoteId is null ? null : (await (await admin.GetAsync($"/api/viability/{linked.Id}")).Read<FeasibilityOut>()).QuoteReference);
        foreach (var step in new[] { "submit", "sign/quality", "sign/production", "sign/commercial" })
            (await admin.Post($"/api/viability/{linked.Id}/{step}", new FeasibilityNoteIn())).EnsureSuccessStatusCode();
        foreach (var step in new[] { "send", "accept" })
            (await admin.Post($"/api/sales/quotes/{quote.Id}/{step}", new QuoteActionIn(SentTo: "a@b.com", CustomerPo: "PO-1"))).EnsureSuccessStatusCode();
        var order = await (await admin.Post($"/api/sales/quotes/{quote.Id}/convert", new ConvertInput())).Read<SalesOrderOut>();
        Assert.Equal(linked.Id, order.Lines[0].FeasibilityId);
        Assert.Equal(linked.Reference, order.Lines[0].FeasibilityReference);
    }

    [Fact]
    public async Task Steel_lot_slitter_and_usage_balance()
    {
        var admin = await api.AdminAsync();
        var stock = await api.UserAsync(UserRole.Stock);
        var reader = await api.UserAsync(UserRole.Reader);
        var mill = await (await admin.Post("/api/suppliers", new SupplierIn("Usina " + Code("U"), null, null, null))).Read<SupplierOut>();
        var slitter = await (await admin.Post("/api/suppliers", new SupplierIn("Açoservice " + Code("A"), null, null, null))).Read<SupplierOut>();

        Assert.Equal(HttpStatusCode.Forbidden, (await reader.Post("/api/steel/lots", new SteelLotIn(Code("B"), mill.Id, Today, 1000m, 6m, "123", "DC01", 1.5m, 1200m, null))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await stock.Post("/api/steel/lots", new SteelLotIn(Code("B"), mill.Id, Today, 0m, 6m, null, null, null, null, null))).StatusCode);
        var lot = await (await stock.Post("/api/steel/lots", new SteelLotIn(Code("B"), mill.Id, Today, 1000m, 6m, "123", "DC01", 1.5m, 1200m, null))).Read<SteelLotOut>();
        Assert.Equal(1000m, lot.BalanceKg);
        Assert.Equal(6000m, lot.BalanceValue);

        Assert.Equal(HttpStatusCode.BadRequest, (await stock.Post("/api/steel/slitter", new SlitterJobIn(lot.Id, slitter.Id, Today, 2000m, "N1", null, null, null, null, null, null))).StatusCode);
        var job = await (await stock.Post("/api/steel/slitter", new SlitterJobIn(lot.Id, slitter.Id, Today, 800m, "N1", null, null, null, null, null, null))).Read<SlitterJobOut>();
        Assert.False(job.Returned);
        lot = await (await stock.GetAsync($"/api/steel/lots/{lot.Id}")).Read<SteelLotOut>();
        Assert.Equal(200m, lot.BalanceKg);
        Assert.Equal(1, lot.PendingJobs);

        job = await (await stock.Put($"/api/steel/slitter/{job.Id}", new SlitterJobIn(lot.Id, slitter.Id, Today, 800m, "N1", "R9", Today, 760m, 30m, 400m, null))).Read<SlitterJobOut>();
        Assert.True(job.Returned);
        Assert.Equal(5m, job.LossPercent);
        Assert.Equal(HttpStatusCode.BadRequest, (await stock.Put($"/api/steel/slitter/{job.Id}", new SlitterJobIn(lot.Id, slitter.Id, Today, 800m, "N1", "R9", Today, 790m, 30m, 400m, null))).StatusCode);

        (await stock.Post("/api/steel/usages", new SteelUsageIn(lot.Id, Today, 100m, 50m, "OF 1", null))).EnsureSuccessStatusCode();
        lot = await (await stock.GetAsync($"/api/steel/lots/{lot.Id}")).Read<SteelLotOut>();
        Assert.Equal(860m, lot.BalanceKg);
        Assert.Equal(5160m, lot.BalanceValue);
        Assert.Equal(6450m, lot.TotalCost);
        Assert.Equal(0, lot.PendingJobs);
        Assert.Single(await (await reader.GetAsync($"/api/steel/lots/{lot.Id}/slitter")).Read<List<SlitterJobOut>>());
        Assert.Single(await (await reader.GetAsync($"/api/steel/lots/{lot.Id}/usages")).Read<List<SteelUsageOut>>());
        Assert.Equal(HttpStatusCode.Conflict, (await stock.DeleteAsync($"/api/steel/lots/{lot.Id}")).StatusCode);
    }

    [Fact]
    public async Task Delivery_records_lot_invoiced_value_and_balances()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var loc = await (await admin.Post("/api/stock-locations", new StockLocationIn(Code("E", 10), "Expedição", StockLocationKind.Internal))).Read<StockLocationOut>();
        (await admin.Put("/api/sales/settings", new SalesSettingsDto(5m, 15, 0m, loc.Id, null))).EnsureSuccessStatusCode();
        (await admin.Post("/api/stock/documents", new StockPost(MovementType.AdjustmentIn, Today, [new StockLine(null, s.Tube.Id, loc.Id, 10m, UnitCost: 5m)], "INV"))).EnsureSuccessStatusCode();
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 10m, Spec: new LineSpec(SaleUnit: "PC", PieceWeightKg: 2m))]))).Read<SalesOrderOut>();
        (await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn())).EnsureSuccessStatusCode();
        var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today, Lines: [new DeliveryLineInput(order.Lines[0].Id, 4m)]))).Read<DeliveryOut>();
        delivery = await (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, "99", LotNumber: "L-77", InvoicedValue: 420m))).Read<DeliveryOut>();
        Assert.Equal("L-77", delivery.LotNumber);
        Assert.Equal(420m, delivery.InvoicedValue);
        Assert.Equal(400m, delivery.ValueExIpi);
        Assert.Equal(12m, delivery.BalanceKg);
        Assert.Equal(600m, delivery.BalanceValue);
    }
}
