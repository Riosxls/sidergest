using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Inventory;
using Ebt.Core.Production;
using Ebt.Core.Sales;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Tests;

public class NfeKeyTests
{
    [Fact]
    public void Check_digit_matches_the_official_manual_example()
    {
        Assert.Equal(3, NfeKey.CheckDigit("3508059999909091027055001000000001518005127"));
    }

    [Fact]
    public void Key_has_44_digits_and_a_valid_check_digit()
    {
        var key = NfeKey.Build(35, new DateTimeOffset(2026, 10, 28, 9, 0, 0, TimeSpan.FromHours(-3)), "11222333000181", 1, 2581, "12345678");
        Assert.Equal(44, key.Length);
        Assert.StartsWith("352610" + "11222333000181" + "55001000002581" + "1" + "12345678", key);
        Assert.Equal(NfeKey.CheckDigit(key[..43]), key[43] - '0');
    }

    [Fact]
    public void Code_number_never_equals_the_nf_number()
    {
        for (var i = 0; i < 200; i++) Assert.NotEqual(7, int.Parse(NfeKey.NewCodeNumber(7)));
    }
}

[Collection("api")]
public class FiscalTests(ApiFixture api)
{
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.Today);

    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();
    private static ProductIn Tube(string code) => new(code, "Tubo " + code, ProductKind.Part, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, null, null, "73063010", "PC", 50, false, null, null);

    private static async Task<FiscalSettingsDto> Enable(HttpClient admin, bool enabled)
    {
        var s = await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>();
        var next = s with
        {
            Enabled = enabled, Environment = SefazEnvironment.Homologation, CompanyName = "EBT Tubos Ltda", TradeName = "EBT", Cnpj = "11222333000181", StateRegistration = "111222333444", TaxRegime = 3,
            Street = "Rua das Industrias", Number = "10", District = "Distrito", City = "Embu das Artes", CityIbgeCode = "3515004", Uf = "SP", ZipCode = "06800000", Phone = "1144444444"
        };
        return await (await admin.Put("/api/fiscal/settings", next)).Read<FiscalSettingsDto>();
    }

    [Fact]
    public async Task Sale_nf_needs_monthly_price_is_recorded_only_after_authorization_and_can_be_cancelled()
    {
        var admin = await api.AdminAsync();
        var customer = await (await admin.Post("/api/customers", new CustomerIn("Cliente " + Code("C"), null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var address = await (await admin.Post($"/api/customers/{customer.Id}/addresses", new CustomerAddressIn("26133636000103", "SP", null, "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", "3515004", "06800000", "5101", "Edilto", "compras@cliente.com", null))).Read<CustomerAddressOut>();
        var tube = await (await admin.Post("/api/products", Tube(Code("T")))).Read<ProductOut>();
        var shipping = await (await admin.Post("/api/stock-locations", new StockLocationIn(Code("E", 10), "Expedição", StockLocationKind.Internal))).Read<StockLocationOut>();
        (await admin.Put("/api/sales/settings", new SalesSettingsDto(5m, 15, 0m, shipping.Id, null))).EnsureSuccessStatusCode();
        (await admin.Post("/api/stock/documents", new StockPost(MovementType.AdjustmentIn, Today, [new StockLine(null, tube.Id, shipping.Id, 30m, UnitCost: 5m)], "INV"))).EnsureSuccessStatusCode();
        var term = await (await admin.Post("/api/sales/payment-terms", new PaymentTermIn(Code("P", 8), "28 DDL", "28", 1_000_000m))).Read<PaymentTermOut>();
        (await admin.Post("/api/sales/price-list", new PriceListIn(tube.Id, null, 100m, 5m, 18m, Today.AddDays(-1), null))).EnsureSuccessStatusCode();
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(customer.Id, address.Id, [new SalesLineInput(tube.Id, 10m)], "PO-9", term.Id))).Read<SalesOrderOut>();
        await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn());

        try
        {
            var settings = await Enable(admin, true);
            var rejected = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today, Notes: StubSefazClient.RejectMarker))).Read<DeliveryOut>();

            var noPrice = await admin.Post($"/api/sales/deliveries/{rejected.Id}/ship", new ShipInput(Today, WithoutCertificate: true));
            Assert.Equal(HttpStatusCode.UnprocessableEntity, noPrice.StatusCode);
            Assert.Contains("monthly price", await noPrice.Content.ReadAsStringAsync());

            (await admin.Post("/api/fiscal/monthly-prices", new MonthlyPriceIn(tube.Id, customer.Id, "5101", Today.Year, Today.Month, 110m))).EnsureSuccessStatusCode();
            var sefaz = await admin.Post($"/api/sales/deliveries/{rejected.Id}/ship", new ShipInput(Today, WithoutCertificate: true));
            Assert.Equal(HttpStatusCode.UnprocessableEntity, sefaz.StatusCode);
            Assert.Contains("SEFAZ rejected", await sefaz.Content.ReadAsStringAsync());

            // Rejection leaves nothing behind: delivery still planned, stock untouched, number not consumed, no NF row.
            Assert.Equal(DeliveryStatus.Planned, (await (await admin.GetAsync($"/api/sales/deliveries/{rejected.Id}")).Read<DeliveryOut>()).Status);
            Assert.Equal(30m, await Balance(admin, tube.Id, shipping.Id));
            Assert.Equal(settings.NextNumber, (await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>()).NextNumber);
            Assert.Empty((await (await admin.GetAsync($"/api/fiscal/documents?deliveryId={rejected.Id}")).Read<Page<FiscalDocumentSummary>>()).Items);
            (await admin.Post($"/api/sales/deliveries/{rejected.Id}/cancel", new SalesReasonIn("NF rejeitada"))).EnsureSuccessStatusCode();

            var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today, Notes: "Entregar na portaria 2"))).Read<DeliveryOut>();
            delivery = await (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, Freight: 50m, GrossWeightKg: 20m, WithoutCertificate: true))).Read<DeliveryOut>();
            Assert.Equal(DeliveryStatus.Shipped, delivery.Status);
            Assert.Equal(settings.NextNumber.ToString(), delivery.InvoiceNumber);
            Assert.Equal(20m, await Balance(admin, tube.Id, shipping.Id));

            var doc = Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?deliveryId={delivery.Id}")).Read<Page<FiscalDocumentSummary>>()).Items);
            var nf = await (await admin.GetAsync($"/api/fiscal/documents/{doc.Id}")).Read<FiscalDocumentOut>();
            Assert.True(nf.Simulated);
            Assert.Equal(FiscalStatus.Authorized, nf.Status);
            Assert.Equal("5101", nf.CfopCode);
            Assert.Equal(1100m, nf.ProductsTotal);
            Assert.Equal(50m, nf.FreightTotal);
            Assert.Equal(57.5m, nf.IpiTotal);             // 5% of (1100 + 50)
            Assert.Equal(1150m, nf.IcmsBase);             // contributor: IPI stays out of the ICMS base
            Assert.Equal(207m, nf.IcmsTotal);             // 18%
            Assert.Equal(7.15m, nf.PisTotal);             // 0.65% of goods
            Assert.Equal(33m, nf.CofinsTotal);            // 3% of goods
            Assert.Equal(1207.5m, nf.InvoiceTotal);
            var line = Assert.Single(nf.Lines);
            Assert.Equal(110m, line.UnitPrice);
            Assert.Equal("73063010", line.Ncm);
            var dup = Assert.Single(nf.Installments);
            Assert.Equal(Today.AddDays(28), dup.DueDate);
            Assert.Equal(1207.5m, dup.Amount);
            Assert.Equal(44, nf.AccessKey.Length);
            Assert.Equal(NfeKey.CheckDigit(nf.AccessKey[..43]), nf.AccessKey[43] - '0');

            var xml = await (await admin.GetAsync($"/api/fiscal/documents/{nf.Id}/xml")).Content.ReadAsStringAsync();
            Assert.Contains($"Id=\"NFe{nf.AccessKey}\"", xml);
            Assert.Contains("<CFOP>5101</CFOP>", xml);
            Assert.Contains("<ICMS00>", xml);
            Assert.Contains("<dup>", xml);
            Assert.Contains(NfeXml.HomologationText, xml);

            // Cancel: reason + the user's own password; the delivery goes back and stock returns.
            Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post($"/api/fiscal/documents/{nf.Id}/cancel", new CancelInvoiceIn("curto", ApiFixture.AdminPassword))).StatusCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await admin.Post($"/api/fiscal/documents/{nf.Id}/cancel", new CancelInvoiceIn("Erro de digitação no pedido do cliente", "senha-errada"))).StatusCode);
            Assert.Equal(HttpStatusCode.Conflict, (await admin.Post($"/api/sales/deliveries/{delivery.Id}/cancel", new SalesReasonIn("tentativa direta"))).StatusCode);
            var cancelled = await (await admin.Post($"/api/fiscal/documents/{nf.Id}/cancel", new CancelInvoiceIn("Erro de digitação no pedido do cliente", ApiFixture.AdminPassword))).Read<FiscalDocumentOut>();
            Assert.Equal(FiscalStatus.Cancelled, cancelled.Status);
            Assert.NotNull(cancelled.CancelProtocol);
            Assert.Equal(DeliveryStatus.Cancelled, (await (await admin.GetAsync($"/api/sales/deliveries/{delivery.Id}")).Read<DeliveryOut>()).Status);
            Assert.Equal(30m, await Balance(admin, tube.Id, shipping.Id));
        }
        finally
        {
            await Enable(admin, false);
        }
    }

    [Fact]
    public async Task Outside_shipment_issues_5901_without_taxes_and_cancel_is_blocked_after_a_return()
    {
        var admin = await api.AdminAsync();
        var wc = await (await admin.Post("/api/work-centers", new WorkCenterIn(Code("W", 10), "Recozimento", null))).Read<WorkCenterOut>();
        var machine = await (await admin.Post("/api/machines", new MachineIn(Code("MQ", 10), "Forno", wc.Id, "FORNOS"))).Read<MachineOut>();
        var product = await (await admin.Post("/api/products", Tube(Code("P")))).Read<ProductOut>();
        (await admin.Post($"/api/products/{product.Id}/routing", new RoutingOperationIn(10, null, machine.Id, wc.Id, null, 1m, 50m, 1m, "Recozimento", null, null))).EnsureSuccessStatusCode();
        (await admin.Put("/api/production/settings", new ProductionSettingsDto(3m, 8m, false, null, null))).EnsureSuccessStatusCode();
        var supplier = await (await admin.Post("/api/suppliers", new SupplierIn("Beneficiadora " + Code("B"), null, null, null))).Read<SupplierOut>();
        var order = await (await admin.Post("/api/production/orders", new ProductionOrderIn(product.Id, 100m, Today.AddDays(30)))).Read<ProductionOrderOut>();
        (await admin.Put($"/api/production/orders/{order.Id}/operations/10/outsource", new OutsourceInput(supplier.Id, 5))).EnsureSuccessStatusCode();
        (await admin.Post($"/api/production/orders/{order.Id}/release", new ReleaseIn())).EnsureSuccessStatusCode();

        try
        {
            await Enable(admin, true);
            var url = $"/api/production/orders/{order.Id}/operations/10/outside-shipments";

            var noAddress = await admin.Post(url, new OutsideSendInput(Today, 40m, null, null, 0.6m));
            Assert.Equal(HttpStatusCode.UnprocessableEntity, noAddress.StatusCode);
            Assert.Contains("no address with CNPJ", await noAddress.Content.ReadAsStringAsync());
            (await admin.Post($"/api/suppliers/{supplier.Id}/addresses", new SupplierAddressIn("SP", "04252011000110", null, "110042490114", "Rua do Forno", "5", "Jardim", "São Paulo", "3550308", "01001000", null, null))).EnsureSuccessStatusCode();

            Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post(url, new OutsideSendInput(Today, 40m, null, null))).StatusCode);   // no reference value
            var first = await (await admin.Post(url, new OutsideSendInput(Today, 40m, null, "lote 1", 0.6m))).Read<OutsideShipmentOut>();
            Assert.NotNull(first.InvoiceNumber);
            var doc = Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?outsideShipmentId={first.Id}")).Read<Page<FiscalDocumentSummary>>()).Items);
            var nf = await (await admin.GetAsync($"/api/fiscal/documents/{doc.Id}")).Read<FiscalDocumentOut>();
            Assert.Equal(FiscalKind.OutsideShipment, nf.Kind);
            Assert.Equal("5901", nf.CfopCode);
            Assert.Equal(24m, nf.ProductsTotal);
            Assert.Equal(0m, nf.IcmsTotal + nf.IpiTotal + nf.PisTotal + nf.CofinsTotal);
            Assert.Equal(24m, nf.InvoiceTotal);
            Assert.Empty(nf.Installments);
            Assert.Contains("art. 43 do Decreto 7.212/10", nf.AdditionalInfo);
            var xml = await (await admin.GetAsync($"/api/fiscal/documents/{nf.Id}/xml")).Content.ReadAsStringAsync();
            Assert.Contains("<cEnq>108</cEnq>", xml);
            Assert.Contains("<IPINT><CST>55</CST></IPINT>", xml);
            Assert.Contains("<ICMS40><orig>0</orig><CST>50</CST></ICMS40>", xml);
            Assert.Contains("<tPag>90</tPag>", xml);

            var second = await (await admin.Post(url, new OutsideSendInput(Today, 10m, null, null, 0.6m))).Read<OutsideShipmentOut>();
            (await admin.Post($"/api/production/outside-shipments/{first.Id}/returns", new OutsideReturnInput(Today, 40m, 0m, 0.6m, null, "9001", null))).EnsureSuccessStatusCode();

            var blocked = await admin.Post($"/api/fiscal/documents/{nf.Id}/cancel", new CancelInvoiceIn("Remessa duplicada por engano", ApiFixture.AdminPassword));
            Assert.Equal(HttpStatusCode.Conflict, blocked.StatusCode);
            Assert.Contains("processing return", await blocked.Content.ReadAsStringAsync());

            var secondDoc = Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?outsideShipmentId={second.Id}")).Read<Page<FiscalDocumentSummary>>()).Items);
            var cancelled = await (await admin.Post($"/api/fiscal/documents/{secondDoc.Id}/cancel", new CancelInvoiceIn("Remessa duplicada por engano", ApiFixture.AdminPassword))).Read<FiscalDocumentOut>();
            Assert.Equal(FiscalStatus.Cancelled, cancelled.Status);
            Assert.Null((await (await admin.GetAsync($"/api/production/outside-shipments/{second.Id}")).Read<OutsideShipmentOut>()).InvoiceNumber);
        }
        finally
        {
            await Enable(admin, false);
        }
    }

    [Fact]
    public async Task Only_admin_edits_settings_and_managers_edit_prices()
    {
        var sales = await api.UserAsync(UserRole.Sales);
        var manager = await api.UserAsync(UserRole.SalesManager);
        var s = await (await sales.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>();
        Assert.Equal(HttpStatusCode.Forbidden, (await manager.Put("/api/fiscal/settings", s)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await sales.Post("/api/fiscal/monthly-prices", new MonthlyPriceIn(1, 1, "5101", 2026, 10, 1m))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await manager.Post("/api/fiscal/monthly-prices", new MonthlyPriceIn(0, 0, "5101", 2026, 13, 0m))).StatusCode);
        var enableIncomplete = await (await api.AdminAsync()).Put("/api/fiscal/settings", s with { Enabled = true, Cnpj = null });
        Assert.Equal(HttpStatusCode.BadRequest, enableIncomplete.StatusCode);
    }

    private static async Task<decimal> Balance(HttpClient c, int productId, int locationId) =>
        (await (await c.GetAsync($"/api/stock/balances?productId={productId}&locationId={locationId}")).Read<Page<StockBalanceOut>>()).Items.Sum(b => b.Quantity);
}
