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
    public async Task Sale_nf_uses_monthly_price_over_the_order_price_is_recorded_only_after_authorization_and_can_be_cancelled()
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
            Assert.Contains("difere do preço do pedido", nf.Warnings);
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
    public async Task Stock_ships_physically_and_leaves_the_nf_to_sales()
    {
        var admin = await api.AdminAsync();
        var stock = await api.UserAsync(UserRole.Stock);
        var sales = await api.UserAsync(UserRole.Sales);
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
            await Enable(admin, true);
            (await admin.Post("/api/fiscal/monthly-prices", new MonthlyPriceIn(tube.Id, customer.Id, "5101", Today.Year, Today.Month, 110m))).EnsureSuccessStatusCode();
            var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
            (await admin.Post($"/api/sales/orders/{order.Id}/certificate-waiver", new CertificateWaiverIn(true))).EnsureSuccessStatusCode(); // the Stock role cannot ship without a certificate itself

            delivery = await (await stock.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).Read<DeliveryOut>();
            Assert.Equal(DeliveryStatus.Shipped, delivery.Status);
            Assert.Null(delivery.InvoiceNumber);
            Assert.Equal(20m, await Balance(admin, tube.Id, shipping.Id));
            Assert.Empty((await (await admin.GetAsync($"/api/fiscal/documents?deliveryId={delivery.Id}")).Read<Page<FiscalDocumentSummary>>()).Items);

            Assert.Equal(HttpStatusCode.Forbidden, (await stock.Post($"/api/sales/deliveries/{delivery.Id}/emit-invoice", new EmitInvoiceInput())).StatusCode);
            delivery = await (await sales.Post($"/api/sales/deliveries/{delivery.Id}/emit-invoice", new EmitInvoiceInput())).Read<DeliveryOut>();
            Assert.NotNull(delivery.InvoiceNumber);
            Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?deliveryId={delivery.Id}")).Read<Page<FiscalDocumentSummary>>()).Items);
            Assert.Equal(HttpStatusCode.Conflict, (await sales.Post($"/api/sales/deliveries/{delivery.Id}/emit-invoice", new EmitInvoiceInput())).StatusCode);
        }
        finally
        {
            await Enable(admin, false);
        }
    }

    [Fact]
    public async Task Fine_permissions_gate_certificate_issue_and_price_list()
    {
        var sales = await api.UserAsync(UserRole.Sales);
        var manager = await api.UserAsync(UserRole.SalesManager);
        var stock = await api.UserAsync(UserRole.Stock);
        Assert.Equal(HttpStatusCode.Forbidden, (await sales.Post("/api/sales/certificates/1/issue", new { })).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await sales.Post("/api/sales/price-list", new PriceListIn(1, null, 1m, null, null, Today, null))).StatusCode);
        Assert.NotEqual(HttpStatusCode.Forbidden, (await manager.Post("/api/sales/certificates/999999/issue", new { })).StatusCode);
        Assert.NotEqual(HttpStatusCode.Forbidden, (await manager.Post("/api/sales/price-list", new PriceListIn(0, null, 1m, null, null, Today, null))).StatusCode);
        var me = await (await stock.GetAsync("/api/auth/me")).Content.ReadAsStringAsync();
        Assert.Contains("sales-ship", me);
        Assert.DoesNotContain("fiscal-emit", me);
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

    private sealed record SaleSetup(CustomerOut Customer, ProductOut Tube, StockLocationOut Shipping, SalesOrderOut Order);

    private async Task<SaleSetup> ReleasedSaleAsync(HttpClient admin)
    {
        var customer = await (await admin.Post("/api/customers", new CustomerIn("Cliente " + Code("C"), null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var address = await (await admin.Post($"/api/customers/{customer.Id}/addresses", new CustomerAddressIn("26133636000103", "SP", null, "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", "3515004", "06800000", "5101", "Edilto", "compras@cliente.com", null))).Read<CustomerAddressOut>();
        var tube = await (await admin.Post("/api/products", Tube(Code("T")))).Read<ProductOut>();
        var shipping = await (await admin.Post("/api/stock-locations", new StockLocationIn(Code("E", 10), "Expedição", StockLocationKind.Internal))).Read<StockLocationOut>();
        (await admin.Put("/api/sales/settings", new SalesSettingsDto(5m, 15, 0m, shipping.Id, null))).EnsureSuccessStatusCode();
        (await admin.Post("/api/stock/documents", new StockPost(MovementType.AdjustmentIn, Today, [new StockLine(null, tube.Id, shipping.Id, 30m, UnitCost: 5m)], "INV"))).EnsureSuccessStatusCode();
        var term = await (await admin.Post("/api/sales/payment-terms", new PaymentTermIn(Code("P", 8), "28 DDL", "28", 1_000_000m))).Read<PaymentTermOut>();
        (await admin.Post("/api/sales/price-list", new PriceListIn(tube.Id, null, 100m, 5m, 18m, Today.AddDays(-1), null))).EnsureSuccessStatusCode();
        (await admin.Post("/api/fiscal/monthly-prices", new MonthlyPriceIn(tube.Id, customer.Id, "5101", Today.Year, Today.Month, 110m))).EnsureSuccessStatusCode();
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(customer.Id, address.Id, [new SalesLineInput(tube.Id, 10m)], "PO-9", term.Id))).Read<SalesOrderOut>();
        await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn());
        return new SaleSetup(customer, tube, shipping, order);
    }

    [Fact]
    public async Task Lost_answer_leaves_a_pending_nf_that_reconciliation_resolves()
    {
        var admin = await api.AdminAsync();
        var s = await ReleasedSaleAsync(admin);
        try
        {
            var settings = await Enable(admin, true);

            // SEFAZ never saw the NF: 502, number stays reserved (Pending), delivery and stock roll back; reconciliation gives the number back.
            var lost = await (await admin.Post($"/api/sales/orders/{s.Order.Id}/deliveries", new DeliveryInput(Today, Notes: StubSefazClient.TimeoutMarker))).Read<DeliveryOut>();
            var res = await admin.Post($"/api/sales/deliveries/{lost.Id}/ship", new ShipInput(Today, WithoutCertificate: true));
            Assert.Equal(HttpStatusCode.BadGateway, res.StatusCode);
            Assert.Equal(DeliveryStatus.Planned, (await (await admin.GetAsync($"/api/sales/deliveries/{lost.Id}")).Read<DeliveryOut>()).Status);
            Assert.Equal(30m, await Balance(admin, s.Tube.Id, s.Shipping.Id));
            Assert.Equal(settings.NextNumber + 1, (await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>()).NextNumber);
            var pending = Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?status={FiscalStatus.Pending}&q={settings.NextNumber}")).Read<Page<FiscalDocumentSummary>>()).Items);
            Assert.Equal(settings.NextNumber, pending.Number);

            var young = await (await admin.Post($"/api/fiscal/documents/{pending.Id}/reconcile?minAgeMinutes=60", new { })).Read<ReconcileResult>();
            Assert.Equal("waiting", young.Outcome);
            var released = await (await admin.Post($"/api/fiscal/documents/{pending.Id}/reconcile?minAgeMinutes=0", new { })).Read<ReconcileResult>();
            Assert.Equal("released", released.Outcome);
            Assert.Equal(settings.NextNumber, (await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>()).NextNumber);
            Assert.Equal(HttpStatusCode.NotFound, (await admin.GetAsync($"/api/fiscal/documents/{pending.Id}")).StatusCode);
            (await admin.Post($"/api/sales/deliveries/{lost.Id}/cancel", new SalesReasonIn("teste"))).EnsureSuccessStatusCode();

            // SEFAZ authorized it but the answer was lost: reconciliation marks it Authorized and says it has no delivery attached.
            var ghost = await (await admin.Post($"/api/sales/orders/{s.Order.Id}/deliveries", new DeliveryInput(Today, Notes: StubSefazClient.TimeoutAuthorizedMarker))).Read<DeliveryOut>();
            Assert.Equal(HttpStatusCode.BadGateway, (await admin.Post($"/api/sales/deliveries/{ghost.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).StatusCode);
            var stuck = Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?status={FiscalStatus.Pending}&q={settings.NextNumber}")).Read<Page<FiscalDocumentSummary>>()).Items);
            var all = await (await admin.Post("/api/fiscal/documents/reconcile?minAgeMinutes=0", new { })).Read<List<ReconcileResult>>();
            var one = Assert.Single(all, r => r.Id == stuck.Id);
            Assert.Equal("authorized", one.Outcome);
            Assert.True(one.Unlinked);
            var nf = await (await admin.GetAsync($"/api/fiscal/documents/{stuck.Id}")).Read<FiscalDocumentOut>();
            Assert.Equal(FiscalStatus.Authorized, nf.Status);
            Assert.NotEmpty(nf.Protocol);
            Assert.Contains("no delivery", nf.StatusMessage);
            Assert.Equal(HttpStatusCode.Conflict, (await admin.Post($"/api/fiscal/documents/{stuck.Id}/reconcile?minAgeMinutes=0", new { })).StatusCode);
        }
        finally
        {
            await Enable(admin, false);
        }
    }

    [Fact]
    public async Task Rejection_gives_the_number_back_when_nothing_later_was_issued()
    {
        var admin = await api.AdminAsync();
        var s = await ReleasedSaleAsync(admin);
        try
        {
            var settings = await Enable(admin, true);
            var rejected = await (await admin.Post($"/api/sales/orders/{s.Order.Id}/deliveries", new DeliveryInput(Today, Notes: StubSefazClient.RejectMarker))).Read<DeliveryOut>();
            Assert.Equal(HttpStatusCode.UnprocessableEntity, (await admin.Post($"/api/sales/deliveries/{rejected.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).StatusCode);
            Assert.Equal(settings.NextNumber, (await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>()).NextNumber);
            Assert.Empty((await (await admin.GetAsync($"/api/fiscal/documents?q={settings.NextNumber}")).Read<Page<FiscalDocumentSummary>>()).Items);
        }
        finally
        {
            await Enable(admin, false);
        }
    }

    [Fact]
    public async Task Inutilization_gives_up_a_skipped_number_after_checks_and_is_recorded()
    {
        var admin = await api.AdminAsync();
        var s = await ReleasedSaleAsync(admin);
        try
        {
            var settings = await Enable(admin, true);
            var n = settings.NextNumber;

            // Number n is lost (Pending, SEFAZ never saw it); the next sale takes n + 1, so n cannot go back to the sequence and stays as a Rejected gap.
            var lost = await (await admin.Post($"/api/sales/orders/{s.Order.Id}/deliveries", new DeliveryInput(Today, Notes: StubSefazClient.TimeoutMarker))).Read<DeliveryOut>();
            Assert.Equal(HttpStatusCode.BadGateway, (await admin.Post($"/api/sales/deliveries/{lost.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).StatusCode);
            (await admin.Post($"/api/sales/deliveries/{lost.Id}/cancel", new SalesReasonIn("teste"))).EnsureSuccessStatusCode();
            var ok = await (await admin.Post($"/api/sales/orders/{s.Order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
            ok = await (await admin.Post($"/api/sales/deliveries/{ok.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).Read<DeliveryOut>();
            Assert.Equal((n + 1).ToString(), ok.InvoiceNumber);
            var stuck = Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?status={FiscalStatus.Pending}&q={n}")).Read<Page<FiscalDocumentSummary>>()).Items);
            var gap = await (await admin.Post($"/api/fiscal/documents/{stuck.Id}/reconcile?minAgeMinutes=0", new { })).Read<ReconcileResult>();
            Assert.Equal("rejected", gap.Outcome);
            Assert.Equal(FiscalStatus.Rejected, gap.Status);

            Task<HttpResponseMessage> Inut(int from, int to, string reason = "Numeracao pulada por falha de comunicacao", string? pw = null) =>
                admin.Post("/api/fiscal/inutilizations", new InutilizeIn(null, from, to, reason, pw ?? ApiFixture.AdminPassword));
            Assert.Equal(HttpStatusCode.BadRequest, (await Inut(n, n, "curto")).StatusCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await Inut(n, n, pw: "senha-errada")).StatusCode);
            Assert.Equal(HttpStatusCode.Conflict, (await Inut(n, n + 1)).StatusCode);        // n + 1 is authorized
            Assert.Equal(HttpStatusCode.Conflict, (await Inut(n + 2, n + 2)).StatusCode);    // not issued yet

            var done = await (await Inut(n, n)).Read<InutilizationOut>();
            Assert.Equal((n, n), (done.FromNumber, done.ToNumber));
            Assert.NotEmpty(done.Protocol);
            Assert.Equal(HttpStatusCode.Conflict, (await Inut(n, n)).StatusCode);            // already inutilized
            Assert.Contains(await (await admin.GetAsync("/api/fiscal/inutilizations")).Read<List<InutilizationOut>>(), i => i.Id == done.Id);
            var nf = await (await admin.GetAsync($"/api/fiscal/documents/{stuck.Id}")).Read<FiscalDocumentOut>();
            Assert.Contains("Inutilizada", nf.StatusMessage);
        }
        finally
        {
            await Enable(admin, false);
        }
    }

    [Fact]
    public async Task Inutilization_and_reconciliation_reject_bad_requests()
    {
        var admin = await api.AdminAsync();
        try
        {
            var settings = await Enable(admin, true);
            Task<HttpResponseMessage> Inut(int? series, int from, int to, string? reason = "Numeracao pulada por falha de comunicacao", string? pw = null) =>
                admin.Post("/api/fiscal/inutilizations", new InutilizeIn(series, from, to, reason, pw ?? ApiFixture.AdminPassword));

            Assert.Equal(HttpStatusCode.BadRequest, (await Inut(null, 1, 1, null)).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post("/api/fiscal/inutilizations", new InutilizeIn(null, 1, 1, "Numeracao pulada por falha", null))).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await Inut(null, 1, 1, new string('x', 256))).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await Inut(null, 0, 1)).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await Inut(null, 5, 4)).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await Inut(null, 1, 1001)).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await Inut(0, 1, 1)).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await Inut(1000, 1, 1)).StatusCode);
            Assert.Equal(HttpStatusCode.Conflict, (await Inut(null, settings.NextNumber, settings.NextNumber)).StatusCode);
            // another series never touched by this system: nothing to compare with, the numbers are simply given up
            var other = await (await Inut(998, 1, 2)).Read<InutilizationOut>();
            Assert.Equal(998, other.Series);
            Assert.Equal(HttpStatusCode.Conflict, (await Inut(998, 2, 3)).StatusCode);

            Assert.Equal(HttpStatusCode.NotFound, (await admin.Post("/api/fiscal/documents/999999/reconcile", new { })).StatusCode);
            Assert.Equal(HttpStatusCode.NotFound, (await admin.Post("/api/fiscal/documents/999999/cancel", new CancelInvoiceIn("Erro de digitação no pedido", ApiFixture.AdminPassword))).StatusCode);
        }
        finally
        {
            await Enable(admin, false);
        }
    }

    [Fact]
    public async Task Cancel_is_refused_after_the_window_and_for_an_already_cancelled_nf()
    {
        var admin = await api.AdminAsync();
        var s = await ReleasedSaleAsync(admin);
        var original = await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>();
        try
        {
            var settings = await Enable(admin, true);
            var delivery = await (await admin.Post($"/api/sales/orders/{s.Order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
            await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, WithoutCertificate: true));
            var doc = Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?deliveryId={delivery.Id}")).Read<Page<FiscalDocumentSummary>>()).Items);

            settings = await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>();
            // issued three hours ago, window of one hour
            await using (var db = api.NewDb())
                await db.FiscalDocuments.Where(d => d.Id == doc.Id).ExecuteUpdateAsync(u => u.SetProperty(d => d.IssuedAt, DateTimeOffset.UtcNow.AddHours(-3)));
            (await admin.Put("/api/fiscal/settings", settings with { CancelWindowHours = 1 })).EnsureSuccessStatusCode();
            var late = await admin.Post($"/api/fiscal/documents/{doc.Id}/cancel", new CancelInvoiceIn("Erro de digitação no pedido do cliente", ApiFixture.AdminPassword));
            Assert.Equal(HttpStatusCode.Conflict, late.StatusCode);
            Assert.Contains("return NF", await late.Content.ReadAsStringAsync());

            // no window at all: the cancellation works once, then the NF is no longer authorized
            (await admin.Put("/api/fiscal/settings", settings with { CancelWindowHours = 0 })).EnsureSuccessStatusCode();
            (await admin.Post($"/api/fiscal/documents/{doc.Id}/cancel", new CancelInvoiceIn("Erro de digitação no pedido do cliente", ApiFixture.AdminPassword))).EnsureSuccessStatusCode();
            Assert.Equal(HttpStatusCode.Conflict, (await admin.Post($"/api/fiscal/documents/{doc.Id}/cancel", new CancelInvoiceIn("Erro de digitação no pedido do cliente", ApiFixture.AdminPassword))).StatusCode);
            Assert.Equal(HttpStatusCode.Conflict, (await admin.Post($"/api/fiscal/documents/{doc.Id}/reconcile?minAgeMinutes=0", new { })).StatusCode);
        }
        finally
        {
            await Enable(admin, false);
            (await admin.Put("/api/fiscal/settings", (await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>()) with { CancelWindowHours = original.CancelWindowHours })).EnsureSuccessStatusCode();
        }
    }
}
