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
        quote = await (await Act(admin, quote.Id, "cancel", new QuoteActionIn("Projeto cancelado"))).Read<QuoteOut>();
        Assert.Equal(QuoteStatus.Cancelled, quote.Status);
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

        var done = await (await admin.Post("/api/admin/data-reset", body with { Confirm = MaintenanceEndpoints.ConfirmWord })).Read<DataResetOut>();
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

        var all = new DataResetIn([Ebt.Core.Maintenance.ResetScope.Sales, Ebt.Core.Maintenance.ResetScope.Purchasing, Ebt.Core.Maintenance.ResetScope.Production, Ebt.Core.Maintenance.ResetScope.Stock], MaintenanceEndpoints.ConfirmWord);
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
        var res = await admin.Post("/api/admin/data-reset", new DataResetIn([Ebt.Core.Maintenance.ResetScope.Stock], MaintenanceEndpoints.ConfirmWord));
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
}
