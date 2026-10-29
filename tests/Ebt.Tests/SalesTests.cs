using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Certificates;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Sales;

namespace Ebt.Tests;

[Collection("api")]
public class SalesTests(ApiFixture api)
{
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.Today);

    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();

    private sealed record Setup(CustomerOut Customer, CustomerAddressOut Address, ProductOut Tube, ProductOut Other, StockLocationOut Shipping, PaymentTermOut Term);

    private static ProductIn Tube(string code) => new(code, "Tubo " + code, ProductKind.Part, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, null, null, "73063010", "PC", 50, false, null, null);

    private static async Task<Setup> Arrange(HttpClient admin, decimal stock = 30m, decimal? creditLimit = 1_000_000m)
    {
        var customer = await (await admin.Post("/api/customers", new CustomerIn("Cliente " + Code("C"), null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var address = await (await admin.Post($"/api/customers/{customer.Id}/addresses", new CustomerAddressIn("26133636000103", "SP", null, "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", null, "06800000", "5101", "Edilto", "compras@cliente.com", null))).Read<CustomerAddressOut>();
        var tube = await (await admin.Post("/api/products", Tube(Code("T")))).Read<ProductOut>();
        var other = await (await admin.Post("/api/products", Tube(Code("O")))).Read<ProductOut>();
        var shipping = await (await admin.Post("/api/stock-locations", new StockLocationIn(Code("E", 10), "Expedição", StockLocationKind.Internal))).Read<StockLocationOut>();
        (await admin.Put("/api/sales/settings", new SalesSettingsDto(5m, 15, 0m, shipping.Id, "Validade 15 dias"))).EnsureSuccessStatusCode();
        if (stock > 0) (await admin.Post("/api/stock/documents", new StockPost(MovementType.AdjustmentIn, Today, [new StockLine(null, tube.Id, shipping.Id, stock, UnitCost: 5m)], "INV"))).EnsureSuccessStatusCode();
        var term = await (await admin.Post("/api/sales/payment-terms", new PaymentTermIn(Code("P", 8), "28 DDL", "28", creditLimit))).Read<PaymentTermOut>();
        (await admin.Post("/api/sales/price-list", new PriceListIn(tube.Id, null, 100m, 5m, 18m, Today.AddDays(-1), null))).EnsureSuccessStatusCode();
        (await admin.Post("/api/sales/price-list", new PriceListIn(other.Id, customer.Id, 20m, null, null, Today.AddDays(-1), null))).EnsureSuccessStatusCode();
        return new Setup(customer, address, tube, other, shipping, term);
    }

    private static QuoteInput Quote(Setup s, decimal otherPrice = 18m) => new(s.Customer.Id,
        [new SalesLineInput(s.Tube.Id, 100m, LeadTimeDays: 20), new SalesLineInput(s.Other.Id, 50m, otherPrice, DeliveryDate: Today.AddDays(30))],
        s.Address.Id, s.Term.Id, FreightTerms.Cif, null, "Edilto", "compras@cliente.com", "RFQ-77");

    private static Task<HttpResponseMessage> Act(HttpClient c, int id, string action, QuoteActionIn? body = null) => c.Post($"/api/sales/quotes/{id}/{action}", body ?? new QuoteActionIn());

    [Fact]
    public async Task Quote_to_delivery_flow()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var sales = await api.UserAsync(UserRole.Sales);
        var manager = await api.UserAsync(UserRole.SalesManager);
        var reader = await api.UserAsync(UserRole.Reader);

        Assert.Equal(HttpStatusCode.Forbidden, (await reader.Post("/api/sales/quotes", Quote(s))).StatusCode);
        var quote = await (await sales.Post("/api/sales/quotes", Quote(s))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Draft, quote.Status);
        Assert.StartsWith("PROP ", quote.Reference);
        Assert.Equal(100m, quote.Lines[0].UnitPrice);
        Assert.Equal(5m, quote.Lines[0].IpiPercent);
        Assert.Equal(10m, quote.Lines[1].DiscountPercent);
        Assert.True(quote.NeedsApproval);
        Assert.Equal(10_000m + 900m, quote.Totals.Products);
        Assert.Equal(500m, quote.Totals.Ipi);

        quote = await (await Act(sales, quote.Id, "send")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.PendingApproval, quote.Status);
        Assert.Equal(HttpStatusCode.Forbidden, (await Act(sales, quote.Id, "approve")).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await Act(sales, quote.Id, "accept")).StatusCode);
        quote = await (await Act(manager, quote.Id, "approve", new QuoteActionIn("Cliente estratégico"))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Approved, quote.Status);
        quote = await (await Act(sales, quote.Id, "send")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Sent, quote.Status);
        Assert.Equal("compras@cliente.com", quote.SentTo);
        Assert.Equal(Today.AddDays(15), quote.ValidUntil);

        Assert.Equal(HttpStatusCode.Conflict, (await Act(sales, quote.Id, "purchase-order")).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await sales.Put($"/api/sales/quotes/{quote.Id}/request", new QuoteRequestIn("cedo demais"))).StatusCode);
        quote = await (await Act(sales, quote.Id, "accept")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Accepted, quote.Status);
        Assert.Equal(HttpStatusCode.Conflict, (await sales.Post($"/api/sales/quotes/{quote.Id}/convert", new ConvertInput())).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await Act(sales, quote.Id, "purchase-order")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await sales.Put($"/api/sales/quotes/{quote.Id}/request", new QuoteRequestIn("Pedido 4521 por e-mail"))).StatusCode);
        quote = await (await Act(sales, quote.Id, "purchase-order", new QuoteActionIn(CustomerPo: "PO-4521"))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.PurchaseOrder, quote.Status);
        Assert.Equal("Pedido 4521 por e-mail", quote.RequestText);
        var order = await (await sales.Post($"/api/sales/quotes/{quote.Id}/convert", new ConvertInput())).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.Created, order.Status);
        Assert.Equal("PO-4521", order.CustomerPo);
        Assert.Equal(quote.Reference, order.QuoteReference);
        Assert.Equal(Today.AddDays(20), order.Lines[0].DueDate);
        quote = await (await sales.GetAsync($"/api/sales/quotes/{quote.Id}")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Converted, quote.Status);
        Assert.Equal(order.Id, quote.SalesOrderId);
        Assert.Equal(["converted", "po-received", "accepted", "sent", "approved", "submitted", "created"], quote.History.Select(h => h.Action));

        Assert.Equal(HttpStatusCode.Conflict, (await sales.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).StatusCode);
        order = await (await sales.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn())).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.Released, order.Status);
        Assert.Equal(30m, order.Lines[0].FromStock);
        Assert.NotNull(order.Lines[0].ProductionReference);
        Assert.Equal(ProductionOrderStatus.Created, order.Lines[0].ProductionStatus);
        Assert.Equal(0m, order.Lines[1].FromStock);
        var of = await (await admin.GetAsync($"/api/production/orders/{order.Lines[0].ProductionOrderId}")).Read<ProductionOrderOut>();
        Assert.Equal(70m, of.Quantity);
        Assert.Equal(s.Customer.Id, of.CustomerId);
        Assert.False(order.Ready);

        var pipeline = await (await sales.GetAsync($"/api/sales/pipeline?customerId={s.Customer.Id}")).Read<PipelineOut>();
        Assert.Contains(pipeline.Stages.First(x => x.Key == "production").Cards, c => c.Id == order.Id);
        Assert.Equal(1, pipeline.Kpis.OpenOrders);

        var tooMuch = await sales.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today, Lines: [new DeliveryLineInput(order.Lines[0].Id, 101m)]));
        Assert.Equal(HttpStatusCode.BadRequest, tooMuch.StatusCode);
        var delivery = await (await sales.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today, Carrier: "Próprio", Lines: [new DeliveryLineInput(order.Lines[0].Id, 30m)]))).Read<DeliveryOut>();
        Assert.Equal(DeliveryStatus.Planned, delivery.Status);
        Assert.Equal(1, delivery.Packages);
        Assert.StartsWith("ENT ", delivery.Reference);

        var stock = await api.UserAsync(UserRole.Stock);
        delivery = await (await stock.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, "2581", null, "abc1d23"))).Read<DeliveryOut>();
        Assert.Equal(DeliveryStatus.Shipped, delivery.Status);
        Assert.Equal("ABC1D23", delivery.VehiclePlate);
        Assert.NotNull(delivery.StockDocumentId);
        var balance = (await (await admin.GetAsync($"/api/stock/balances?productId={s.Tube.Id}&locationId={s.Shipping.Id}")).Read<Page<StockBalanceOut>>()).Items.Sum(b => b.Quantity);
        Assert.Equal(0m, balance);

        order = await (await sales.GetAsync($"/api/sales/orders/{order.Id}")).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.PartiallyShipped, order.Status);
        Assert.Equal(30m, order.Lines[0].Shipped);
        Assert.Equal(70m, order.Lines[0].Remaining);

        delivery = await (await sales.Post($"/api/sales/deliveries/{delivery.Id}/confirm", new ConfirmDeliveryIn(Today, "Portaria"))).Read<DeliveryOut>();
        Assert.Equal(DeliveryStatus.Delivered, delivery.Status);
        Assert.Equal(["delivered", "shipped", "created"], delivery.History.Select(h => h.Action));

        Assert.Equal(HttpStatusCode.Conflict, (await sales.Post($"/api/sales/orders/{order.Id}/cancel", new SalesReasonIn("Cliente desistiu"))).StatusCode);
    }

    [Fact]
    public async Task Full_stock_order_ships_and_completes()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 40m);
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 40m)], "PO-1", s.Term.Id))).Read<SalesOrderOut>();
        Assert.Equal(100m, order.Lines[0].UnitPrice);
        order = await (await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn())).Read<SalesOrderOut>();
        Assert.Null(order.Lines[0].ProductionOrderId);
        Assert.True(order.Ready);
        var pipeline = await (await admin.GetAsync($"/api/sales/pipeline?customerId={s.Customer.Id}")).Read<PipelineOut>();
        Assert.Contains(pipeline.Stages.First(x => x.Key == "certificate").Cards, c => c.Id == order.Id && c.Badges.Contains("ready"));
        Assert.DoesNotContain(pipeline.Stages.First(x => x.Key == "ready").Cards, c => c.Id == order.Id);

        var certificate = await (await admin.Post("/api/sales/certificates", new CertificateInput(order.Id, RawMaterialLot: "700261", Hardness: "66 HRB"))).Read<CertificateOut>();
        Assert.Equal(CertificateStatus.Draft, certificate.Status);
        Assert.Equal("PO-1", certificate.CustomerPo);
        Assert.Equal(40m, certificate.Quantity);
        Assert.Equal(order.Lines[0].Id, certificate.OrderLineId);
        Assert.Matches(@"^\d+-\d\d$", certificate.Reference);
        Assert.Equal(2146, certificate.Number);
        Assert.Contains(certificate.Measures, m => m.Kind == CertificateMeasureKind.Dimensional && m.Name == "Espessura" && m.Specified == "1,50");
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post($"/api/sales/certificates/{certificate.Id}/issue", new object())).StatusCode);
        var measures = certificate.Measures.Select(m => new CertificateMeasureInput(m.Kind, m.Name, m.Specified, m.Name == "C" ? "0,081" : null)).ToList();
        certificate = await (await admin.Put($"/api/sales/certificates/{certificate.Id}", new CertificateInput(order.Id, CustomerPo: "PO-1", Quantity: 40m, Measures: measures, RawMaterialLot: "700261"))).Read<CertificateOut>();
        certificate = await (await admin.Post($"/api/sales/certificates/{certificate.Id}/issue", new object())).Read<CertificateOut>();
        Assert.Equal(CertificateStatus.Issued, certificate.Status);
        Assert.Equal(HttpStatusCode.Conflict, (await admin.Put($"/api/sales/certificates/{certificate.Id}", new CertificateInput(order.Id))).StatusCode);
        pipeline = await (await admin.GetAsync($"/api/sales/pipeline?customerId={s.Customer.Id}")).Read<PipelineOut>();
        Assert.Contains(pipeline.Stages.First(x => x.Key == "ready").Cards, c => c.Id == order.Id && c.Badges.Contains("ready"));

        var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        Assert.Equal(40m, delivery.Lines.Single().Quantity);
        certificate = await (await admin.Post($"/api/sales/certificates/{certificate.Id}/link-delivery", new CertificateLinkIn(delivery.Id))).Read<CertificateOut>();
        Assert.Equal(delivery.Reference, certificate.DeliveryReference);
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, "2581"))).EnsureSuccessStatusCode();
        certificate = await (await admin.GetAsync($"/api/sales/certificates/{certificate.Id}")).Read<CertificateOut>();
        Assert.Equal("2581", certificate.EffectiveInvoiceNumber);
        Assert.Contains((await (await admin.GetAsync("/api/sales/certificates?q=2581")).Read<Page<CertificateSummaryOut>>()).Items, c => c.Id == certificate.Id);
        order = await (await admin.GetAsync($"/api/sales/orders/{order.Id}")).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.Shipped, order.Status);

        var cancelled = await (await admin.Post($"/api/sales/deliveries/{delivery.Id}/cancel", new SalesReasonIn("NF recusada"))).Read<DeliveryOut>();
        Assert.Equal(DeliveryStatus.Cancelled, cancelled.Status);
        order = await (await admin.GetAsync($"/api/sales/orders/{order.Id}")).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.Released, order.Status);

        delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today))).EnsureSuccessStatusCode();
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/confirm", new ConfirmDeliveryIn())).EnsureSuccessStatusCode();
        order = await (await admin.GetAsync($"/api/sales/orders/{order.Id}")).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.Delivered, order.Status);
    }

    [Fact]
    public async Task Credit_limit_needs_manager_override()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 0m, creditLimit: 1000m);
        var sales = await api.UserAsync(UserRole.Sales);
        var input = new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 20m)], null, s.Term.Id, OverrideCredit: true);
        Assert.Equal(HttpStatusCode.Conflict, (await sales.Post("/api/sales/orders", input)).StatusCode);
        var manager = await api.UserAsync(UserRole.SalesManager);
        var order = await (await manager.Post("/api/sales/orders", input)).Read<SalesOrderOut>();
        Assert.Contains(order.History, h => h.Action == "credit-override");
        Assert.True(order.Credit.Exceeded);

        order = await (await sales.Post($"/api/sales/orders/{order.Id}/cancel", new SalesReasonIn("Teste"))).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.Cancelled, order.Status);
    }

    [Fact]
    public async Task Declined_quote_can_be_revised_and_resent()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var quote = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        Assert.False(quote.NeedsApproval);
        quote = await (await Act(admin, quote.Id, "send")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Sent, quote.Status);
        Assert.Equal(HttpStatusCode.BadRequest, (await Act(admin, quote.Id, "decline")).StatusCode);
        quote = await (await Act(admin, quote.Id, "decline", new QuoteActionIn("Preço alto"))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Rejected, quote.Status);
        var original = quote;
        Assert.EndsWith($"{original.Number}", original.Reference);
        Assert.Equal(HttpStatusCode.BadRequest, (await Act(admin, quote.Id, "revise")).StatusCode);
        quote = await (await Act(admin, quote.Id, "revise", new QuoteActionIn("Cliente mudou o pedido", CustomerPo: "PO-9"))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Draft, quote.Status);
        Assert.EndsWith("-B", quote.Reference);
        Assert.Equal(original.Number, quote.Number);
        Assert.Equal("PO-9", quote.CustomerPo);
        Assert.Equal(original.Lines.Count, quote.Lines.Count);
        var cancelled = await (await admin.GetAsync($"/api/sales/quotes/{original.Id}")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Cancelled, cancelled.Status);
        Assert.EndsWith("-A", cancelled.Reference);
        Assert.Equal("Cliente mudou o pedido", cancelled.DecisionNote);
        var edit = Quote(s, otherPrice: 19.5m) with { Notes = "Nova condição" };
        quote = await (await admin.Put($"/api/sales/quotes/{quote.Id}", edit)).Read<QuoteOut>();
        Assert.Equal(19.5m, quote.Lines[1].UnitPrice);
        Assert.Equal(HttpStatusCode.Conflict, (await admin.DeleteAsync($"/api/sales/quotes/{quote.Id}")).StatusCode);
        quote = await (await Act(admin, quote.Id, "send", new QuoteActionIn(SentTo: "edilto@cliente.com"))).Read<QuoteOut>();
        Assert.Equal("edilto@cliente.com", quote.SentTo);
        quote = await (await Act(admin, quote.Id, "cancel", new QuoteActionIn("Projeto cancelado"))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Cancelled, quote.Status);
    }

    [Fact]
    public async Task Price_lookup_prefers_customer_price()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        (await admin.Post("/api/sales/price-list", new PriceListIn(s.Tube.Id, s.Customer.Id, 95m, null, null, Today, null))).EnsureSuccessStatusCode();
        var p = await (await admin.GetAsync($"/api/sales/price?productId={s.Tube.Id}&customerId={s.Customer.Id}")).Read<PriceOut>();
        Assert.Equal(95m, p.UnitPrice);
        Assert.True(p.CustomerSpecific);
        var generic = await (await admin.GetAsync($"/api/sales/price?productId={s.Tube.Id}")).Read<PriceOut>();
        Assert.Equal(100m, generic.UnitPrice);
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post("/api/sales/payment-terms", new PaymentTermIn("X1", "Errado", "28/abc", null))).StatusCode);
    }
}
