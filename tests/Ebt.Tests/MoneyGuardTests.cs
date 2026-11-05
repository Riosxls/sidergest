using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Inventory;
using Ebt.Core.Sales;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Tests;

/// <summary>Rules that keep money and fiscal documents consistent: order prices, manual NF numbers, delivery stock documents, NF cancel/ship retries.</summary>
[Collection("api")]
public class MoneyGuardTests(ApiFixture api)
{
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.Today);

    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();
    private static ProductIn Tube(string code) => new(code, "Tubo " + code, ProductKind.Part, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, null, null, "73063010", "PC", 50, false, null, null);

    private sealed record Setup(CustomerOut Customer, CustomerAddressOut Address, ProductOut Tube, StockLocationOut Shipping, PaymentTermOut Term);

    private async Task<Setup> Arrange(HttpClient admin)
    {
        var customer = await (await admin.Post("/api/customers", new CustomerIn("Cliente " + Code("C"), null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var address = await (await admin.Post($"/api/customers/{customer.Id}/addresses", new CustomerAddressIn("26133636000103", "SP", null, "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", "3515004", "06800000", "5101", "Edilto", "compras@cliente.com", null))).Read<CustomerAddressOut>();
        var tube = await (await admin.Post("/api/products", Tube(Code("T")))).Read<ProductOut>();
        var shipping = await (await admin.Post("/api/stock-locations", new StockLocationIn(Code("E", 10), "Expedicao", StockLocationKind.Internal))).Read<StockLocationOut>();
        (await admin.Put("/api/sales/settings", new SalesSettingsDto(5m, 15, 0m, shipping.Id, null))).EnsureSuccessStatusCode();
        (await admin.Post("/api/stock/documents", new StockPost(MovementType.AdjustmentIn, Today, [new StockLine(null, tube.Id, shipping.Id, 100m, UnitCost: 5m)], "INV"))).EnsureSuccessStatusCode();
        var term = await (await admin.Post("/api/sales/payment-terms", new PaymentTermIn(Code("P", 8), "28 DDL", "28", 1_000_000m))).Read<PaymentTermOut>();
        (await admin.Post("/api/sales/price-list", new PriceListIn(tube.Id, null, 100m, 5m, 18m, Today.AddDays(-1), null))).EnsureSuccessStatusCode();
        return new Setup(customer, address, tube, shipping, term);
    }

    private static async Task<SalesOrderOut> NewOrder(HttpClient admin, Setup s, decimal quantity = 10m)
    {
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, quantity)], "PO-9", s.Term.Id))).Read<SalesOrderOut>();
        (await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn())).EnsureSuccessStatusCode();
        return order;
    }

    private static async Task<DeliveryOut> NewDelivery(HttpClient admin, SalesOrderOut order, decimal quantity) =>
        await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today, Lines: [new DeliveryLineInput(order.Lines[0].Id, quantity)]))).Read<DeliveryOut>();

    private static async Task SetFiscal(HttpClient admin, bool enabled)
    {
        var s = await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>();
        (await admin.Put("/api/fiscal/settings", s with
        {
            Enabled = enabled, Environment = SefazEnvironment.Homologation, CompanyName = "EBT Tubos Ltda", TradeName = "EBT", Cnpj = "11222333000181", StateRegistration = "111222333444", TaxRegime = 3,
            Street = "Rua das Industrias", Number = "10", District = "Distrito", City = "Embu das Artes", CityIbgeCode = "3515004", Uf = "SP", ZipCode = "06800000", Phone = "1144444444"
        })).EnsureSuccessStatusCode();
    }

    private static async Task<FiscalDocumentSummary> NfOf(HttpClient admin, int deliveryId) =>
        Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?deliveryId={deliveryId}")).Read<Page<FiscalDocumentSummary>>()).Items);

    [Fact]
    public async Task A_salesperson_cannot_create_or_edit_an_order_below_the_discount_limit_but_a_manager_can()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var sales = await api.UserAsync(UserRole.Sales);
        SalesOrderIn Body(decimal? price) => new(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 1m, price)], "PO-1", s.Term.Id);

        Assert.Equal(HttpStatusCode.Conflict, (await sales.Post("/api/sales/orders", Body(50m))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await sales.Post("/api/sales/orders", Body(0m))).StatusCode);
        var atList = await (await sales.Post("/api/sales/orders", Body(null))).Read<SalesOrderOut>();
        (await sales.Post("/api/sales/orders", Body(97m))).EnsureSuccessStatusCode();   // 3% is inside the 5% limit

        Assert.Equal(HttpStatusCode.Conflict, (await sales.Put($"/api/sales/orders/{atList.Id}", Body(40m))).StatusCode);
        (await admin.Post("/api/sales/orders", Body(50m))).EnsureSuccessStatusCode();
        (await admin.Put($"/api/sales/orders/{atList.Id}", Body(40m))).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task A_typed_nf_number_only_counts_from_someone_who_may_emit_the_nf()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var stock = await api.UserAsync(UserRole.Stock);
        try
        {
            // Emission off: any shipper may record the number of an NF issued elsewhere.
            await SetFiscal(admin, false);
            var o1 = await NewOrder(admin, s);
            (await admin.Post($"/api/sales/orders/{o1.Id}/certificate-waiver", new CertificateWaiverIn(true))).EnsureSuccessStatusCode(); // the Stock role cannot ship without a certificate itself
            var d1 = await NewDelivery(admin, o1, 3m);
            var shipped = await (await stock.Post($"/api/sales/deliveries/{d1.Id}/ship", new ShipInput(Today, InvoiceNumber: "999", WithoutCertificate: true))).Read<DeliveryOut>();
            Assert.Equal("999", shipped.InvoiceNumber);

            // Emission on: for the Stock role the field is ignored, so the NF stays pending instead of being skipped.
            await SetFiscal(admin, true);
            (await admin.Post("/api/fiscal/monthly-prices", new MonthlyPriceIn(s.Tube.Id, s.Customer.Id, "5101", Today.Year, Today.Month, 110m))).EnsureSuccessStatusCode();
            var d2 = await NewDelivery(admin, o1, 3m);
            var pending = await (await stock.Post($"/api/sales/deliveries/{d2.Id}/ship", new ShipInput(Today, InvoiceNumber: "888", WithoutCertificate: true))).Read<DeliveryOut>();
            Assert.Null(pending.InvoiceNumber);
            Assert.Empty((await (await admin.GetAsync($"/api/fiscal/documents?deliveryId={d2.Id}")).Read<Page<FiscalDocumentSummary>>()).Items);
        }
        finally { await SetFiscal(admin, false); }
    }

    [Fact]
    public async Task The_shipment_document_of_a_delivery_cannot_be_reversed_on_its_own()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        await SetFiscal(admin, false);
        var order = await NewOrder(admin, s);
        var d = await NewDelivery(admin, order, 2m);
        var shipped = await (await admin.Post($"/api/sales/deliveries/{d.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).Read<DeliveryOut>();
        Assert.NotNull(shipped.StockDocumentId);

        var res = await admin.PostAsync($"/api/stock/documents/{shipped.StockDocumentId}/reverse", null);
        Assert.Equal(HttpStatusCode.Conflict, res.StatusCode);
        Assert.Contains(shipped.Reference, await res.Content.ReadAsStringAsync());

        // Cancelling the delivery is the way, and it does reverse the document.
        (await admin.Post($"/api/sales/deliveries/{d.Id}/cancel", new SalesReasonIn("cliente desistiu"))).EnsureSuccessStatusCode();
        Assert.Equal(DeliveryStatus.Cancelled, (await (await admin.GetAsync($"/api/sales/deliveries/{d.Id}")).Read<DeliveryOut>()).Status);
    }

    [Fact]
    public async Task Shipping_again_after_a_failed_shipment_reuses_the_authorized_nf_instead_of_issuing_a_second_one()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        try
        {
            await SetFiscal(admin, true);
            (await admin.Post("/api/fiscal/monthly-prices", new MonthlyPriceIn(s.Tube.Id, s.Customer.Id, "5101", Today.Year, Today.Month, 110m))).EnsureSuccessStatusCode();
            var order = await NewOrder(admin, s);
            var d = await NewDelivery(admin, order, 4m);
            var first = await (await admin.Post($"/api/sales/deliveries/{d.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).Read<DeliveryOut>();
            var nf = await NfOf(admin, d.Id);
            var nextNumber = (await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>()).NextNumber;

            // What a rollback after SEFAZ answered leaves behind: the NF is authorized, but the delivery is planned again and the NF has neither lines nor a delivery.
            await using (var db = api.NewDb())
            {
                await db.FiscalDocumentLines.Where(l => l.DocumentId == nf.Id).ExecuteDeleteAsync();
                await db.FiscalInstallments.Where(i => i.DocumentId == nf.Id).ExecuteDeleteAsync();
                await db.FiscalDocuments.Where(f => f.Id == nf.Id).ExecuteUpdateAsync(x => x.SetProperty(f => f.DeliveryId, (int?)null));
                await db.Deliveries.Where(x => x.Id == d.Id).ExecuteUpdateAsync(x => x.SetProperty(y => y.Status, DeliveryStatus.Planned).SetProperty(y => y.InvoiceNumber, (string?)null).SetProperty(y => y.StockDocumentId, (int?)null));
            }

            var again = await (await admin.Post($"/api/sales/deliveries/{d.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).Read<DeliveryOut>();
            Assert.Equal(first.InvoiceNumber, again.InvoiceNumber);
            Assert.Equal(nextNumber, (await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>()).NextNumber);
            Assert.Equal(nf.Id, (await NfOf(admin, d.Id)).Id);
            Assert.NotEmpty((await (await admin.GetAsync($"/api/fiscal/documents/{nf.Id}")).Read<FiscalDocumentOut>()).Lines);
        }
        finally { await SetFiscal(admin, false); }
    }

    [Fact]
    public async Task Cancelling_an_nf_undoes_the_delivery_first_and_a_refusal_leaves_the_nf_authorized()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        try
        {
            await SetFiscal(admin, true);
            (await admin.Post("/api/fiscal/monthly-prices", new MonthlyPriceIn(s.Tube.Id, s.Customer.Id, "5101", Today.Year, Today.Month, 110m))).EnsureSuccessStatusCode();
            var order = await NewOrder(admin, s);
            var d = await NewDelivery(admin, order, 4m);
            var shipped = await (await admin.Post($"/api/sales/deliveries/{d.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).Read<DeliveryOut>();
            var nf = await NfOf(admin, d.Id);
            // Every local write is saved before SEFAZ is called; the history still ends up naming the NF number.
            Assert.Contains((await (await admin.GetAsync($"/api/sales/deliveries/{d.Id}")).Read<DeliveryOut>()).History, h => h.Action == "shipped" && h.Note!.Contains($"NF {nf.Number}"));

            // The stock document is already reversed, so undoing the delivery is refused: the NF must not be cancelled at SEFAZ.
            await using (var db = api.NewDb())
                await db.StockDocuments.Where(x => x.Id == shipped.StockDocumentId).ExecuteUpdateAsync(x => x.SetProperty(y => y.Reversed, true));
            var refused = await admin.Post($"/api/fiscal/documents/{nf.Id}/cancel", new CancelInvoiceIn("Cancelamento de teste do NF", ApiFixture.AdminPassword));
            Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
            Assert.Equal(FiscalStatus.Authorized, (await (await admin.GetAsync($"/api/fiscal/documents/{nf.Id}")).Read<FiscalDocumentOut>()).Status);
            Assert.Equal(DeliveryStatus.Shipped, (await (await admin.GetAsync($"/api/sales/deliveries/{d.Id}")).Read<DeliveryOut>()).Status);

            await using (var db = api.NewDb())
                await db.StockDocuments.Where(x => x.Id == shipped.StockDocumentId).ExecuteUpdateAsync(x => x.SetProperty(y => y.Reversed, false));
            (await admin.Post($"/api/fiscal/documents/{nf.Id}/cancel", new CancelInvoiceIn("Cancelamento de teste do NF", ApiFixture.AdminPassword))).EnsureSuccessStatusCode();
            Assert.Equal(FiscalStatus.Cancelled, (await (await admin.GetAsync($"/api/fiscal/documents/{nf.Id}")).Read<FiscalDocumentOut>()).Status);
            Assert.Equal(DeliveryStatus.Cancelled, (await (await admin.GetAsync($"/api/sales/deliveries/{d.Id}")).Read<DeliveryOut>()).Status);
        }
        finally { await SetFiscal(admin, false); }
    }
}