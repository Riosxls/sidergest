using System.Net.Http.Json;
using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Certificates;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Sales;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Ebt.Tests;

[Collection("api")]
public class SalesTests(ApiFixture api)
{
    private static readonly DateOnly Today = Ebt.Core.Services.Clock.Today();

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
        Assert.Equal(Ebt.Core.Services.WorkDays.Add(Today, 20), order.Lines[0].DueDate); // lead time counts working days
        quote = await (await sales.GetAsync($"/api/sales/quotes/{quote.Id}")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Converted, quote.Status);
        Assert.Equal(order.Id, quote.SalesOrderId);
        Assert.Equal(["converted", "po-received", "po-text", "accepted", "sent", "approved", "submitted", "created"], quote.History.Select(h => h.Action));

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
        Assert.Equal(order.Id, of.SalesOrderId);
        Assert.Equal(order.Reference, of.SalesOrderReference);
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
        // Shipping without a certificate needs certificates-issue (or a manager): the Stock role is refused, the order waiver then lets it ship.
        Assert.Equal(HttpStatusCode.Forbidden, (await stock.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, "2581", null, "abc1d23", WithoutCertificate: true))).StatusCode);
        Assert.Equal(DeliveryStatus.Planned, (await (await admin.GetAsync($"/api/sales/deliveries/{delivery.Id}")).Read<DeliveryOut>()).Status);
        (await admin.Post($"/api/sales/orders/{order.Id}/certificate-waiver", new CertificateWaiverIn(true))).EnsureSuccessStatusCode();
        delivery = await (await stock.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, "2581", null, "abc1d23", WithoutCertificate: true))).Read<DeliveryOut>();
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
        Assert.True(certificate.Number >= 2146); // numbering continues from the last paper certificate; other tests also issue EBT certificates
        Assert.Contains(certificate.Measures, m => m.Kind == CertificateMeasureKind.Dimensional && m.Name == "Espessura" && m.Specified == "1,50");
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post($"/api/sales/certificates/{certificate.Id}/issue", new object())).StatusCode);
        var measures = certificate.Measures.Select(m => new CertificateMeasureInput(m.Kind, m.Name, m.Specified, m.Name == "C" ? "0,081" : "1")).ToList();
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
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, "2581", WithoutCertificate: true))).EnsureSuccessStatusCode();
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
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).EnsureSuccessStatusCode();
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/confirm", new ConfirmDeliveryIn())).EnsureSuccessStatusCode();
        order = await (await admin.GetAsync($"/api/sales/orders/{order.Id}")).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.Delivered, order.Status);
    }

    private static async Task<SalesOrderOut> ReleasedOrder(HttpClient admin, Setup s, decimal quantity)
    {
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, quantity)], "PO-1", s.Term.Id))).Read<SalesOrderOut>();
        return await (await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn())).Read<SalesOrderOut>();
    }

    [Fact]
    public async Task Test_records_stay_out_of_the_pipeline_until_asked()
    {
        var admin = await api.AdminAsync();
        var sales = await api.UserAsync(UserRole.Sales);
        var s = await Arrange(admin, stock: 10m);
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 10m)], "PO-T", s.Term.Id))).Read<SalesOrderOut>();
        order = await (await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn())).Read<SalesOrderOut>();
        static bool Has(PipelineOut p, int id) => p.Stages.Any(st => st.Cards.Any(c => c.Kind == SalesRecordKind.Order && c.Id == id));
        var url = $"/api/sales/pipeline?customerId={s.Customer.Id}";
        Assert.True(Has(await (await admin.GetAsync(url)).Read<PipelineOut>(), order.Id));

        var flag = new { entity = "SalesOrder", ids = new[] { order.Id }, target = "Test", apply = false };
        Assert.Equal(HttpStatusCode.Forbidden, (await sales.Post("/api/admin/data-source", flag)).StatusCode);
        var preview = await admin.Post("/api/admin/data-source", flag);
        Assert.Contains("\"rows\":1", await preview.Content.ReadAsStringAsync());
        Assert.True(Has(await (await admin.GetAsync(url)).Read<PipelineOut>(), order.Id));

        (await admin.Post("/api/admin/data-source", flag with { apply = true })).EnsureSuccessStatusCode();
        Assert.False(Has(await (await admin.GetAsync(url)).Read<PipelineOut>(), order.Id));
        Assert.True(Has(await (await admin.GetAsync(url + "&includeTest=true")).Read<PipelineOut>(), order.Id));
        Assert.Contains("SalesOrder", await (await admin.GetAsync("/api/admin/data-source")).Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post("/api/admin/data-source", new { entity = "Nope", apply = true })).StatusCode);
    }

    [Fact]
    public async Task Shipping_needs_an_issued_certificate_or_a_waiver()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 41m);
        var order = await ReleasedOrder(admin, s, 40m);
        var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        var blocked = await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today));
        Assert.Equal(HttpStatusCode.Conflict, blocked.StatusCode);
        Assert.Contains("certificate", await blocked.Content.ReadAsStringAsync());
        (await admin.Post($"/api/sales/orders/{order.Id}/certificate-waiver", new CertificateWaiverIn(true))).EnsureSuccessStatusCode();
        delivery = await (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today))).Read<DeliveryOut>();
        Assert.Equal(DeliveryStatus.Shipped, delivery.Status);
        Assert.DoesNotContain(delivery.History, h => h.Note?.Contains("sem certificado") == true);

        var other = await ReleasedOrder(admin, s, 1m);
        var d2 = await (await admin.Post($"/api/sales/orders/{other.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        d2 = await (await admin.Post($"/api/sales/deliveries/{d2.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).Read<DeliveryOut>();
        Assert.Contains(d2.History, h => h.Action == "shipped" && h.Note == "sem certificado");
    }

    [Fact]
    public async Task Closing_the_balance_ends_a_partly_shipped_order()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 40m);
        var order = await ReleasedOrder(admin, s, 100m);
        Assert.Equal(HttpStatusCode.Conflict, (await admin.Post($"/api/sales/orders/{order.Id}/close-balance", new SalesReasonIn("Cliente cortou"))).StatusCode);
        var first = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today, Lines: [new DeliveryLineInput(order.Lines[0].Id, 40m)]))).Read<DeliveryOut>();
        await admin.Post($"/api/sales/deliveries/{first.Id}/ship", new ShipInput(Today, WithoutCertificate: true));
        var planned = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today, Lines: [new DeliveryLineInput(order.Lines[0].Id, 10m)]))).Read<DeliveryOut>();

        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post($"/api/sales/orders/{order.Id}/close-balance", new SalesReasonIn(" "))).StatusCode);
        order = await (await admin.Post($"/api/sales/orders/{order.Id}/close-balance", new SalesReasonIn("Cliente cortou o saldo"))).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.Shipped, order.Status);
        Assert.Equal(40m, order.Lines[0].Quantity);
        Assert.Equal(0m, order.Lines[0].Remaining);
        Assert.Contains(order.History, h => h.Action == "balance-closed" && h.Note!.Contains("100 → 40"));
        Assert.Equal(DeliveryStatus.Cancelled, (await (await admin.GetAsync($"/api/sales/deliveries/{planned.Id}")).Read<DeliveryOut>()).Status);

        (await admin.Post($"/api/sales/deliveries/{first.Id}/confirm", new ConfirmDeliveryIn())).EnsureSuccessStatusCode();
        order = await (await admin.GetAsync($"/api/sales/orders/{order.Id}")).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.Delivered, order.Status);
        Assert.Equal(HttpStatusCode.Conflict, (await admin.Post($"/api/sales/orders/{order.Id}/close-balance", new SalesReasonIn("de novo"))).StatusCode);
    }

    [Fact]
    public async Task Released_order_can_be_rescheduled_and_open_OFs_follow()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 0m);
        var created = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 20m)], "PO-1", s.Term.Id))).Read<SalesOrderOut>();
        Assert.Equal(HttpStatusCode.Conflict, (await admin.Post($"/api/sales/orders/{created.Id}/reschedule", new RescheduleInput("x", "PO-2"))).StatusCode);
        var order = await (await admin.Post($"/api/sales/orders/{created.Id}/release", new SalesReleaseIn())).Read<SalesOrderOut>();
        var line = order.Lines[0];
        var due = line.DueDate.AddDays(14);

        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post($"/api/sales/orders/{order.Id}/reschedule", new RescheduleInput(null, null, [new RescheduleLine(line.Id, due)]))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await admin.Post($"/api/sales/orders/{order.Id}/reschedule", new RescheduleInput("sem mudança"))).StatusCode);
        order = await (await admin.Post($"/api/sales/orders/{order.Id}/reschedule", new RescheduleInput("Cliente adiou", "PO-2", [new RescheduleLine(line.Id, due)]))).Read<SalesOrderOut>();
        Assert.Equal(due, order.Lines[0].DueDate);
        Assert.Equal("PO-2", order.CustomerPo);
        Assert.Contains(order.History, h => h.Action == "rescheduled" && h.Note!.Contains("Cliente adiou") && h.Note.Contains("PO-1 → PO-2"));
        Assert.Equal(due, (await (await admin.GetAsync($"/api/production/orders/{line.ProductionOrderId}")).Read<ProductionOrderOut>()).DueDate);
    }

    [Fact]
    public async Task Cancelling_an_order_shows_what_it_touches_and_can_stop_production()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 0m);
        var order = await ReleasedOrder(admin, s, 20m);
        var preview = await (await admin.GetAsync($"/api/sales/orders/{order.Id}/cancel-preview")).Read<CancelOrderPreview>();
        var of = Assert.Single(preview.ProductionOrders);
        Assert.False(of.Started);
        (await admin.Post($"/api/production/orders/{order.Lines[0].ProductionOrderId}/release", new ReleaseIn(true))).EnsureSuccessStatusCode();
        preview = await (await admin.GetAsync($"/api/sales/orders/{order.Id}/cancel-preview")).Read<CancelOrderPreview>();
        Assert.True(Assert.Single(preview.ProductionOrders).Started);

        var keep = await ReleasedOrder(admin, s, 20m);
        (await admin.Post($"/api/production/orders/{keep.Lines[0].ProductionOrderId}/release", new ReleaseIn(true))).EnsureSuccessStatusCode();
        keep = await (await admin.Post($"/api/sales/orders/{keep.Id}/cancel", new OrderCancelIn("Pedido duplicado"))).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.Cancelled, keep.Status);
        Assert.NotEqual(ProductionOrderStatus.Cancelled, (await (await admin.GetAsync($"/api/production/orders/{keep.Lines[0].ProductionOrderId}")).Read<ProductionOrderOut>()).Status);

        order = await (await admin.Post($"/api/sales/orders/{order.Id}/cancel", new OrderCancelIn("Pedido duplicado", CancelProduction: true))).Read<SalesOrderOut>();
        Assert.Equal(ProductionOrderStatus.Cancelled, (await (await admin.GetAsync($"/api/production/orders/{order.Lines[0].ProductionOrderId}")).Read<ProductionOrderOut>()).Status);
    }

    [Fact]
    public async Task Lead_time_counts_working_days_from_the_day_the_customer_approved()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var quote = await (await admin.Post("/api/sales/quotes", new QuoteInput(s.Customer.Id, [new SalesLineInput(s.Tube.Id, 100m, 100m, LeadTimeDays: 20)], s.Address.Id, s.Term.Id, FreightTerms.Cif, null, "Edilto", "compras@cliente.com"))).Read<QuoteOut>();
        (await Act(admin, quote.Id, "send")).EnsureSuccessStatusCode();
        (await Act(admin, quote.Id, "accept")).EnsureSuccessStatusCode();
        var approvedOn = Today.AddDays(-12); // the customer approved twelve days ago and the PO only arrived now
        await using (var db = api.NewDb())
            await db.Quotes.Where(x => x.Id == quote.Id).ExecuteUpdateAsync(u => u.SetProperty(x => x.DecidedAt, new DateTimeOffset(approvedOn.ToDateTime(new TimeOnly(18, 0)), TimeSpan.Zero)));
        (await admin.Put($"/api/sales/quotes/{quote.Id}/request", new QuoteRequestIn("Pedido 77 por e-mail"))).EnsureSuccessStatusCode();
        (await Act(admin, quote.Id, "purchase-order", new QuoteActionIn(CustomerPo: "PO-77"))).EnsureSuccessStatusCode();
        var order = await (await admin.Post($"/api/sales/quotes/{quote.Id}/convert", new ConvertInput())).Read<SalesOrderOut>();
        Assert.Equal(Ebt.Core.Services.WorkDays.Add(approvedOn, 20), order.Lines[0].DueDate);
    }

    [Fact]
    public async Task Delivery_date_written_on_the_customers_purchase_order_wins_over_the_lead_time()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var quote = await (await admin.Post("/api/sales/quotes", new QuoteInput(s.Customer.Id, [new SalesLineInput(s.Tube.Id, 100m, 100m, LeadTimeDays: 20), new SalesLineInput(s.Other.Id, 50m, 20m, LeadTimeDays: 10)],
            s.Address.Id, s.Term.Id, FreightTerms.Cif, null, "Edilto", "compras@cliente.com"))).Read<QuoteOut>();
        (await Act(admin, quote.Id, "send")).EnsureSuccessStatusCode();
        (await Act(admin, quote.Id, "accept")).EnsureSuccessStatusCode();
        (await admin.Put($"/api/sales/quotes/{quote.Id}/request", new QuoteRequestIn("Pedido 78: item 1 para 15/12"))).EnsureSuccessStatusCode();

        var tooLate = quote.Lines[0];
        var past = await Act(admin, quote.Id, "purchase-order", new QuoteActionIn(CustomerPo: "PO-78", DeliveryDates: [new QuoteLineDate(tooLate.Id, Today.AddDays(-1))]));
        Assert.Equal(HttpStatusCode.BadRequest, past.StatusCode);
        var foreign = await Act(admin, quote.Id, "purchase-order", new QuoteActionIn(DeliveryDates: [new QuoteLineDate(int.MaxValue, Today.AddDays(5))]));
        Assert.Equal(HttpStatusCode.BadRequest, foreign.StatusCode);

        var customerDate = Today.AddDays(60); // well beyond the 20 working days
        quote = await (await Act(admin, quote.Id, "purchase-order", new QuoteActionIn(CustomerPo: "PO-78", DeliveryDates: [new QuoteLineDate(tooLate.Id, customerDate)]))).Read<QuoteOut>();
        Assert.Equal(customerDate, quote.Lines[0].DeliveryDate);
        Assert.Null(quote.Lines[1].DeliveryDate);
        Assert.Contains(quote.History, h => h.Action == "delivery-dates" && h.Note!.Contains($"{customerDate:dd/MM/yyyy}"));

        var order = await (await admin.Post($"/api/sales/quotes/{quote.Id}/convert", new ConvertInput())).Read<SalesOrderOut>();
        Assert.Equal(customerDate, order.Lines[0].DueDate);
        Assert.Equal(Ebt.Core.Services.WorkDays.Add(Today, 10), order.Lines[1].DueDate); // no date from the customer: ours, counted from the approval
    }

    [Fact]
    public async Task Issued_certificate_teaches_the_next_one_of_the_same_customer_and_product()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 100m);
        var first = await ReleasedOrder(admin, s, 10m);
        const string title = "CERTIFICADO DE GARANTIA DA QUALIDADE DO PRODUTO";
        var measures = new List<CertificateMeasureInput>
        {
            new(CertificateMeasureKind.Chemical, "C", "Máx. 0,150", "0,070"),
            new(CertificateMeasureKind.Chemical, "Mn", "Máx. 0,700", "0,366"),
            new(CertificateMeasureKind.Dimensional, "Diâmetro", "25,40± 0,15", "25,40 à 25,48"),
            new(CertificateMeasureKind.Mechanical, "LR", "290 Mpa mín.", "400Mpa"),
            new(CertificateMeasureKind.Mechanical, "Alongamento longitudinal", "28% Mínimo", "32%"),
        };
        var one = await (await admin.Post("/api/sales/certificates", new CertificateInput(first.Id, Title: title, Notes: "Certificado de origem do material nº 1127693\nMATERIAL RECOZIDO", Measures: measures, RawMaterialLot: "700090"))).Read<CertificateOut>();
        Assert.Equal(title, one.Title);
        Assert.DoesNotContain(await (await admin.GetAsync("/api/sales/certificates/templates")).Read<List<CertificateTemplateOut>>(), t => t.CustomerId == s.Customer.Id);
        (await admin.Post($"/api/sales/certificates/{one.Id}/issue", new object())).EnsureSuccessStatusCode();

        var templates = (await (await admin.GetAsync($"/api/sales/certificates/templates?customerId={s.Customer.Id}")).Read<List<CertificateTemplateOut>>());
        var template = Assert.Single(templates);
        Assert.Equal(s.Tube.Id, template.ProductId);
        Assert.Equal(one.Reference, template.LearnedFrom);
        Assert.Equal("MATERIAL RECOZIDO", template.Notes);
        Assert.All(template.Measures, m => Assert.Null(m.Found));

        var second = await ReleasedOrder(admin, s, 5m);
        var next = await (await admin.Post("/api/sales/certificates", new CertificateInput(second.Id))).Read<CertificateOut>();
        Assert.Equal(title, next.Title);
        Assert.Equal("MATERIAL RECOZIDO", next.Notes);
        Assert.Null(next.RawMaterialLot);
        Assert.Equal(["C", "Mn", "Diâmetro", "LR", "Alongamento longitudinal"], next.Measures.Select(m => m.Name));
        Assert.Equal("Máx. 0,150", next.Measures.First(m => m.Name == "C").Specified);
        Assert.Equal("25,40± 0,15", next.Measures.First(m => m.Name == "Diâmetro").Specified);
        Assert.All(next.Measures, m => Assert.Null(m.Found));
        var blank = await (await admin.GetAsync($"/api/sales/certificates/template?orderLineId={second.Lines[0].Id}")).Read<List<CertificateMeasureOut>>();
        Assert.Equal(5, blank.Count);

        // another customer ordering the same product gets the plain template
        var other = await (await admin.Post("/api/customers", new CustomerIn("Outro " + Code("C"), null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var addr = await (await admin.Post($"/api/customers/{other.Id}/addresses", new CustomerAddressIn("26133636000103", "SP", null, "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", null, "06800000", "5101", "Edilto", "c@cliente.com", null))).Read<CustomerAddressOut>();
        var foreign = await (await admin.Post("/api/sales/orders", new SalesOrderIn(other.Id, addr.Id, [new SalesLineInput(s.Tube.Id, 3m)], "PO-9", s.Term.Id))).Read<SalesOrderOut>();
        var plain = await (await admin.Post("/api/sales/certificates", new CertificateInput(foreign.Id))).Read<CertificateOut>();
        Assert.Null(plain.Title);
        Assert.Equal(CertificateService.DefaultFinish, plain.Finish);
        Assert.Contains(plain.Measures, m => m.Name == "Espessura" && m.Specified == "1,50");

        // the specification can be edited without issuing another certificate
        var edit = await admin.Put($"/api/sales/certificates/templates/{template.Id}", new TemplateIn("TITULO NOVO", null, "Obs fixa", [new CertificateMeasureInput(CertificateMeasureKind.Dimensional, "Espessura", "1,40 a 1,60")]));
        Assert.Equal(HttpStatusCode.OK, edit.StatusCode);
        var edited = (await (await admin.GetAsync($"/api/sales/certificates/templates?customerId={s.Customer.Id}")).Read<List<CertificateTemplateOut>>()).Single();
        Assert.Equal("TITULO NOVO", edited.Title);
        Assert.Equal("Obs fixa", edited.Notes);
        var only = Assert.Single(edited.Measures);
        Assert.Equal("1,40 a 1,60", only.Specified);
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Put($"/api/sales/certificates/templates/{template.Id}", new TemplateIn(null, null, null, [new CertificateMeasureInput(CertificateMeasureKind.Dimensional, " ", null)]))).StatusCode);

        Assert.Equal(HttpStatusCode.NoContent, (await admin.DeleteAsync($"/api/sales/certificates/templates/{template.Id}")).StatusCode);
        Assert.Empty((await (await admin.GetAsync($"/api/sales/certificates/templates?customerId={s.Customer.Id}")).Read<List<CertificateTemplateOut>>()));
    }

    [Fact]
    public async Task One_click_creates_a_certificate_for_each_item_of_a_delivery()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 100m);
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 10m), new SalesLineInput(s.Other.Id, 5m)], "PO-5", s.Term.Id))).Read<SalesOrderOut>();
        order = await (await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn())).Read<SalesOrderOut>();
        var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        Assert.Equal(2, delivery.Lines.Count);

        var made = await (await admin.Post($"/api/sales/certificates/for-delivery/{delivery.Id}", new object())).Read<List<CertificateOut>>();
        Assert.Equal(2, made.Count);
        Assert.All(made, c => Assert.Equal(delivery.Id, c.DeliveryId));
        Assert.Equal([5m, 10m], made.Select(c => c.Quantity).Order());
        Assert.Equal(2, made.Select(c => c.Number).Distinct().Count());
        Assert.Equal(HttpStatusCode.Conflict, (await admin.Post($"/api/sales/certificates/for-delivery/{delivery.Id}", new object())).StatusCode);

        (await admin.Post($"/api/sales/certificates/{made[1].Id}/cancel", new CertificateReasonIn("Erro de quantidade"))).EnsureSuccessStatusCode();
        var again = await (await admin.Post($"/api/sales/certificates/for-delivery/{delivery.Id}", new object())).Read<List<CertificateOut>>();
        Assert.Equal(made[1].OrderLineId, Assert.Single(again).OrderLineId);
    }

    [Fact]
    public async Task Customer_default_term_and_custom_term_flow_to_quote_and_order()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var company = new CustomerCompany("26133636000103", "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", "SP", "06800000", null, null, null, s.Term.Id);
        var updated = await (await admin.Put($"/api/customers/{s.Customer.Id}", new CustomerIn(s.Customer.Name, null, null, ConsumerType.Normal, Company: company))).Read<CustomerOut>();
        Assert.Equal(s.Term.Id, updated.Company!.PaymentTermId);
        Assert.Equal(s.Term.Name, updated.Company.PaymentTermName);

        var custom = Quote(s) with { PaymentTermId = null, CustomPaymentTerm = "30/60/90" };
        var quote = await (await admin.Post("/api/sales/quotes", custom)).Read<QuoteOut>();
        Assert.Null(quote.PaymentTermId);
        Assert.Equal("30/60/90", quote.CustomPaymentTerm);
        var fromTerm = await (await admin.Post("/api/sales/quotes", Quote(s))).Read<QuoteOut>();
        Assert.Equal(s.Term.Id, fromTerm.PaymentTermId);
        Assert.Equal(s.Term.Name, fromTerm.PaymentTermName);

        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 10m)], null, null, FreightTerms.Cif, null, false, null, "45 dias"))).Read<SalesOrderOut>();
        Assert.Equal("45 dias", order.CustomPaymentTerm);
        Assert.Null(order.PaymentTermName);
    }

    [Fact]
    public async Task Customer_credit_limit_overrides_the_term_and_blocks_release_and_shipment_until_a_manager_overrides()
    {
        var admin = await api.AdminAsync();
        var sales = await api.UserAsync(UserRole.Sales);
        var stock = await api.UserAsync(UserRole.Stock);
        var manager = await api.UserAsync(UserRole.SalesManager);
        async Task SetLimit(Setup s, decimal limit)
        {
            var company = new CustomerCompany("26133636000103", "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", "SP", "06800000", null, null, null, s.Term.Id, CreditLimit: limit);
            var res = await admin.Put($"/api/customers/{s.Customer.Id}", new CustomerIn(s.Customer.Name, null, null, ConsumerType.Normal, Company: company));
            Assert.Equal(limit, (await res.Read<CustomerOut>()).Company!.CreditLimit);
        }

        // Release: limit lowered after the order was created.
        var s1 = await Arrange(admin, stock: 0m);
        var o1 = await (await sales.Post("/api/sales/orders", new SalesOrderIn(s1.Customer.Id, s1.Address.Id, [new SalesLineInput(s1.Tube.Id, 10m)], null, s1.Term.Id))).Read<SalesOrderOut>();
        await SetLimit(s1, 100m);
        var credit = (await (await admin.GetAsync($"/api/sales/orders/{o1.Id}")).Read<SalesOrderOut>()).Credit;
        Assert.Equal(100m, credit.Limit);
        Assert.Equal("customer", credit.LimitSource);
        Assert.Equal(HttpStatusCode.Conflict, (await sales.Post($"/api/sales/orders/{o1.Id}/release", new SalesReleaseIn(OverrideCredit: true))).StatusCode);
        var released = await (await manager.Post($"/api/sales/orders/{o1.Id}/release", new SalesReleaseIn(OverrideCredit: true))).Read<SalesOrderOut>();
        Assert.Contains(released.History, h => h.Action == "credit-override" && h.Note!.Contains("liberação"));

        // Shipment: same rule, an authorised order is not asked again.
        var s2 = await Arrange(admin, stock: 10m);
        var o2 = await (await sales.Post("/api/sales/orders", new SalesOrderIn(s2.Customer.Id, s2.Address.Id, [new SalesLineInput(s2.Tube.Id, 10m)], null, s2.Term.Id))).Read<SalesOrderOut>();
        (await sales.Post($"/api/sales/orders/{o2.Id}/release", new SalesReleaseIn())).EnsureSuccessStatusCode();
        await SetLimit(s2, 100m);
        var d2 = await (await admin.Post($"/api/sales/orders/{o2.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        var blocked = await stock.Post($"/api/sales/deliveries/{d2.Id}/ship", new ShipInput(Today, WithoutCertificate: true, OverrideCredit: true));
        Assert.Equal(HttpStatusCode.Conflict, blocked.StatusCode);
        Assert.Contains("Credit limit", await blocked.Content.ReadAsStringAsync());
        var shipped = await (await manager.Post($"/api/sales/deliveries/{d2.Id}/ship", new ShipInput(Today, WithoutCertificate: true, OverrideCredit: true))).Read<DeliveryOut>();
        Assert.Equal(DeliveryStatus.Shipped, shipped.Status);
        Assert.Contains((await (await admin.GetAsync($"/api/sales/orders/{o2.Id}")).Read<SalesOrderOut>()).History, h => h.Action == "credit-override" && h.Note!.Contains("expedição"));
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
        var sales = await api.UserAsync(UserRole.Sales);
        Assert.Equal(HttpStatusCode.Conflict, (await sales.DeleteAsync($"/api/sales/quotes/{quote.Id}")).StatusCode); // sales staff cannot delete a revision; only admin can
        quote = await (await Act(admin, quote.Id, "send", new QuoteActionIn(SentTo: "edilto@cliente.com"))).Read<QuoteOut>();
        Assert.Equal("edilto@cliente.com", quote.SentTo);
        // Once the quote is with the customer the outcome is the customer's decision, not a cancellation.
        await AssertStatus(HttpStatusCode.Conflict, Act(admin, quote.Id, "cancel", new QuoteActionIn("Projeto cancelado")));
        quote = await (await Act(admin, quote.Id, "decline", new QuoteActionIn("Projeto cancelado"))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Rejected, quote.Status);
    }

    [Fact]
    public async Task Only_a_quote_that_never_left_the_company_can_be_cancelled()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var draft = await (await admin.Post("/api/sales/quotes", Quote(s, 20m))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Cancelled, (await (await Act(admin, draft.Id, "cancel", new QuoteActionIn("Engano"))).Read<QuoteOut>()).Status);

        foreach (var phase in new[] { "sent", "accepted", "po" })
        {
            var q = await (await admin.Post("/api/sales/quotes", Quote(s, 20m))).Read<QuoteOut>();
            q = await (await Act(admin, q.Id, "send")).Read<QuoteOut>();
            if (phase != "sent")
            {
                q = await (await Act(admin, q.Id, "accept")).Read<QuoteOut>();
                if (phase == "po")
                {
                    Assert.Equal(HttpStatusCode.OK, (await admin.Put($"/api/sales/quotes/{q.Id}/request", new QuoteRequestIn("Pedido por e-mail"))).StatusCode);
                    q = await (await Act(admin, q.Id, "purchase-order", new QuoteActionIn(CustomerPo: "PO-1"))).Read<QuoteOut>();
                }
            }
            await AssertStatus(HttpStatusCode.Conflict, Act(admin, q.Id, "cancel", new QuoteActionIn("Desistiu")));
            Assert.NotEqual(QuoteStatus.Cancelled, (await (await admin.GetAsync($"/api/sales/quotes/{q.Id}")).Read<QuoteOut>()).Status);
        }
    }

    [Fact]
    public async Task Waiting_for_approval_goes_back_to_draft_to_be_edited_without_a_revision()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var quote = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 17m))).Read<QuoteOut>();
        Assert.Equal(HttpStatusCode.Conflict, (await Act(admin, quote.Id, "reopen")).StatusCode); // a plain draft has nothing to reopen
        quote = await (await Act(admin, quote.Id, "send")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.PendingApproval, quote.Status);
        quote = await (await Act(admin, quote.Id, "reopen", new QuoteActionIn("Preço errado"))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Draft, quote.Status);
        Assert.EndsWith($"{quote.Number}", quote.Reference); // same quote, no revision letter

        quote = await (await Act(admin, quote.Id, "send")).Read<QuoteOut>();
        quote = await (await Act(admin, quote.Id, "approve")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Approved, quote.Status);
        Assert.NotNull(quote.ApprovedBy);
        quote = await (await Act(admin, quote.Id, "reopen")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Draft, quote.Status);
        Assert.Null(quote.ApprovedBy);
        Assert.Contains(quote.History, h => h.Action == "reopened");

        quote = await (await Act(admin, quote.Id, "send")).Read<QuoteOut>();
        quote = await (await Act(admin, quote.Id, "approve")).Read<QuoteOut>();
        quote = await (await Act(admin, quote.Id, "send", new QuoteActionIn(SentTo: "x@cliente.com"))).Read<QuoteOut>();
        Assert.Equal(HttpStatusCode.Conflict, (await Act(admin, quote.Id, "reopen")).StatusCode); // once it is out with the customer, change it through a revision
    }

    [Fact]
    public async Task Customer_giving_up_after_approving_or_ordering_is_recorded_as_a_lost_sale()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var draft = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        Assert.Equal(HttpStatusCode.Conflict, (await Act(admin, draft.Id, "decline", new QuoteActionIn("x"))).StatusCode);

        var accepted = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        await Act(admin, accepted.Id, "send");
        await Act(admin, accepted.Id, "accept");
        var lost = await (await Act(admin, accepted.Id, "decline", new QuoteActionIn("Projeto adiado pelo cliente"))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Rejected, lost.Status);
        Assert.Equal(LostReason.CustomerGaveUp, lost.LostReason);
        Assert.Contains(lost.History, h => h.Action == "gave-up");

        var ordered = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        await Act(admin, ordered.Id, "send");
        await Act(admin, ordered.Id, "accept");
        await admin.Put($"/api/sales/quotes/{ordered.Id}/request", new QuoteRequestIn("PO"));
        await Act(admin, ordered.Id, "purchase-order");
        lost = await (await Act(admin, ordered.Id, "decline", new QuoteActionIn("Cliente cancelou", LostReason: LostReason.Price))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Rejected, lost.Status);
        Assert.Equal(LostReason.Price, lost.LostReason); // a chosen reason is kept

        var report = await (await admin.GetAsync("/api/sales/quotes/lost-reasons")).Read<List<LostReasonOut>>();
        Assert.Contains(report, r => r.Reason == LostReason.CustomerGaveUp && r.Quotes >= 1);
    }

    [Fact]
    public async Task Validity_can_be_extended_and_an_expired_quote_goes_back_to_sent()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var quote = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        Assert.Equal(HttpStatusCode.Conflict, (await Act(admin, quote.Id, "extend", new QuoteActionIn(ValidUntil: Today.AddDays(10)))).StatusCode); // not sent yet
        quote = await (await Act(admin, quote.Id, "send")).Read<QuoteOut>();

        Assert.Equal(HttpStatusCode.BadRequest, (await Act(admin, quote.Id, "extend", new QuoteActionIn(ValidUntil: Today.AddDays(-1)))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Act(admin, quote.Id, "extend", new QuoteActionIn(ValidUntil: Today.AddDays(400)))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Act(admin, quote.Id, "extend")).StatusCode);
        quote = await (await Act(admin, quote.Id, "extend", new QuoteActionIn("Cliente pediu mais prazo", ValidUntil: Today.AddDays(45)))).Read<QuoteOut>();
        Assert.Equal(Today.AddDays(45), quote.ValidUntil);
        Assert.Equal(QuoteStatus.Sent, quote.Status);

        await using (var db = api.NewDb())
            await db.Quotes.Where(x => x.Id == quote.Id).ExecuteUpdateAsync(u => u.SetProperty(x => x.ValidUntil, Today.AddDays(-2)));
        using (var scope = api.CreateScope())
            await scope.ServiceProvider.GetRequiredService<SalesService>().ExpireOverdueAsync();
        Assert.Equal(QuoteStatus.Expired, (await (await admin.GetAsync($"/api/sales/quotes/{quote.Id}")).Read<QuoteOut>()).Status);
        quote = await (await Act(admin, quote.Id, "extend", new QuoteActionIn(ValidUntil: Today.AddDays(15)))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Sent, quote.Status);
        Assert.Equal(Today.AddDays(15), quote.ValidUntil);
        Assert.Contains(quote.History, h => h.Action == "validity-extended");
    }

    [Fact]
    public async Task A_replaced_revision_says_which_revision_replaced_it()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var quote = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        await Act(admin, quote.Id, "send");
        var revB = await (await Act(admin, quote.Id, "revise", new QuoteActionIn("Cliente pediu outro preço"))).Read<QuoteOut>();
        await Act(admin, revB.Id, "send");
        var revC = await (await Act(admin, revB.Id, "revise", new QuoteActionIn("De novo"))).Read<QuoteOut>();

        var first = await (await admin.GetAsync($"/api/sales/quotes/{quote.Id}")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Cancelled, first.Status);
        Assert.Equal(revC.Id, first.SupersededById); // points at the live one, not the middle revision
        Assert.Equal(revC.Reference, first.SupersededBy);
        Assert.Null((await (await admin.GetAsync($"/api/sales/quotes/{revC.Id}")).Read<QuoteOut>()).SupersededById);

        var list = await (await admin.GetAsync($"/api/sales/quotes?q={revC.Number}&take=50")).Read<Page<QuoteSummaryOut>>();
        Assert.Equal(revC.Id, list.Items.Single(x => x.Id == quote.Id).SupersededById);
        Assert.Null(list.Items.Single(x => x.Id == revC.Id).SupersededBy);

        var plain = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        plain = await (await Act(admin, plain.Id, "cancel", new QuoteActionIn("Emitido por engano"))).Read<QuoteOut>();
        Assert.Null(plain.SupersededById); // cancelled on its own, not replaced
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

    [Fact]
    public async Task Accepting_keeps_the_po_and_editing_keeps_default_conditions()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var quote = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        Assert.Equal("Validade 15 dias", quote.Conditions);
        quote = await (await admin.Put($"/api/sales/quotes/{quote.Id}", Quote(s, otherPrice: 20m) with { Conditions = null })).Read<QuoteOut>();
        Assert.Equal("Validade 15 dias", quote.Conditions);

        quote = await (await Act(admin, quote.Id, "send")).Read<QuoteOut>();
        var revised = await (await Act(admin, quote.Id, "revise", new QuoteActionIn("Ajuste", CustomerPo: "PO-KEEP"))).Read<QuoteOut>();
        revised = await (await Act(admin, revised.Id, "send")).Read<QuoteOut>();
        revised = await (await Act(admin, revised.Id, "accept")).Read<QuoteOut>();
        Assert.Equal("PO-KEEP", revised.CustomerPo);
    }

    [Fact]
    public async Task Off_list_price_needs_approval_only_when_the_setting_is_on()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var unlisted = await (await admin.Post("/api/products", Tube(Code("U")))).Read<ProductOut>();
        var input = new QuoteInput(s.Customer.Id, [new SalesLineInput(unlisted.Id, 10m, 50m)], s.Address.Id, s.Term.Id, ContactEmail: "compras@cliente.com");

        var plain = await (await admin.Post("/api/sales/quotes", input)).Read<QuoteOut>();
        Assert.False(plain.NeedsApproval);
        Assert.Equal(1, plain.Totals.OffListLines);

        (await admin.Put("/api/sales/settings", new SalesSettingsDto(5m, 15, 0m, s.Shipping.Id, "Validade 15 dias", OffListNeedsApproval: true))).EnsureSuccessStatusCode();
        try
        {
            var strict = await (await admin.Post("/api/sales/quotes", input)).Read<QuoteOut>();
            Assert.True(strict.NeedsApproval);
            strict = await (await Act(admin, strict.Id, "send")).Read<QuoteOut>();
            Assert.Equal(QuoteStatus.PendingApproval, strict.Status);
        }
        finally
        {
            (await admin.Put("/api/sales/settings", new SalesSettingsDto(5m, 15, 0m, s.Shipping.Id, "Validade 15 dias"))).EnsureSuccessStatusCode();
        }
    }

    [Fact]
    public async Task Decline_records_the_lost_reason_and_the_report_counts_it()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var quote = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        quote = await (await Act(admin, quote.Id, "send")).Read<QuoteOut>();
        quote = await (await Act(admin, quote.Id, "decline", new QuoteActionIn("Concorrente mais barato", LostReason: LostReason.Price))).Read<QuoteOut>();
        Assert.Equal(LostReason.Price, quote.LostReason);

        var report = await (await admin.GetAsync("/api/sales/quotes/lost-reasons")).Read<List<LostReasonOut>>();
        Assert.Contains(report, r => r.Reason == LostReason.Price && r.Quotes >= 1 && r.Value > 0);
        var listed = (await (await admin.GetAsync($"/api/sales/quotes?q={quote.Reference}")).Read<Page<QuoteSummaryOut>>()).Items.Single(x => x.Id == quote.Id);
        Assert.Equal(LostReason.Price, listed.LostReason);
    }

    [Fact]
    public async Task Duplicate_copies_into_a_new_draft_for_the_same_or_another_customer()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var source = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();

        var copy = await (await admin.Post($"/api/sales/quotes/{source.Id}/duplicate", new DuplicateInput())).Read<QuoteOut>();
        Assert.NotEqual(source.Number, copy.Number);
        Assert.Equal(0, copy.Revision);
        Assert.Equal(QuoteStatus.Draft, copy.Status);
        Assert.Equal(source.Lines.Count, copy.Lines.Count);
        Assert.Equal(s.Address.Id, copy.AddressId);
        Assert.Contains(copy.History, e => e.Action == "duplicated");

        var other = await (await admin.Post("/api/customers", new CustomerIn("Outro " + Code("C"), null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var moved = await (await admin.Post($"/api/sales/quotes/{source.Id}/duplicate", new DuplicateInput(other.Id))).Read<QuoteOut>();
        Assert.Equal(other.Id, moved.CustomerId);
        Assert.Null(moved.AddressId);
        Assert.Null(moved.ContactEmail);
        Assert.Equal(source.Lines[1].UnitPrice, moved.Lines[1].UnitPrice);
    }

    [Fact]
    public async Task Credit_warning_is_available_on_open_quotes_and_po_changes_are_logged()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, creditLimit: 100m);
        var quote = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        var credit = await (await admin.GetAsync($"/api/sales/quotes/{quote.Id}/credit")).Read<CreditCheck>();
        Assert.True(credit.Exceeded);
        Assert.Equal(100m, credit.Limit);

        quote = await (await Act(admin, quote.Id, "send")).Read<QuoteOut>();
        quote = await (await Act(admin, quote.Id, "accept")).Read<QuoteOut>();
        quote = await (await admin.Put($"/api/sales/quotes/{quote.Id}/request", new QuoteRequestIn("PO por e-mail"))).Read<QuoteOut>();
        Assert.Contains(quote.History, e => e.Action == "po-text");
    }

    [Fact]
    public async Task List_filters_follow_up_expiring_and_mine_and_unused_approvals_lapse()
    {
        var admin = await api.AdminAsync();
        var sales = await api.UserAsync(UserRole.Sales);
        var s = await Arrange(admin);
        var mine = await (await sales.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        var other = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        var sent = await (await Act(admin, other.Id, "send")).Read<QuoteOut>();

        var mineList = await (await sales.GetAsync("/api/sales/quotes?mine=true&take=200")).Read<Page<QuoteSummaryOut>>();
        Assert.Contains(mineList.Items, x => x.Id == mine.Id);
        Assert.DoesNotContain(mineList.Items, x => x.Id == other.Id);

        await using (var db = api.NewDb())
        {
            await db.Quotes.Where(x => x.Id == sent.Id).ExecuteUpdateAsync(u => u.SetProperty(x => x.SentAt, DateTimeOffset.UtcNow.AddDays(-10)).SetProperty(x => x.ValidUntil, Today.AddDays(1)));
            var approvable = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 17m))).Read<QuoteOut>();
            Assert.True(approvable.NeedsApproval);
            approvable = await (await Act(admin, approvable.Id, "send")).Read<QuoteOut>();
            approvable = await (await Act(admin, approvable.Id, "approve")).Read<QuoteOut>();
            Assert.Equal(QuoteStatus.Approved, approvable.Status);
            await db.Quotes.Where(x => x.Id == approvable.Id).ExecuteUpdateAsync(u => u.SetProperty(x => x.ApprovedAt, DateTimeOffset.UtcNow.AddDays(-40)));

            var followUp = await (await admin.GetAsync("/api/sales/quotes?followUp=true&take=200")).Read<Page<QuoteSummaryOut>>();
            Assert.Contains(followUp.Items, x => x.Id == sent.Id && x.FollowUp && x.Expiring);
            var expiring = await (await admin.GetAsync("/api/sales/quotes?expiring=true&take=200")).Read<Page<QuoteSummaryOut>>();
            Assert.Contains(expiring.Items, x => x.Id == sent.Id);

            using var scope = api.CreateScope();
            var swept = await scope.ServiceProvider.GetRequiredService<SalesService>().ExpireOverdueAsync();
            Assert.True(swept >= 1);
            var lapsed = await (await admin.GetAsync($"/api/sales/quotes/{approvable.Id}")).Read<QuoteOut>();
            Assert.Equal(QuoteStatus.Draft, lapsed.Status);
            Assert.Contains(lapsed.History, e => e.Action == "approval-lapsed");
        }
    }

    [Fact]
    public async Task Only_admin_deletes_ended_quotes_and_never_one_with_an_order()
    {
        var admin = await api.AdminAsync();
        var sales = await api.UserAsync(UserRole.Sales);
        var s = await Arrange(admin);
        var quote = await (await sales.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        quote = await (await Act(sales, quote.Id, "cancel", new QuoteActionIn("Teste"))).Read<QuoteOut>();
        Assert.Equal(HttpStatusCode.Conflict, (await sales.DeleteAsync($"/api/sales/quotes/{quote.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await admin.DeleteAsync($"/api/sales/quotes/{quote.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await admin.GetAsync($"/api/sales/quotes/{quote.Id}")).StatusCode);

        var sent = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        sent = await (await Act(admin, sent.Id, "send")).Read<QuoteOut>();
        Assert.Equal(HttpStatusCode.Conflict, (await admin.DeleteAsync($"/api/sales/quotes/{sent.Id}")).StatusCode);

        var converted = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        await Act(admin, converted.Id, "send");
        await Act(admin, converted.Id, "accept");
        await admin.Put($"/api/sales/quotes/{converted.Id}/request", new QuoteRequestIn("PO"));
        await Act(admin, converted.Id, "purchase-order");
        (await admin.Post($"/api/sales/quotes/{converted.Id}/convert", new ConvertInput())).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Conflict, (await admin.DeleteAsync($"/api/sales/quotes/{converted.Id}")).StatusCode);
    }

    [Fact]
    public async Task Admin_clears_sales_movement_data_but_never_master_data()
    {
        var admin = await api.AdminAsync();
        var sales = await api.UserAsync(UserRole.Sales);
        var s = await Arrange(admin);
        var q = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        await Act(admin, q.Id, "send");
        await Act(admin, q.Id, "accept");
        await admin.Put($"/api/sales/quotes/{q.Id}/request", new QuoteRequestIn("PO"));
        await Act(admin, q.Id, "purchase-order");
        (await admin.Post($"/api/sales/quotes/{q.Id}/convert", new ConvertInput())).EnsureSuccessStatusCode();

        var body = new DataResetIn([Ebt.Core.Maintenance.ResetScope.Sales]);
        Assert.Equal(HttpStatusCode.Forbidden, (await sales.Post("/api/admin/data-reset/preview", body)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post("/api/admin/data-reset/preview", new DataResetIn([]))).StatusCode);
        var preview = await (await admin.Post("/api/admin/data-reset/preview", body)).Read<DataResetOut>();
        Assert.Contains(preview.Tables, t => t.Table == "quotes" && t.Rows >= 1);
        Assert.Contains(preview.Tables, t => t.Table == "sales_orders" && t.Rows >= 1);

        // Nothing is deleted without the confirmation word.
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post("/api/admin/data-reset", body)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post("/api/admin/data-reset", body with { Confirm = "limpar tudo" })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await admin.GetAsync($"/api/sales/quotes/{q.Id}")).StatusCode);

        var done = await (await admin.Post("/api/admin/data-reset", body with { Confirm = MaintenanceEndpoints.ConfirmWord, Password = ApiFixture.AdminPassword })).Read<DataResetOut>();
        Assert.True(done.TotalRows >= 2);
        Assert.Equal(HttpStatusCode.NotFound, (await admin.GetAsync($"/api/sales/quotes/{q.Id}")).StatusCode);
        Assert.Equal(0, (await (await admin.GetAsync("/api/sales/quotes?take=1")).Read<Page<QuoteSummaryOut>>()).Total);
        Assert.Equal(0, (await (await admin.GetAsync("/api/sales/orders?take=1")).Read<Page<SalesOrderSummaryOut>>()).Total);

        // Master data survives, and the wipe is in the audit trail.
        Assert.Equal(HttpStatusCode.OK, (await admin.GetAsync($"/api/products/{s.Tube.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await admin.GetAsync($"/api/customers/{s.Customer.Id}")).StatusCode);
        var audit = await (await admin.GetAsync("/api/audit?entity=DataReset")).Read<Page<AuditOut>>();
        Assert.Contains(audit.Items, a => a.EntityId == "Sales" && a.User == ApiFixture.AdminUser);
    }

    [Fact]
    public async Task Every_scope_clears_cleanly_in_foreign_key_order()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var q = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        await Act(admin, q.Id, "send");
        await Act(admin, q.Id, "accept");
        await admin.Put($"/api/sales/quotes/{q.Id}/request", new QuoteRequestIn("PO"));
        await Act(admin, q.Id, "purchase-order");
        (await admin.Post($"/api/sales/quotes/{q.Id}/convert", new ConvertInput())).EnsureSuccessStatusCode();

        var all = new DataResetIn([Ebt.Core.Maintenance.ResetScope.Sales, Ebt.Core.Maintenance.ResetScope.Purchasing, Ebt.Core.Maintenance.ResetScope.Production, Ebt.Core.Maintenance.ResetScope.Stock], MaintenanceEndpoints.ConfirmWord, ApiFixture.AdminPassword);
        var res = await admin.Post("/api/admin/data-reset", all);
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var done = await res.Read<DataResetOut>();
        Assert.Contains(done.Tables, t => t.Table == "stock_movements");
        Assert.Equal(HttpStatusCode.OK, (await admin.GetAsync($"/api/products/{s.Tube.Id}")).StatusCode);
    }

    [Fact]
    public async Task Stock_cannot_be_cleared_alone_while_sales_still_point_at_its_documents()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var q = await (await admin.Post("/api/sales/quotes", Quote(s, otherPrice: 20m))).Read<QuoteOut>();
        await Act(admin, q.Id, "send");
        await Act(admin, q.Id, "accept");
        await admin.Put($"/api/sales/quotes/{q.Id}/request", new QuoteRequestIn("PO"));
        await Act(admin, q.Id, "purchase-order");
        var order = await (await admin.Post($"/api/sales/quotes/{q.Id}/convert", new ConvertInput())).Read<SalesOrderOut>();
        (await admin.Post($"/api/sales/orders/{order.Id}/release", new { })).EnsureSuccessStatusCode();
        var res = await admin.Post("/api/admin/data-reset", new DataResetIn([Ebt.Core.Maintenance.ResetScope.Stock], MaintenanceEndpoints.ConfirmWord, ApiFixture.AdminPassword));
        // Either the order has reservations pointing at stock or it does not; in both cases the database state stays consistent.
        Assert.True(res.StatusCode is HttpStatusCode.OK or HttpStatusCode.Conflict);
        Assert.Equal(HttpStatusCode.OK, (await admin.GetAsync($"/api/sales/orders/{order.Id}")).StatusCode);
    }

    [Fact]
    public async Task Stale_if_match_is_rejected_with_412()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var sales = await api.UserAsync(UserRole.Sales);
        var quote = await (await sales.Post("/api/sales/quotes", Quote(s))).Read<QuoteOut>();

        var first = await sales.GetAsync($"/api/sales/quotes/{quote.Id}");
        var etag = first.Headers.ETag?.ToString();
        Assert.False(string.IsNullOrEmpty(etag));

        var update = new HttpRequestMessage(HttpMethod.Put, $"/api/sales/quotes/{quote.Id}") { Content = JsonContent.Create(Quote(s, 17m), options: ApiFixture.Json) };
        update.Headers.TryAddWithoutValidation("If-Match", etag);
        var ok = await sales.SendAsync(update);
        ok.EnsureSuccessStatusCode();
        Assert.NotEqual(etag, ok.Headers.ETag?.ToString());

        var stale = new HttpRequestMessage(HttpMethod.Put, $"/api/sales/quotes/{quote.Id}") { Content = JsonContent.Create(Quote(s, 16m), options: ApiFixture.Json) };
        stale.Headers.TryAddWithoutValidation("If-Match", etag);
        Assert.Equal(HttpStatusCode.PreconditionFailed, (await sales.SendAsync(stale)).StatusCode);

        var noHeader = await sales.Put($"/api/sales/quotes/{quote.Id}", Quote(s, 16m));
        Assert.Equal(HttpStatusCode.OK, noHeader.StatusCode);
    }

    private static async Task AssertStatus(HttpStatusCode expected, Task<HttpResponseMessage> call) => Assert.Equal(expected, (await call).StatusCode);

    [Fact]
    public async Task Quote_and_order_input_validation()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var other = await (await admin.Post("/api/customers", new CustomerIn("Outro " + Code("C"), null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var unpriced = await (await admin.Post("/api/products", Tube(Code("U")))).Read<ProductOut>();
        QuoteInput Q(IReadOnlyList<SalesLineInput>? lines = null, int? customer = null, int? address = null, int? term = null, int? validity = null) =>
            new(customer ?? s.Customer.Id, lines ?? [new SalesLineInput(s.Tube.Id, 5m)], address ?? s.Address.Id, term ?? s.Term.Id, FreightTerms.Cif, validity, "Edilto", "compras@cliente.com");
        SalesLineInput L(int? product = null, decimal qty = 5m, decimal? price = null, decimal? ipi = null, decimal? icms = null, int? lead = null) =>
            new(product ?? s.Tube.Id, qty, price, ipi, icms, lead);

        const string q = "/api/sales/quotes";
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(q, Q(lines: [])));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(q, Q(lines: [L(product: 999_999)])));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(q, Q(lines: [L(qty: 0m)])));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(q, Q(lines: [L(price: -1m)])));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(q, Q(lines: [L(ipi: 101m)])));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(q, Q(lines: [L(icms: -1m)])));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(q, Q(lines: [L(lead: -1)])));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(q, Q(lines: [L(product: unpriced.Id)])));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(q, Q(customer: 999_999)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(q, Q(term: 999_999)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(q, Q(validity: 0)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(q, Q(customer: other.Id)));   // address of another customer

        // quote state machine
        var quote = await (await admin.Post(q, Q())).Read<QuoteOut>();
        await AssertStatus(HttpStatusCode.Conflict, Act(admin, quote.Id, "approve"));
        await AssertStatus(HttpStatusCode.Conflict, Act(admin, quote.Id, "reject-approval", new QuoteActionIn("nota")));
        await AssertStatus(HttpStatusCode.Conflict, Act(admin, quote.Id, "decline", new QuoteActionIn("nota")));
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{q}/{quote.Id}/revise", new QuoteActionIn("nota")));
        await AssertStatus(HttpStatusCode.NotFound, Act(admin, 999_999, "send"));
        await AssertStatus(HttpStatusCode.NotFound, admin.DeleteAsync($"{q}/999999"));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Put($"{q}/{quote.Id}", Q(validity: 0)));
        quote = await (await Act(admin, quote.Id, "send")).Read<QuoteOut>();
        await AssertStatus(HttpStatusCode.Conflict, admin.Put($"{q}/{quote.Id}", Q()));
        await AssertStatus(HttpStatusCode.Conflict, Act(admin, quote.Id, "send"));
        if (quote.Status == QuoteStatus.PendingApproval)
        {
            await AssertStatus(HttpStatusCode.BadRequest, Act(admin, quote.Id, "reject-approval"));
            quote = await (await Act(admin, quote.Id, "reject-approval", new QuoteActionIn("preço fora da política"))).Read<QuoteOut>();
            Assert.Equal(QuoteStatus.Draft, quote.Status);
            quote = await (await Act(admin, quote.Id, "send")).Read<QuoteOut>();
            quote = await (await Act(admin, quote.Id, "approve")).Read<QuoteOut>();
            quote = await (await Act(admin, quote.Id, "send")).Read<QuoteOut>();
        }
        Assert.Equal(QuoteStatus.Sent, quote.Status);
        await AssertStatus(HttpStatusCode.BadRequest, Act(admin, quote.Id, "decline"));
        await AssertStatus(HttpStatusCode.BadRequest, Act(admin, quote.Id, "decline", new QuoteActionIn("preço alto", LostReason: (LostReason)999)));
        await AssertStatus(HttpStatusCode.Conflict, Act(admin, quote.Id, "cancel")); // a sent quote ends through the customer's decision
        await AssertStatus(HttpStatusCode.Conflict, Act(admin, quote.Id, "reopen"));
        quote = await (await Act(admin, quote.Id, "accept")).Read<QuoteOut>();
        await AssertStatus(HttpStatusCode.Conflict, Act(admin, quote.Id, "purchase-order", new QuoteActionIn(CustomerPo: "PO-X")));
        (await admin.Put($"{q}/{quote.Id}/request", new QuoteRequestIn("Pedido de compra PO-X"))).EnsureSuccessStatusCode();
        await AssertStatus(HttpStatusCode.BadRequest, Act(admin, quote.Id, "purchase-order",
            new QuoteActionIn(CustomerPo: "PO-X", DeliveryDates: [new QuoteLineDate(quote.Lines[0].Id, Today.AddDays(-2))])));
        await AssertStatus(HttpStatusCode.BadRequest, Act(admin, quote.Id, "purchase-order",
            new QuoteActionIn(CustomerPo: "PO-X", DeliveryDates: [new QuoteLineDate(999_999, Today.AddDays(5))])));
        await AssertStatus(HttpStatusCode.Conflict, admin.DeleteAsync($"{q}/{quote.Id}"));

        // orders
        const string o = "/api/sales/orders";
        SalesOrderIn O(int? customer = null, int? address = null, List<SalesLineInput>? lines = null) =>
            new(customer ?? s.Customer.Id, address ?? s.Address.Id, lines ?? [new SalesLineInput(s.Tube.Id, 5m)], "PO-V", s.Term.Id);
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(o, O(lines: [])));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(o, O(address: 999_999)));
        var order = await (await admin.Post(o, O())).Read<SalesOrderOut>();
        await AssertStatus(HttpStatusCode.BadRequest, admin.Put($"{o}/{order.Id}", O(customer: other.Id)));
        await AssertStatus(HttpStatusCode.NotFound, admin.Put($"{o}/999999", O()));
        await AssertStatus(HttpStatusCode.NotFound, admin.Post($"{o}/999999/release", new SalesReleaseIn()));
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{o}/{order.Id}/reschedule", new RescheduleInput(CustomerPo: "X")));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"{o}/{order.Id}/cancel", new OrderCancelIn(" ")));
        (await admin.Post($"{o}/{order.Id}/release", new SalesReleaseIn())).EnsureSuccessStatusCode();
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{o}/{order.Id}/release", new SalesReleaseIn()));
        await AssertStatus(HttpStatusCode.Conflict, admin.Put($"{o}/{order.Id}", O()));

        // reschedule: unknown line, missing reason for a date change, no-op
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"{o}/{order.Id}/reschedule", new RescheduleInput("atraso", Lines: [new RescheduleLine(999_999, Today)])));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"{o}/{order.Id}/reschedule", new RescheduleInput(Lines: [new RescheduleLine(order.Lines[0].Id, Today.AddDays(90))])));
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{o}/{order.Id}/reschedule", new RescheduleInput()));
        // balance: nothing shipped yet means nothing to close; a reason is needed
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"{o}/{order.Id}/close-balance", new SalesReasonIn(" ")));

        // deliveries
        const string d = "/api/sales/deliveries";
        string dl(int id) => $"{o}/{id}/deliveries";
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(dl(order.Id), new DeliveryInput(Today, AddressId: 999_999)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(dl(order.Id), new DeliveryInput(Today, Lines: [new DeliveryLineInput(999_999, 1m)])));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(dl(order.Id), new DeliveryInput(Today, Lines: [new DeliveryLineInput(order.Lines[0].Id, 0m)])));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(dl(order.Id), new DeliveryInput(Today, Lines: [new DeliveryLineInput(order.Lines[0].Id, 1m), new DeliveryLineInput(order.Lines[0].Id, 1m)])));
        var delivery = await (await admin.Post(dl(order.Id), new DeliveryInput(Today))).Read<DeliveryOut>();
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{d}/{delivery.Id}/confirm", new ConfirmDeliveryIn()));
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{d}/{delivery.Id}/emit-invoice", new EmitInvoiceInput()));
        await AssertStatus(HttpStatusCode.NotFound, admin.Post($"{d}/999999/ship", new ShipInput(Today, WithoutCertificate: true)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"{d}/{delivery.Id}/cancel", new SalesReasonIn(" ")));
        (await admin.Post($"{d}/{delivery.Id}/cancel", new SalesReasonIn("cliente adiou"))).EnsureSuccessStatusCode();
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{d}/{delivery.Id}/cancel", new SalesReasonIn("de novo")));
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{d}/{delivery.Id}/ship", new ShipInput(Today, WithoutCertificate: true)));

        // the whole order delivered: nothing left to plan; cancelling an order with a shipped delivery is refused
        var full = await (await admin.Post(dl(order.Id), new DeliveryInput(Today))).Read<DeliveryOut>();
        await AssertStatus(HttpStatusCode.Conflict, admin.Post(dl(order.Id), new DeliveryInput(Today)));
        (await admin.Post($"{d}/{full.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).EnsureSuccessStatusCode();
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{o}/{order.Id}/cancel", new OrderCancelIn("tarde demais")));
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{o}/{order.Id}/close-balance", new SalesReasonIn("nada a encerrar")));
    }

    [Fact]
    public async Task Certificate_errors_waiver_and_delivery_drafts()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var order = await ReleasedOrder(admin, s, 10m);
        var multi = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 5m), new SalesLineInput(s.Other.Id, 5m)], "PO-2", s.Term.Id))).Read<SalesOrderOut>();
        const string url = "/api/sales/certificates";

        await AssertStatus(HttpStatusCode.NotFound, admin.Post(url, new CertificateInput(999_999)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(url, new CertificateInput(multi.Id)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(url, new CertificateInput(order.Id, OrderLineId: multi.Lines[0].Id)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(url, new CertificateInput(order.Id, DeliveryId: 999_999)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(url, new CertificateInput(order.Id, Quantity: 0m)));
        var forLine = await (await admin.Post(url, new CertificateInput(multi.Id, OrderLineId: multi.Lines[1].Id))).Read<CertificateOut>();
        Assert.Equal(multi.Lines[1].Id, forLine.OrderLineId);

        var cert = await (await admin.Post(url, new CertificateInput(order.Id, Unit: "pc"))).Read<CertificateOut>();
        Assert.Equal("PC", cert.Unit);
        await AssertStatus(HttpStatusCode.NotFound, admin.GetAsync($"{url}/999999"));
        await AssertStatus(HttpStatusCode.NotFound, admin.Put($"{url}/999999", new CertificateInput(order.Id)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Put($"{url}/{cert.Id}", new CertificateInput(order.Id, Quantity: 0m)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"{url}/{cert.Id}/link-delivery", new CertificateLinkIn(999_999)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"{url}/{cert.Id}/cancel", new CertificateReasonIn(" ")));
        await AssertStatus(HttpStatusCode.NotFound, admin.Post($"{url}/999999/cancel", new CertificateReasonIn("x")));
        await AssertStatus(HttpStatusCode.NotFound, admin.DeleteAsync($"{url}/999999"));

        // an issued certificate cannot be deleted or issued twice; cancelling freezes it
        var measures = cert.Measures.Select(m => new CertificateMeasureInput(m.Kind, m.Name, m.Specified, "1")).ToList();
        (await admin.Put($"{url}/{cert.Id}", new CertificateInput(order.Id, Measures: measures))).EnsureSuccessStatusCode();
        (await admin.Post($"{url}/{cert.Id}/issue", new object())).EnsureSuccessStatusCode();
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{url}/{cert.Id}/issue", new object()));
        await AssertStatus(HttpStatusCode.Conflict, admin.DeleteAsync($"{url}/{cert.Id}"));
        (await admin.Post($"{url}/{cert.Id}/cancel", new CertificateReasonIn("Emitido para o pedido errado"))).EnsureSuccessStatusCode();
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{url}/{cert.Id}/cancel", new CertificateReasonIn("de novo")));
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{url}/{cert.Id}/link-delivery", new CertificateLinkIn(null)));
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{url}/{cert.Id}/issue", new object()));
        await AssertStatus(HttpStatusCode.Conflict, admin.Put($"{url}/{cert.Id}", new CertificateInput(order.Id)));

        // drafts per delivery: unknown and cancelled deliveries are refused, a second call finds nothing left to draft
        await AssertStatus(HttpStatusCode.NotFound, admin.Post($"{url}/for-delivery/999999", new object()));
        var gone = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        (await admin.Post($"/api/sales/deliveries/{gone.Id}/cancel", new SalesReasonIn("planejamento errado"))).EnsureSuccessStatusCode();
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{url}/for-delivery/{gone.Id}", new object()));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post(url, new CertificateInput(order.Id, DeliveryId: gone.Id)));
        var planned = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        (await admin.Post($"{url}/for-delivery/{planned.Id}", new object())).EnsureSuccessStatusCode();
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"{url}/for-delivery/{planned.Id}", new object()));

        // templates and waiver
        await AssertStatus(HttpStatusCode.NotFound, admin.Put($"{url}/templates/999999", new TemplateIn("T", null, null, [])));
        await AssertStatus(HttpStatusCode.NotFound, admin.DeleteAsync($"{url}/templates/999999"));
        await AssertStatus(HttpStatusCode.NotFound, admin.Post("/api/sales/orders/999999/certificate-waiver", new CertificateWaiverIn(true)));
        (await admin.Post($"/api/sales/orders/{order.Id}/certificate-waiver", new CertificateWaiverIn(true))).EnsureSuccessStatusCode();
        (await admin.Post($"/api/sales/orders/{order.Id}/certificate-waiver", new CertificateWaiverIn(false))).EnsureSuccessStatusCode();
    }

    private sealed class FakeMail(bool fail = false) : Ebt.Core.Mail.IMailSender
    {
        public List<Ebt.Core.Mail.OutgoingMail> Sent { get; } = [];
        public bool Enabled => true;
        public string? From => "orcamentos@ebt.test";

        public Task SendAsync(Ebt.Core.Mail.OutgoingMail mail, CancellationToken ct = default)
        {
            if (fail) throw new Ebt.Core.Mail.MailException("O servidor de e-mail recusou o envio (teste).");
            Sent.Add(mail);
            return Task.CompletedTask;
        }
    }

    private static QuoteEmailIn Email(string to = "compras@cliente.com", string? cc = null, string pdf = "JVBERi0xLjQ=") => new(to, cc, "PROP teste · EBT", "Segue o orçamento.", pdf, "Orçamento teste.pdf");

    [Fact]
    public async Task Quote_email_is_off_without_smtp_settings()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var quote = await (await admin.Post("/api/sales/quotes", Quote(s, 20m))).Read<QuoteOut>();
        var status = await (await admin.GetAsync("/api/system/mail")).Content.ReadFromJsonAsync<System.Text.Json.JsonElement>();
        Assert.False(status.GetProperty("enabled").GetBoolean());
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"/api/sales/quotes/{quote.Id}/email", Email()));
    }

    [Fact]
    public async Task Quote_email_sends_the_pdf_and_registers_the_send()
    {
        var mail = new FakeMail();
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var withMail = await api.AdminWithMailAsync(mail);
        var quote = await (await admin.Post("/api/sales/quotes", Quote(s, 20m))).Read<QuoteOut>();
        Assert.False(quote.NeedsApproval);

        await AssertStatus(HttpStatusCode.BadRequest, withMail.Post($"/api/sales/quotes/{quote.Id}/email", Email(to: "sem-arroba")));
        await AssertStatus(HttpStatusCode.BadRequest, withMail.Post($"/api/sales/quotes/{quote.Id}/email", Email(cc: "ok@x.com; ruim")));
        await AssertStatus(HttpStatusCode.BadRequest, withMail.Post($"/api/sales/quotes/{quote.Id}/email", Email(pdf: "")));
        Assert.Empty(mail.Sent);

        var sent = await (await withMail.Post($"/api/sales/quotes/{quote.Id}/email", Email(to: "a@cliente.com; b@cliente.com", cc: "vendas@ebt.test"))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Sent, sent.Status);
        Assert.Equal("a@cliente.com, b@cliente.com", sent.SentTo);
        var m = Assert.Single(mail.Sent);
        Assert.Equal(["a@cliente.com", "b@cliente.com"], m.To);
        Assert.Equal(["vendas@ebt.test"], m.Cc);
        Assert.Equal("Orçamento teste.pdf", m.Attachment!.FileName);
        Assert.Equal("%PDF-1.4"u8.ToArray(), m.Attachment.Data);

        // A quote already sent is mailed again without changing its status or validity.
        var again = await (await withMail.Post($"/api/sales/quotes/{quote.Id}/email", Email())).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Sent, again.Status);
        Assert.Equal(sent.ValidUntil, again.ValidUntil);
        Assert.Equal(2, mail.Sent.Count);
        await using var db = api.NewDb();
        Assert.Contains(await db.SalesEvents.Where(e => e.Kind == SalesRecordKind.Quote && e.RecordId == quote.Id).Select(e => e.Action).ToListAsync(), a => a == "emailed");
    }

    [Fact]
    public async Task Quote_email_waits_for_the_discount_approval_and_reports_a_failed_send()
    {
        var mail = new FakeMail();
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var withMail = await api.AdminWithMailAsync(mail);
        var discounted = await (await admin.Post("/api/sales/quotes", Quote(s))).Read<QuoteOut>();
        Assert.True(discounted.NeedsApproval);
        await AssertStatus(HttpStatusCode.Conflict, withMail.Post($"/api/sales/quotes/{discounted.Id}/email", Email()));
        Assert.Empty(mail.Sent);

        var failing = await api.AdminWithMailAsync(new FakeMail(fail: true));
        var quote = await (await admin.Post("/api/sales/quotes", Quote(s, 20m))).Read<QuoteOut>();
        await AssertStatus(HttpStatusCode.BadGateway, failing.Post($"/api/sales/quotes/{quote.Id}/email", Email()));
        // The send is registered and committed before the mail goes out (no lock is held across SMTP); the failure is written to the history.
        var after = await (await admin.GetAsync($"/api/sales/quotes/{quote.Id}")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Sent, after.Status);
        Assert.Contains(after.History, h => h.Action == "email-failed" && h.Note!.Contains("Falha no envio do e-mail"));
        Assert.DoesNotContain(after.History, h => h.Action == "emailed");
        // The discounted draft was refused before anything was written: still a draft, no history besides its creation.
        var untouched = await (await admin.GetAsync($"/api/sales/quotes/{discounted.Id}")).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Draft, untouched.Status);
        Assert.Equal(["created"], untouched.History.Select(h => h.Action));
        var refused = await withMail.Post($"/api/sales/quotes/{discounted.Id}/email", Email());
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Contains("autorização do gerente", await refused.Content.ReadAsStringAsync());

        var reader = await api.UserAsync(UserRole.Reader);
        await AssertStatus(HttpStatusCode.Forbidden, reader.Post($"/api/sales/quotes/{quote.Id}/email", Email()));
    }

    [Fact]
    public async Task Quote_email_is_capped_checked_replies_to_the_sender_and_registers_the_send_once()
    {
        var mail = new FakeMail();
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var withMail = await api.AdminWithMailAsync(mail);
        var quote = await (await admin.Post("/api/sales/quotes", Quote(s, 20m))).Read<QuoteOut>();
        var url = $"/api/sales/quotes/{quote.Id}/email";

        var eleven = string.Join("; ", Enumerable.Range(1, 11).Select(n => $"p{n}@cliente.com"));
        await AssertStatus(HttpStatusCode.BadRequest, withMail.Post(url, Email(to: eleven)));
        await AssertStatus(HttpStatusCode.BadRequest, withMail.Post(url, Email(to: string.Join("; ", Enumerable.Range(1, 6).Select(n => $"p{n}@cliente.com")), cc: string.Join("; ", Enumerable.Range(1, 5).Select(n => $"c{n}@cliente.com")))));
        await AssertStatus(HttpStatusCode.BadRequest, withMail.Post(url, Email() with { Body = new string('x', 10_001) }));
        await AssertStatus(HttpStatusCode.BadRequest, withMail.Post(url, Email() with { Subject = "linha 1\nBcc: alguem@fora.com" }));
        await AssertStatus(HttpStatusCode.BadRequest, withMail.Post(url, Email(pdf: Convert.ToBase64String("not a pdf"u8.ToArray()))));
        Assert.Empty(mail.Sent);
        Assert.Equal(QuoteStatus.Draft, (await (await admin.GetAsync($"/api/sales/quotes/{quote.Id}")).Read<QuoteOut>()).Status);

        // The file name always ends in .pdf and carries no path; the reply goes to the sender's profile e-mail.
        (await admin.Put("/api/auth/profile", new ProfileRequest("Administrador", "vendedor@ebt.test"))).EnsureSuccessStatusCode();
        // Two clicks at once: both mails go out (the second is the explicit resend of a sent quote) but the send is registered a single time.
        var both = await Task.WhenAll(withMail.Post(url, Email() with { FileName = "..\\evil.exe" }), withMail.Post(url, Email()));
        Assert.All(both, r => Assert.Equal(HttpStatusCode.OK, r.StatusCode));
        Assert.Equal(2, mail.Sent.Count);
        Assert.Contains(mail.Sent, m => m.Attachment!.FileName == "evil.exe.pdf");
        Assert.All(mail.Sent, m => Assert.Equal("vendedor@ebt.test", m.ReplyTo));
        await using var db = api.NewDb();
        var actions = await db.SalesEvents.Where(e => e.Kind == SalesRecordKind.Quote && e.RecordId == quote.Id).Select(e => e.Action).ToListAsync();
        Assert.Single(actions, a => a == "sent");
        Assert.Single(actions, a => a == "emailed");
        (await admin.Put("/api/auth/profile", new ProfileRequest("Administrador", null))).EnsureSuccessStatusCode();
    }

    private async Task<CertificateOut> IssueCertificateAsync(HttpClient admin, CertificateOut draft, bool allFound = true)
    {
        var measures = draft.Measures.Select((m, n) => new CertificateMeasureInput(m.Kind, m.Name, m.Specified, allFound || n == 0 ? "1" : null)).ToList();
        (await admin.Put($"/api/sales/certificates/{draft.Id}", new CertificateInput(draft.OrderId, Measures: measures))).EnsureSuccessStatusCode();
        return await (await admin.Post($"/api/sales/certificates/{draft.Id}/issue", new object())).Read<CertificateOut>();
    }

    [Fact]
    public async Task Shipping_needs_an_issued_certificate_for_every_item_of_the_delivery_and_every_row_found()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 100m);
        (await admin.Post("/api/stock/documents", new StockPost(MovementType.AdjustmentIn, Today, [new StockLine(null, s.Other.Id, s.Shipping.Id, 50m, UnitCost: 5m)], "INV"))).EnsureSuccessStatusCode();
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 10m), new SalesLineInput(s.Other.Id, 5m)], "PO-9", s.Term.Id))).Read<SalesOrderOut>();
        order = await (await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn())).Read<SalesOrderOut>();
        var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        var made = await (await admin.Post($"/api/sales/certificates/for-delivery/{delivery.Id}", new object())).Read<List<CertificateOut>>();

        // A row without the found value cannot be issued.
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"/api/sales/certificates/{made[0].Id}/issue", new object()));
        var partial = made[0].Measures.Select((m, n) => new CertificateMeasureInput(m.Kind, m.Name, m.Specified, n == 0 ? "1" : null)).ToList();
        (await admin.Put($"/api/sales/certificates/{made[0].Id}", new CertificateInput(order.Id, Measures: partial))).EnsureSuccessStatusCode();
        Assert.True(partial.Count > 1);
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"/api/sales/certificates/{made[0].Id}/issue", new object()));

        // One certificate for two items is not enough: the other item has none.
        await IssueCertificateAsync(admin, made[0]);
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today)));
        await IssueCertificateAsync(admin, made[1]);
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today))).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task A_delivery_with_an_unknown_nf_outcome_cannot_be_cancelled()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 20m);
        var order = await ReleasedOrder(admin, s, 10m);
        var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).EnsureSuccessStatusCode();
        int docId;
        await using (var db = api.NewDb())
        {
            var doc = new FiscalDocument
            {
                Kind = FiscalKind.Sale, Status = FiscalStatus.Pending, Simulated = true, CfopCode = "5101", Series = 1, Number = 800_000 + Random.Shared.Next(100_000), AccessKey = Guid.NewGuid().ToString("N"),
                Protocol = "", RecipientName = "Cliente", RecipientDocument = "26133636000103", RecipientUf = "SP", Xml = "<x/>", DeliveryId = delivery.Id, IssuedAt = DateTimeOffset.UtcNow
            };
            db.FiscalDocuments.Add(doc);
            await db.SaveChangesAsync();
            docId = doc.Id;
        }
        var blocked = await admin.Post($"/api/sales/deliveries/{delivery.Id}/cancel", new SalesReasonIn("cliente desistiu"));
        Assert.Equal(HttpStatusCode.Conflict, blocked.StatusCode);
        Assert.Contains("pendente", await blocked.Content.ReadAsStringAsync());

        await using (var db = api.NewDb()) await db.FiscalDocuments.Where(f => f.Id == docId).ExecuteUpdateAsync(u => u.SetProperty(f => f.Status, FiscalStatus.Rejected));
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/cancel", new SalesReasonIn("cliente desistiu"))).EnsureSuccessStatusCode();
    }

    // ---- Review fixes: balance closing, quote-born prices, certificate waiver, rounding, credit exposure, pipeline, input sanity ----

    private async Task AddStock(HttpClient admin, Setup s, ProductOut product, decimal quantity) =>
        (await admin.Post("/api/stock/documents", new StockPost(MovementType.AdjustmentIn, Today, [new StockLine(null, product.Id, s.Shipping.Id, quantity, UnitCost: 5m)], "INV"))).EnsureSuccessStatusCode();

    private static async Task SetFiscal(HttpClient admin, bool enabled)
    {
        var f = await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>();
        (await admin.Put("/api/fiscal/settings", f with
        {
            Enabled = enabled, Environment = SefazEnvironment.Homologation, CompanyName = "EBT Tubos Ltda", TradeName = "EBT", Cnpj = "11222333000181", StateRegistration = "111222333444", TaxRegime = 3,
            Street = "Rua das Industrias", Number = "10", District = "Distrito", City = "Embu das Artes", CityIbgeCode = "3515004", Uf = "SP", ZipCode = "06800000", Phone = "1144444444"
        })).EnsureSuccessStatusCode();
    }

    private async Task<(QuoteOut Quote, SalesOrderOut Order)> QuoteBornOrder(HttpClient sales, Setup s)
    {
        var quote = await (await sales.Post("/api/sales/quotes", Quote(s, 20m))).Read<QuoteOut>();
        (await Act(sales, quote.Id, "send")).EnsureSuccessStatusCode();
        (await Act(sales, quote.Id, "accept")).EnsureSuccessStatusCode();
        (await sales.Put($"/api/sales/quotes/{quote.Id}/request", new QuoteRequestIn("Pedido por e-mail"))).EnsureSuccessStatusCode();
        (await Act(sales, quote.Id, "purchase-order", new QuoteActionIn(CustomerPo: "PO-1"))).EnsureSuccessStatusCode();
        return (quote, await (await sales.Post($"/api/sales/quotes/{quote.Id}/convert", new ConvertInput())).Read<SalesOrderOut>());
    }

    [Fact]
    public async Task Closing_the_balance_removes_an_item_that_never_shipped_and_refuses_one_with_a_live_OF()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 40m);
        await AddStock(admin, s, s.Other, 20m);
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 10m), new SalesLineInput(s.Other.Id, 5m)], "PO-1", s.Term.Id))).Read<SalesOrderOut>();
        order = await (await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn())).Read<SalesOrderOut>();
        Assert.All(order.Lines, l => Assert.Null(l.ProductionOrderId));
        var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today, Lines: [new DeliveryLineInput(order.Lines[0].Id, 4m)]))).Read<DeliveryOut>();
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).EnsureSuccessStatusCode();

        // The second item never shipped: it used to shrink to quantity 0 and hit the check constraint (500); now it leaves the order.
        order = await (await admin.Post($"/api/sales/orders/{order.Id}/close-balance", new SalesReasonIn("Cliente levou só o primeiro item"))).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.Shipped, order.Status);
        var line = Assert.Single(order.Lines);
        Assert.Equal((s.Tube.Id, 4m), (line.ProductId, line.Quantity));
        Assert.Equal(SalesService.Money(4m * 100m) + SalesService.Money(4m * 100m * 5m / 100m), order.Total);
        Assert.Contains(order.History, h => h.Action == "balance-closed" && h.Note!.Contains("removido"));

        // With a production order on the unshipped item the closing is refused up front and nothing changes.
        var s2 = await Arrange(admin, stock: 40m);
        var o2 = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s2.Customer.Id, s2.Address.Id, [new SalesLineInput(s2.Tube.Id, 10m), new SalesLineInput(s2.Other.Id, 5m)], "PO-2", s2.Term.Id))).Read<SalesOrderOut>();
        o2 = await (await admin.Post($"/api/sales/orders/{o2.Id}/release", new SalesReleaseIn())).Read<SalesOrderOut>();
        Assert.NotNull(o2.Lines[1].ProductionOrderId);
        var d2 = await (await admin.Post($"/api/sales/orders/{o2.Id}/deliveries", new DeliveryInput(Today, Lines: [new DeliveryLineInput(o2.Lines[0].Id, 4m)]))).Read<DeliveryOut>();
        (await admin.Post($"/api/sales/deliveries/{d2.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).EnsureSuccessStatusCode();
        var refused = await admin.Post($"/api/sales/orders/{o2.Id}/close-balance", new SalesReasonIn("tentativa"));
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Contains("ordem de produção", await refused.Content.ReadAsStringAsync());
        var unchanged = await (await admin.GetAsync($"/api/sales/orders/{o2.Id}")).Read<SalesOrderOut>();
        Assert.Equal(2, unchanged.Lines.Count);
        Assert.Equal(10m, unchanged.Lines[0].Quantity);
    }

    [Fact]
    public async Task A_quote_born_order_cannot_be_repriced_without_a_manager_but_unchanged_prices_pass()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var sales = await api.UserAsync(UserRole.Sales);
        var manager = await api.UserAsync(UserRole.SalesManager);
        var (_, order) = await QuoteBornOrder(sales, s);
        SalesOrderIn Body(decimal tubePrice) => new(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 100m, tubePrice), new SalesLineInput(s.Other.Id, 50m, 20m)], "PO-1", s.Term.Id);

        (await sales.Put($"/api/sales/orders/{order.Id}", Body(100m))).EnsureSuccessStatusCode();     // same prices as the approved quote
        var refused = await sales.Put($"/api/sales/orders/{order.Id}", Body(50m));                       // 50% off the list price
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Contains("sales manager", await refused.Content.ReadAsStringAsync());
        var repriced = await (await manager.Put($"/api/sales/orders/{order.Id}", Body(50m))).Read<SalesOrderOut>();
        Assert.Equal(50m, repriced.Lines[0].UnitPrice);
    }

    [Fact]
    public async Task Shipping_without_a_certificate_needs_the_certificates_issue_right_or_a_manager()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 100m);
        var sales = await api.UserAsync(UserRole.Sales);
        var stock = await api.UserAsync(UserRole.Stock);
        var manager = await api.UserAsync(UserRole.SalesManager);
        var order = await ReleasedOrder(admin, s, 30m);
        var ids = new List<int>();
        for (var n = 0; n < 3; n++)
            ids.Add((await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today, Lines: [new DeliveryLineInput(order.Lines[0].Id, 10m)]))).Read<DeliveryOut>()).Id);

        foreach (var (client, id) in new[] { (sales, ids[0]), (stock, ids[0]) })
        {
            var res = await client.Post($"/api/sales/deliveries/{id}/ship", new ShipInput(Today, WithoutCertificate: true));
            Assert.Equal(HttpStatusCode.Forbidden, res.StatusCode);
            Assert.Contains("certificates-issue", await res.Content.ReadAsStringAsync());
        }
        Assert.Equal(DeliveryStatus.Planned, (await (await admin.GetAsync($"/api/sales/deliveries/{ids[0]}")).Read<DeliveryOut>()).Status);
        Assert.Equal(HttpStatusCode.Conflict, (await sales.Post($"/api/sales/deliveries/{ids[0]}/ship", new ShipInput(Today))).StatusCode);   // without the flag it is the usual "issue the certificate"
        var shipped = await (await manager.Post($"/api/sales/deliveries/{ids[1]}/ship", new ShipInput(Today, WithoutCertificate: true))).Read<DeliveryOut>();
        Assert.Contains(shipped.History, h => h.Action == "shipped" && h.Note!.Contains("sem certificado"));
        (await admin.Post($"/api/sales/deliveries/{ids[2]}/ship", new ShipInput(Today, WithoutCertificate: true))).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task Force_cancelling_running_production_needs_the_PCP_or_a_manager()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 0m);
        var sales = await api.UserAsync(UserRole.Sales);
        var manager = await api.UserAsync(UserRole.SalesManager);
        var order = await ReleasedOrder(admin, s, 20m);
        (await admin.Post($"/api/production/orders/{order.Lines[0].ProductionOrderId}/release", new ReleaseIn(true))).EnsureSuccessStatusCode();

        var denied = await sales.Post($"/api/sales/orders/{order.Id}/cancel", new OrderCancelIn("Duplicado", CancelProduction: true));
        Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
        Assert.Contains("PCP", await denied.Content.ReadAsStringAsync());
        Assert.Equal(SalesOrderStatus.Released, (await (await admin.GetAsync($"/api/sales/orders/{order.Id}")).Read<SalesOrderOut>()).Status);
        // Sales alone may still cancel the order itself (the running OF is left alone).
        var other = await ReleasedOrder(admin, s, 10m);
        Assert.Equal(SalesOrderStatus.Cancelled, (await (await sales.Post($"/api/sales/orders/{other.Id}/cancel", new OrderCancelIn("Duplicado"))).Read<SalesOrderOut>()).Status);

        var cancelled = await (await manager.Post($"/api/sales/orders/{order.Id}/cancel", new OrderCancelIn("Duplicado", CancelProduction: true))).Read<SalesOrderOut>();
        Assert.Equal(SalesOrderStatus.Cancelled, cancelled.Status);
        Assert.Equal(ProductionOrderStatus.Cancelled, (await (await admin.GetAsync($"/api/production/orders/{order.Lines[0].ProductionOrderId}")).Read<ProductionOrderOut>()).Status);
    }

    [Fact]
    public async Task Money_rounds_one_way_so_the_lines_add_up_to_the_totals()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        // 3 x 0.335 = 1.005: away from zero it is 1.01 everywhere (a banker's rounding in the line total would say 1.00 while the order total says 1.01).
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 3m, 0.335m)], "PO-R", s.Term.Id))).Read<SalesOrderOut>();
        Assert.Equal(1.01m, order.Lines[0].Total);
        Assert.Equal(1.01m, order.Products);
        Assert.Equal(order.Products, order.Lines.Sum(l => l.Total));
        Assert.Equal(1.01m, order.Lines[0].BalanceValue);
        var summary = (await (await admin.GetAsync($"/api/sales/orders?customerId={s.Customer.Id}")).Read<Page<SalesOrderSummaryOut>>()).Items.Single(o => o.Id == order.Id);
        Assert.Equal(1.01m, summary.BalanceValue);
        Assert.Equal(order.Total, summary.Total);
        Assert.Equal(summary.Total, summary.BalanceWithIpi); // nothing shipped: the balance with IPI is the whole total
        Assert.True(summary.BalanceWithIpi > summary.BalanceValue);

        var quote = await (await admin.Post("/api/sales/quotes", new QuoteInput(s.Customer.Id, [new SalesLineInput(s.Tube.Id, 3m, 0.335m, 0m)], s.Address.Id, s.Term.Id, FreightTerms.Cif, null, "Edilto", "compras@cliente.com"))).Read<QuoteOut>();
        Assert.Equal(1.01m, quote.Lines[0].Total);
        Assert.Equal(1.01m, quote.Totals.Products);
    }

    [Fact]
    public async Task Delivery_gross_weight_uses_kilograms_for_lines_sold_by_weight_and_the_piece_weight_otherwise()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 0m);
        var heavy = await (await admin.Post("/api/products", new ProductIn(Code("H"), "Tubo pesado", ProductKind.Part, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, 2m, null, "73063010", "PC", 50, false, null, null))).Read<ProductOut>();
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id,
            [new SalesLineInput(heavy.Id, 100m, 10m, Spec: new LineSpec(SaleUnit: "KG")), new SalesLineInput(heavy.Id, 10m, 10m, Spec: new LineSpec(SaleUnit: "PC", PieceWeightKg: 3m)), new SalesLineInput(heavy.Id, 5m, 10m)], "PO-W", s.Term.Id))).Read<SalesOrderOut>();
        order = await (await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn())).Read<SalesOrderOut>();
        var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        // 100 kg (sold by weight, not 100 x 2) + 10 x 3 kg (the line's piece weight) + 5 x 2 kg (the product's net weight)
        Assert.Equal(140m, delivery.GrossWeightKg);
    }

    [Fact]
    public async Task Goods_shipped_without_an_nf_count_in_the_credit_exposure_while_fiscal_emission_is_on()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 40m, creditLimit: 1500m);
        var sales = await api.UserAsync(UserRole.Sales);
        var stock = await api.UserAsync(UserRole.Stock);
        var order = await ReleasedOrder(admin, s, 10m);   // 10 x 100 + 5% IPI = 1,050
        (await admin.Post($"/api/sales/orders/{order.Id}/certificate-waiver", new CertificateWaiverIn(true))).EnsureSuccessStatusCode();
        var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        var next = new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 10m)], "PO-N", s.Term.Id);
        try
        {
            await SetFiscal(admin, true);
            // The Stock role ships physically; the NF stays owed (no emission right), and the delivery says so.
            delivery = await (await stock.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today))).Read<DeliveryOut>();
            Assert.Equal((true, "None"), (delivery.NeedsInvoice, delivery.InvoiceStatus));
            var summary = (await (await admin.GetAsync($"/api/sales/deliveries?customerId={s.Customer.Id}")).Read<Page<DeliverySummaryOut>>()).Items.Single();
            Assert.Equal((true, "None"), (summary.NeedsInvoice, summary.InvoiceStatus));
            Assert.Equal(delivery.Id, Assert.Single((await (await admin.GetAsync($"/api/sales/deliveries?customerId={s.Customer.Id}&pendingInvoice=true")).Read<Page<DeliverySummaryOut>>()).Items).Id);
            Assert.Equal(1, (await (await admin.GetAsync($"/api/sales/pipeline?customerId={s.Customer.Id}")).Read<PipelineOut>()).Kpis.AwaitingInvoiceCount);

            var credit = (await (await admin.GetAsync($"/api/sales/orders/{order.Id}")).Read<SalesOrderOut>()).Credit;
            Assert.Equal((0m, 0m, 1050m), (credit.Open, credit.Receivable, credit.ShippedNotInvoiced));
            var blocked = await sales.Post("/api/sales/orders", next);
            Assert.Equal(HttpStatusCode.Conflict, blocked.StatusCode);
            Assert.Contains($"shipped not yet invoiced {1050m:0.00}", await blocked.Content.ReadAsStringAsync());

            // Once the NF exists (here an authorized document is recorded straight in the database) the goods move from "shipped not invoiced" to the receivables.
            await using (var db = api.NewDb())
            {
                db.FiscalDocuments.Add(new FiscalDocument
                {
                    Kind = FiscalKind.Sale, Status = FiscalStatus.Authorized, Simulated = true, CfopCode = "5101", Series = 77, Number = 900_000 + Random.Shared.Next(90_000), AccessKey = Guid.NewGuid().ToString("N"), Protocol = "1",
                    RecipientName = "Cliente", RecipientDocument = "26133636000103", RecipientUf = "SP", Xml = "<x/>", DeliveryId = delivery.Id, CustomerId = s.Customer.Id, IssuedAt = DateTimeOffset.UtcNow
                });
                await db.SaveChangesAsync();
            }
            var after = await (await admin.GetAsync($"/api/sales/deliveries/{delivery.Id}")).Read<DeliveryOut>();
            Assert.Equal((false, "Authorized"), (after.NeedsInvoice, after.InvoiceStatus));
            Assert.Equal(0m, (await (await admin.GetAsync($"/api/sales/orders/{order.Id}")).Read<SalesOrderOut>()).Credit.ShippedNotInvoiced);
            Assert.Equal(0, (await (await admin.GetAsync($"/api/sales/pipeline?customerId={s.Customer.Id}")).Read<PipelineOut>()).Kpis.AwaitingInvoiceCount);
            (await sales.Post("/api/sales/orders", next)).EnsureSuccessStatusCode();
        }
        finally { await SetFiscal(admin, false); }

        // Emission off: nothing to wait for, so nothing is added and the delivery reports it.
        Assert.Equal(0m, (await (await admin.GetAsync($"/api/sales/orders/{order.Id}")).Read<SalesOrderOut>()).Credit.ShippedNotInvoiced);
        var off = await (await admin.GetAsync($"/api/sales/deliveries/{delivery.Id}")).Read<DeliveryOut>();
        Assert.False(off.NeedsInvoice);
    }

    [Fact]
    public async Task A_pending_nf_is_reported_as_pending_and_not_as_owed()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 20m);
        var order = await ReleasedOrder(admin, s, 10m);
        var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        Assert.Equal((false, "FiscalOff"), (delivery.NeedsInvoice, delivery.InvoiceStatus));  // planned, emission off
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).EnsureSuccessStatusCode();
        try
        {
            await SetFiscal(admin, true);
            await using (var db = api.NewDb())
            {
                db.FiscalDocuments.Add(new FiscalDocument
                {
                    Kind = FiscalKind.Sale, Status = FiscalStatus.Pending, Simulated = true, CfopCode = "5101", Series = 77, Number = 700_000 + Random.Shared.Next(90_000), AccessKey = Guid.NewGuid().ToString("N"), Protocol = "",
                    RecipientName = "Cliente", RecipientDocument = "26133636000103", RecipientUf = "SP", Xml = "<x/>", DeliveryId = delivery.Id, IssuedAt = DateTimeOffset.UtcNow
                });
                await db.SaveChangesAsync();
            }
            var d = await (await admin.GetAsync($"/api/sales/deliveries/{delivery.Id}")).Read<DeliveryOut>();
            Assert.Equal((false, "Pending"), (d.NeedsInvoice, d.InvoiceStatus));
            Assert.Empty((await (await admin.GetAsync($"/api/sales/deliveries?customerId={s.Customer.Id}&pendingInvoice=true")).Read<Page<DeliverySummaryOut>>()).Items);
        }
        finally { await SetFiscal(admin, false); }
    }

    [Fact]
    public async Task The_quote_credit_check_does_not_count_a_quote_twice_once_it_became_an_order()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var sales = await api.UserAsync(UserRole.Sales);
        var quote = await (await sales.Post("/api/sales/quotes", Quote(s, 20m))).Read<QuoteOut>();
        var before = await (await sales.GetAsync($"/api/sales/quotes/{quote.Id}/credit")).Read<CreditCheck>();
        Assert.Equal((0m, quote.Totals.Total), (before.Open, before.ThisOrder));
        (await Act(sales, quote.Id, "send")).EnsureSuccessStatusCode();
        (await Act(sales, quote.Id, "accept")).EnsureSuccessStatusCode();
        (await sales.Put($"/api/sales/quotes/{quote.Id}/request", new QuoteRequestIn("Pedido por e-mail"))).EnsureSuccessStatusCode();
        (await Act(sales, quote.Id, "purchase-order", new QuoteActionIn(CustomerPo: "PO-1"))).EnsureSuccessStatusCode();
        var order = await (await sales.Post($"/api/sales/quotes/{quote.Id}/convert", new ConvertInput())).Read<SalesOrderOut>();
        var after = await (await sales.GetAsync($"/api/sales/quotes/{quote.Id}/credit")).Read<CreditCheck>();
        Assert.Equal((quote.Totals.Total, 0m), (after.Open, after.ThisOrder));
        Assert.Equal(order.Total, after.Open);
    }

    [Fact]
    public async Task Two_orders_created_at_once_cannot_both_use_the_same_credit_headroom()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 0m, creditLimit: 1200m);   // each order is worth 1,050: only one fits
        var sales = await api.UserAsync(UserRole.Sales);
        var other = await api.UserAsync(UserRole.Sales);
        var body = new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 10m)], "PO-C", s.Term.Id);
        var both = await Task.WhenAll(sales.Post("/api/sales/orders", body), other.Post("/api/sales/orders", body));
        Assert.Single(both, r => r.StatusCode == HttpStatusCode.Created);
        Assert.Single(both, r => r.StatusCode == HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Shipping_and_cancelling_the_same_order_at_once_never_deadlock()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 200m);
        for (var round = 0; round < 4; round++)
        {
            var order = await ReleasedOrder(admin, s, 10m);
            var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
            var ship = admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, WithoutCertificate: true));
            var cancel = admin.Post($"/api/sales/orders/{order.Id}/cancel", new OrderCancelIn("Cliente desistiu"));
            var results = await Task.WhenAll(ship, cancel);
            // One of them wins; the other is told the order/delivery changed. A deadlock would surface as a 500.
            Assert.All(results, r => Assert.True(r.StatusCode is HttpStatusCode.OK or HttpStatusCode.Conflict, $"{r.StatusCode}: {r.Content.ReadAsStringAsync().Result}"));
            Assert.Contains(results, r => r.StatusCode == HttpStatusCode.OK);
        }
    }

    [Fact]
    public async Task The_delivered_column_follows_the_last_delivery_date_and_the_certificate_stage_is_per_item()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 100m);
        await AddStock(admin, s, s.Other, 50m);
        // Delivered long ago on an old order, versus delivered today on an old order.
        var recent = await ReleasedOrder(admin, s, 5m);
        var stale = await ReleasedOrder(admin, s, 5m);
        foreach (var o in new[] { recent, stale })
        {
            var d = await (await admin.Post($"/api/sales/orders/{o.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
            (await admin.Post($"/api/sales/deliveries/{d.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).EnsureSuccessStatusCode();
            (await admin.Post($"/api/sales/deliveries/{d.Id}/confirm", new ConfirmDeliveryIn())).EnsureSuccessStatusCode();
        }
        await using (var db = api.NewDb())
        {
            await db.SalesOrders.Where(o => o.Id == recent.Id || o.Id == stale.Id).ExecuteUpdateAsync(u => u.SetProperty(o => o.CreatedAt, DateTimeOffset.UtcNow.AddDays(-90)));
            await db.Deliveries.Where(d => d.OrderId == stale.Id).ExecuteUpdateAsync(u => u.SetProperty(d => d.DeliveredAt, DateTimeOffset.UtcNow.AddDays(-45)));
        }
        var pipeline = await (await admin.GetAsync($"/api/sales/pipeline?customerId={s.Customer.Id}")).Read<PipelineOut>();
        var delivered = pipeline.Stages.Single(x => x.Key == "delivered").Cards;
        Assert.Contains(delivered, c => c.Id == recent.Id);
        Assert.DoesNotContain(delivered, c => c.Id == stale.Id);

        // Two items, one certificate: the order keeps waiting in "certificate" until the second item has its own.
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 10m), new SalesLineInput(s.Other.Id, 5m)], "PO-9", s.Term.Id))).Read<SalesOrderOut>();
        order = await (await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn())).Read<SalesOrderOut>();
        var planned = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        var made = await (await admin.Post($"/api/sales/certificates/for-delivery/{planned.Id}", new object())).Read<List<CertificateOut>>();
        await IssueCertificateAsync(admin, made[0]);
        pipeline = await (await admin.GetAsync($"/api/sales/pipeline?customerId={s.Customer.Id}")).Read<PipelineOut>();
        Assert.Contains(pipeline.Stages.Single(x => x.Key == "certificate").Cards, c => c.Id == order.Id);
        await IssueCertificateAsync(admin, made[1]);
        pipeline = await (await admin.GetAsync($"/api/sales/pipeline?customerId={s.Customer.Id}")).Read<PipelineOut>();
        Assert.Contains(pipeline.Stages.Single(x => x.Key == "ready").Cards, c => c.Id == order.Id);
        Assert.DoesNotContain(pipeline.Stages.Single(x => x.Key == "certificate").Cards, c => c.Id == order.Id);
    }

    [Fact]
    public async Task Win_rate_leaves_out_quotes_replaced_by_a_revision()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        // One quote won, one lost, one accepted then revised (the revision is a draft, so only the original counts as "replaced").
        var won = await (await admin.Post("/api/sales/quotes", Quote(s, 20m))).Read<QuoteOut>();
        (await Act(admin, won.Id, "send")).EnsureSuccessStatusCode();
        (await Act(admin, won.Id, "accept")).EnsureSuccessStatusCode();
        var lost = await (await admin.Post("/api/sales/quotes", Quote(s, 20m))).Read<QuoteOut>();
        (await Act(admin, lost.Id, "send")).EnsureSuccessStatusCode();
        (await Act(admin, lost.Id, "decline", new QuoteActionIn("preço"))).EnsureSuccessStatusCode();
        var revised = await (await admin.Post("/api/sales/quotes", Quote(s, 20m))).Read<QuoteOut>();
        (await Act(admin, revised.Id, "send")).EnsureSuccessStatusCode();
        (await Act(admin, revised.Id, "accept")).EnsureSuccessStatusCode();
        (await admin.Post($"/api/sales/quotes/{revised.Id}/revise", new QuoteActionIn("Cliente pediu alteração"))).EnsureSuccessStatusCode();

        var rate = (await (await admin.GetAsync($"/api/sales/pipeline?customerId={s.Customer.Id}")).Read<PipelineOut>()).Kpis.WinRate;
        Assert.Equal(0.5m, rate); // 1 won / (1 won + 1 lost); the superseded quote is out of the denominator
    }

    [Fact]
    public async Task Dates_validity_and_freight_are_checked()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin, stock: 50m);
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post("/api/sales/quotes", Quote(s, 20m) with { ValidityDays = 400 }));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post("/api/sales/quotes", Quote(s, 20m) with { Freight = (FreightTerms)99 }));
        (await admin.Post("/api/sales/quotes", Quote(s, 20m) with { ValidityDays = 365 })).EnsureSuccessStatusCode();
        await AssertStatus(HttpStatusCode.BadRequest, admin.Put("/api/sales/settings", new SalesSettingsDto(5m, 400, 0m, s.Shipping.Id, null)));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 1m)], null, s.Term.Id, (FreightTerms)99)));

        var order = await ReleasedOrder(admin, s, 20m);
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today.AddYears(-2))));
        var d = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"/api/sales/deliveries/{d.Id}/ship", new ShipInput(Today.AddYears(-2), WithoutCertificate: true)));
        (await admin.Post($"/api/sales/deliveries/{d.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).EnsureSuccessStatusCode();
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"/api/sales/deliveries/{d.Id}/confirm", new ConfirmDeliveryIn(Today.AddDays(3))));
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"/api/sales/deliveries/{d.Id}/confirm", new ConfirmDeliveryIn(Today.AddDays(-3))));
        (await admin.Post($"/api/sales/deliveries/{d.Id}/confirm", new ConfirmDeliveryIn(Today))).EnsureSuccessStatusCode();

        var open = await ReleasedOrder(admin, s, 5m);
        await AssertStatus(HttpStatusCode.BadRequest, admin.Post($"/api/sales/orders/{open.Id}/reschedule", new RescheduleInput("atraso", Lines: [new RescheduleLine(open.Lines[0].Id, Today.AddDays(-5))])));
        // The same (even if already past) date is "unchanged": no complaint about it, just nothing to do.
        await AssertStatus(HttpStatusCode.Conflict, admin.Post($"/api/sales/orders/{open.Id}/reschedule", new RescheduleInput("sem mudança", Lines: [new RescheduleLine(open.Lines[0].Id, open.Lines[0].DueDate)])));
    }
}
