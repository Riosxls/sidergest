using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Inventory;
using Ebt.Core.Sales;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace Ebt.Tests;

/// <summary>Return NF (devolução), CC-e, duplicity handling, live-NF uniqueness, price fallback, transport data and the scheduled reconciliation.</summary>
[Collection("api")]
public class FiscalReturnTests(ApiFixture api)
{
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.Today);

    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();
    private static ProductIn Tube(string code) => new(code, "Tubo " + code, ProductKind.Part, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, null, null, "73063010", "PC", 50, false, null, null);

    private static async Task Enable(HttpClient admin, bool enabled)
    {
        var s = await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>();
        var next = s with
        {
            Enabled = enabled, Environment = SefazEnvironment.Homologation, CompanyName = "EBT Tubos Ltda", TradeName = "EBT", Cnpj = "11222333000181", StateRegistration = "111222333444", TaxRegime = 3,
            Street = "Rua das Industrias", Number = "10", District = "Distrito", City = "Embu das Artes", CityIbgeCode = "3515004", Uf = "SP", ZipCode = "06800000", Phone = "1144444444"
        };
        (await admin.Put("/api/fiscal/settings", next)).EnsureSuccessStatusCode();
    }

    private static async Task<decimal> Balance(HttpClient c, int productId, int locationId) =>
        (await (await c.GetAsync($"/api/stock/balances?productId={productId}&locationId={locationId}")).Read<Page<StockBalanceOut>>()).Items.Sum(b => b.Quantity);

    private sealed record Setup(CustomerOut Customer, ProductOut Tube, StockLocationOut Shipping, StockLocationOut Returns, SalesOrderOut Order);

    /// <summary>A released order of 10 tubes (price list 100); the customer lives in <paramref name="uf"/>. 30 tubes in the shipping location.</summary>
    private async Task<Setup> ReleasedSaleAsync(HttpClient admin, string uf = "SP", decimal? monthlyPrice = 110m)
    {
        var customer = await (await admin.Post("/api/customers", new CustomerIn("Cliente " + Code("C"), null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var sp = uf == "SP";
        var address = await (await admin.Post($"/api/customers/{customer.Id}/addresses", new CustomerAddressIn("26133636000103", uf, null, "148061942112", true, "Av. Brasil", "100", null, "Centro", sp ? "Embu" : "Rio de Janeiro",
            sp ? "3515004" : "3304557", sp ? "06800000" : "20000000", sp ? "5101" : "6101", "Edilto", "compras@cliente.com", null))).Read<CustomerAddressOut>();
        var tube = await (await admin.Post("/api/products", Tube(Code("T")))).Read<ProductOut>();
        var shipping = await (await admin.Post("/api/stock-locations", new StockLocationIn(Code("E", 10), "Expedição", StockLocationKind.Internal))).Read<StockLocationOut>();
        var returns = await (await admin.Post("/api/stock-locations", new StockLocationIn(Code("D", 10), "Devoluções", StockLocationKind.Internal))).Read<StockLocationOut>();
        (await admin.Put("/api/sales/settings", new SalesSettingsDto(5m, 15, 0m, shipping.Id, null))).EnsureSuccessStatusCode();
        (await admin.Post("/api/stock/documents", new StockPost(MovementType.AdjustmentIn, Today, [new StockLine(null, tube.Id, shipping.Id, 30m, UnitCost: 5m)], "INV"))).EnsureSuccessStatusCode();
        var term = await (await admin.Post("/api/sales/payment-terms", new PaymentTermIn(Code("P", 8), "28 DDL", "28", 1_000_000m))).Read<PaymentTermOut>();
        (await admin.Post("/api/sales/price-list", new PriceListIn(tube.Id, null, 100m, 5m, 18m, Today.AddDays(-1), null))).EnsureSuccessStatusCode();
        if (!sp)
            (await admin.Put("/api/fiscal/cfops/6101", new CfopIn("6101", "Venda de produção do estabelecimento", FiscalKind.Sale, true, "00", "50", "01", "01", 0.65m, 3m, null, true))).EnsureSuccessStatusCode();
        if (monthlyPrice is { } mp)
            (await admin.Post("/api/fiscal/monthly-prices", new MonthlyPriceIn(tube.Id, customer.Id, sp ? "5101" : "6101", Today.Year, Today.Month, mp))).EnsureSuccessStatusCode();
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(customer.Id, address.Id, [new SalesLineInput(tube.Id, 10m)], "PO-9", term.Id))).Read<SalesOrderOut>();
        await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn());
        return new Setup(customer, tube, shipping, returns, order);
    }

    private static async Task<(DeliveryOut Delivery, FiscalDocumentOut Nf)> ShipAsync(HttpClient admin, Setup s, ShipInput? ship = null, string? notes = null)
    {
        var d = await (await admin.Post($"/api/sales/orders/{s.Order.Id}/deliveries", new DeliveryInput(Today, Notes: notes))).Read<DeliveryOut>();
        var shipped = await (await admin.Post($"/api/sales/deliveries/{d.Id}/ship", ship ?? new ShipInput(Today, WithoutCertificate: true))).Read<DeliveryOut>();
        var summary = Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?deliveryId={d.Id}")).Read<Page<FiscalDocumentSummary>>()).Items);
        return (shipped, await (await admin.GetAsync($"/api/fiscal/documents/{summary.Id}")).Read<FiscalDocumentOut>());
    }

    private static Task<HttpResponseMessage> Return(HttpClient c, int nfId, int itemId, decimal quantity, int locationId, string? reason = "Cliente devolveu por medida errada") =>
        c.Post($"/api/fiscal/documents/{nfId}/return", new ReturnInput([new ReturnLineInput(itemId, quantity)], locationId, reason));

    [Fact]
    public async Task Order_price_is_the_default_and_the_monthly_price_only_overrides_it()
    {
        var admin = await api.AdminAsync();
        var s = await ReleasedSaleAsync(admin, monthlyPrice: null);
        try
        {
            await Enable(admin, true);
            var (_, nf) = await ShipAsync(admin, s);
            Assert.Equal(FiscalStatus.Authorized, nf.Status);
            Assert.Equal(Assert.Single(s.Order.Lines).UnitPrice, Assert.Single(nf.Lines).UnitPrice);
            Assert.Null(nf.Warnings);
        }
        finally { await Enable(admin, false); }
    }

    [Fact]
    public async Task Transport_group_carries_net_and_gross_weight_the_carrier_registry_and_the_plate_uf()
    {
        var admin = await api.AdminAsync();
        var s = await ReleasedSaleAsync(admin);
        var carrierName = "Transportes " + Code("X", 6);
        (await admin.Post("/api/fiscal/carriers", new FiscalCarrierIn(carrierName, "04252011000110", "110042490114", "Rua do Frete 9", "Belo Horizonte", "MG", null))).EnsureSuccessStatusCode();
        try
        {
            await Enable(admin, true);
            var (_, nf) = await ShipAsync(admin, s, new ShipInput(Today, Carrier: carrierName.ToUpperInvariant(), VehiclePlate: "abc1d23", GrossWeightKg: 400m, WithoutCertificate: true));
            var xml = await (await admin.GetAsync($"/api/fiscal/documents/{nf.Id}/xml")).Content.ReadAsStringAsync();
            var net = Math.Round(s.Tube.NetWeightKg!.Value * 10m, 3);
            Assert.Contains($"<pesoL>{net.ToString("0.000", System.Globalization.CultureInfo.InvariantCulture)}</pesoL><pesoB>400.000</pesoB>", xml);
            Assert.Contains("<transporta><CNPJ>04252011000110</CNPJ>", xml);
            Assert.Contains("<IE>110042490114</IE><xEnder>Rua do Frete 9</xEnder><xMun>Belo Horizonte</xMun><UF>MG</UF></transporta>", xml);
            Assert.Contains("<veicTransp><placa>ABC1D23</placa><UF>MG</UF></veicTransp>", xml);   // the carrier's UF, not the issuer's SP
        }
        finally { await Enable(admin, false); }
    }

    [Fact]
    public async Task Return_nf_sends_goods_back_to_stock_limited_to_the_balance_and_can_be_cancelled()
    {
        var admin = await api.AdminAsync();
        var s = await ReleasedSaleAsync(admin);
        try
        {
            await Enable(admin, true);
            var (delivery, nf) = await ShipAsync(admin, s);
            var line = Assert.Single(nf.Lines);
            Assert.Equal(20m, await Balance(admin, s.Tube.Id, s.Shipping.Id));

            // Validation.
            Assert.Equal(HttpStatusCode.BadRequest, (await Return(admin, nf.Id, line.Id, 11m, s.Returns.Id)).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await Return(admin, nf.Id, line.Id, 0m, s.Returns.Id)).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await Return(admin, nf.Id, line.Id + 9999, 1m, s.Returns.Id)).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await Return(admin, nf.Id, line.Id, 1m, s.Returns.Id, reason: " ")).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await Return(admin, nf.Id, line.Id, 1m, 999999)).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post($"/api/fiscal/documents/{nf.Id}/return", new ReturnInput([], s.Returns.Id, "motivo qualquer"))).StatusCode);
            Assert.Equal(HttpStatusCode.NotFound, (await Return(admin, 999999, line.Id, 1m, s.Returns.Id)).StatusCode);

            // Partial return: 4 of 10 come back to the chosen location.
            var first = await (await Return(admin, nf.Id, line.Id, 4m, s.Returns.Id)).Read<FiscalDocumentOut>();
            Assert.Equal(FiscalKind.Return, first.Kind);
            Assert.Equal(FiscalStatus.Authorized, first.Status);
            Assert.Equal("1202", first.CfopCode);
            Assert.Equal(nf.Id, first.ReferencedDocumentId);
            Assert.Equal(nf.Number, first.ReferencedNumber);
            Assert.Equal(nf.AccessKey, first.ReferencedAccessKey);
            var back = Assert.Single(first.Lines);
            Assert.Equal(4m, back.Quantity);
            Assert.Equal(line.UnitPrice, back.UnitPrice);
            Assert.Equal(line.Id, back.ReferencedLineId);
            Assert.Equal(0.4m * nf.ProductsTotal, first.ProductsTotal);
            Assert.Equal(0.4m * nf.IcmsTotal, first.IcmsTotal);
            Assert.Equal(0.4m * nf.IpiTotal, first.IpiTotal);
            Assert.Equal("00", back.IpiCst);                                   // sale CST 50 becomes the entry CST 00
            Assert.Empty(first.Installments);
            Assert.Contains($"Devolução ref. NF {nf.Number}", first.AdditionalInfo);
            Assert.Equal(24m, await Balance(admin, s.Tube.Id, s.Shipping.Id) + await Balance(admin, s.Tube.Id, s.Returns.Id));
            Assert.Equal(4m, await Balance(admin, s.Tube.Id, s.Returns.Id));

            var xml = await (await admin.GetAsync($"/api/fiscal/documents/{first.Id}/xml")).Content.ReadAsStringAsync();
            Assert.Contains("<tpNF>0</tpNF>", xml);
            Assert.Contains("<finNFe>4</finNFe>", xml);
            Assert.Contains($"<NFref><refNFe>{nf.AccessKey}</refNFe></NFref>", xml);
            Assert.Contains("<CFOP>1202</CFOP>", xml);
            Assert.Contains("<idDest>1</idDest>", xml);

            // The original shows what was returned, the return is linked both ways, the delivery history says so.
            var again = await (await admin.GetAsync($"/api/fiscal/documents/{nf.Id}")).Read<FiscalDocumentOut>();
            Assert.Equal(4m, Assert.Single(again.Lines).ReturnedQuantity);
            Assert.Equal(first.Id, Assert.Single(again.Returns!).Id);
            var history = (await (await admin.GetAsync($"/api/sales/deliveries/{delivery.Id}")).Read<DeliveryOut>()).History;
            Assert.Contains(history, h => h.Action == "nf-return" && h.Note!.Contains($"NF {nf.Number}"));

            // Only the balance can still come back; the original cannot be cancelled while a return NF lives.
            Assert.Equal(HttpStatusCode.BadRequest, (await Return(admin, nf.Id, line.Id, 7m, s.Returns.Id)).StatusCode);
            var cancelOriginal = await admin.Post($"/api/fiscal/documents/{nf.Id}/cancel", new CancelInvoiceIn("Erro de digitação no pedido do cliente", ApiFixture.AdminPassword));
            Assert.Equal(HttpStatusCode.Conflict, cancelOriginal.StatusCode);
            Assert.Contains("return NF", await cancelOriginal.Content.ReadAsStringAsync());

            var second = await (await Return(admin, nf.Id, line.Id, 6m, s.Returns.Id)).Read<FiscalDocumentOut>();
            Assert.Equal(nf.ProductsTotal, first.ProductsTotal + second.ProductsTotal);
            Assert.Equal(nf.InvoiceTotal, first.InvoiceTotal + second.InvoiceTotal);
            Assert.Equal(HttpStatusCode.BadRequest, (await Return(admin, nf.Id, line.Id, 1m, s.Returns.Id)).StatusCode);
            Assert.Equal(10m, await Balance(admin, s.Tube.Id, s.Returns.Id));

            // Cancelling a return NF takes the goods out of stock again and frees the balance.
            var cancelled = await (await admin.Post($"/api/fiscal/documents/{second.Id}/cancel", new CancelInvoiceIn("Devolução lançada por engano no sistema", ApiFixture.AdminPassword))).Read<FiscalDocumentOut>();
            Assert.Equal(FiscalStatus.Cancelled, cancelled.Status);
            Assert.Equal(4m, await Balance(admin, s.Tube.Id, s.Returns.Id));
            Assert.Equal(4m, Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents/{nf.Id}")).Read<FiscalDocumentOut>()).Lines).ReturnedQuantity);
            (await Return(admin, nf.Id, line.Id, 6m, s.Returns.Id)).EnsureSuccessStatusCode();

            // A return NF is not itself returnable, and a cancelled NF cannot be returned.
            Assert.Equal(HttpStatusCode.Conflict, (await Return(admin, first.Id, back.Id, 1m, s.Returns.Id)).StatusCode);
            Assert.Equal(HttpStatusCode.Conflict, (await Return(admin, second.Id, second.Lines[0].Id, 1m, s.Returns.Id)).StatusCode);
        }
        finally { await Enable(admin, false); }
    }

    [Fact]
    public async Task Return_of_an_interstate_sale_uses_cfop_2202_and_needs_fiscal_emit()
    {
        var admin = await api.AdminAsync();
        var stock = await api.UserAsync(UserRole.Stock);
        var s = await ReleasedSaleAsync(admin, "RJ");
        try
        {
            await Enable(admin, true);
            var (_, nf) = await ShipAsync(admin, s);
            Assert.Equal("6101", nf.CfopCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await Return(stock, nf.Id, nf.Lines[0].Id, 1m, s.Returns.Id)).StatusCode);
            var ret = await (await Return(admin, nf.Id, nf.Lines[0].Id, 10m, s.Returns.Id)).Read<FiscalDocumentOut>();
            Assert.Equal("2202", ret.CfopCode);
            var xml = await (await admin.GetAsync($"/api/fiscal/documents/{ret.Id}/xml")).Content.ReadAsStringAsync();
            Assert.Contains("<idDest>2</idDest>", xml);
            Assert.Contains("<natOp>Devolução de venda de produção do estabelecimento</natOp>", xml);
        }
        finally { await Enable(admin, false); }
    }

    [Fact]
    public async Task Return_is_refused_when_sefaz_rejects_it_and_stock_stays_untouched()
    {
        var admin = await api.AdminAsync();
        var s = await ReleasedSaleAsync(admin);
        try
        {
            await Enable(admin, true);
            var (_, nf) = await ShipAsync(admin, s);
            var res = await Return(admin, nf.Id, nf.Lines[0].Id, 2m, s.Returns.Id, reason: $"Devolução {StubSefazClient.RejectMarker}");
            Assert.Equal(HttpStatusCode.UnprocessableEntity, res.StatusCode);
            Assert.Contains("SEFAZ rejected", await res.Content.ReadAsStringAsync());
            Assert.Equal(0m, await Balance(admin, s.Tube.Id, s.Returns.Id));
            Assert.Empty((await (await admin.GetAsync($"/api/fiscal/documents?kind={FiscalKind.Return}&q={s.Customer.Name}")).Read<Page<FiscalDocumentSummary>>()).Items);
        }
        finally { await Enable(admin, false); }
    }

    [Fact]
    public async Task Correction_letter_is_sequenced_validated_and_listed()
    {
        var admin = await api.AdminAsync();
        var s = await ReleasedSaleAsync(admin);
        try
        {
            await Enable(admin, true);
            var (_, nf) = await ShipAsync(admin, s);
            Task<HttpResponseMessage> Cce(string? text) => admin.Post($"/api/fiscal/documents/{nf.Id}/correction", new CorrectionIn(text));

            Assert.Equal(HttpStatusCode.BadRequest, (await Cce("curto")).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await Cce(null)).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await Cce(new string('x', 1001))).StatusCode);
            Assert.Equal(HttpStatusCode.NotFound, (await admin.Post("/api/fiscal/documents/999999/correction", new CorrectionIn("Correção de endereço de entrega do cliente"))).StatusCode);
            Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Cce($"Dados de transporte corrigidos {StubSefazClient.RejectMarker}")).StatusCode);
            Assert.Empty((await (await admin.GetAsync($"/api/fiscal/documents/{nf.Id}")).Read<FiscalDocumentOut>()).Events!);

            var one = await (await Cce("Onde se le  transportadora X\nleia transportadora Y")).Read<FiscalDocumentOut>();
            var two = await (await Cce("Onde se le placa AAA0A00 leia placa BBB1B11")).Read<FiscalDocumentOut>();
            Assert.Equal([1, 2], two.Events!.Select(e => e.Sequence).ToArray());
            Assert.Equal("Onde se le transportadora X leia transportadora Y", one.Events![0].Text);   // whitespace collapsed
            Assert.All(two.Events!, e => { Assert.Equal("110110", e.EventType); Assert.NotEmpty(e.Protocol); Assert.True(e.Simulated); });

            // 20 is the limit.
            await using (var db = api.NewDb())
            {
                for (var n = 3; n <= 20; n++)
                    db.FiscalEvents.Add(new FiscalEvent { DocumentId = nf.Id, EventType = "110110", Sequence = n, Text = "x", Protocol = "135", Environment = SefazEnvironment.Homologation, CreatedAt = DateTimeOffset.UtcNow });
                await db.SaveChangesAsync();
            }
            var over = await Cce("Mais uma correção de dados adicionais");
            Assert.Equal(HttpStatusCode.Conflict, over.StatusCode);
            Assert.Contains("20 corrections", await over.Content.ReadAsStringAsync());

            // Only authorized NFs take a CC-e.
            (await admin.Post($"/api/fiscal/documents/{nf.Id}/cancel", new CancelInvoiceIn("Erro de digitação no pedido do cliente", ApiFixture.AdminPassword))).EnsureSuccessStatusCode();
            Assert.Equal(HttpStatusCode.Conflict, (await Cce("Correção depois do cancelamento da NF")).StatusCode);
        }
        finally { await Enable(admin, false); }
    }

    [Fact]
    public async Task Duplicity_answer_keeps_the_number_and_flags_the_document_for_a_key_lookup()
    {
        var admin = await api.AdminAsync();
        var s = await ReleasedSaleAsync(admin);
        try
        {
            await Enable(admin, true);
            var n = (await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>()).NextNumber;
            var d = await (await admin.Post($"/api/sales/orders/{s.Order.Id}/deliveries", new DeliveryInput(Today, Notes: StubSefazClient.DuplicateMarker))).Read<DeliveryOut>();
            var res = await admin.Post($"/api/sales/deliveries/{d.Id}/ship", new ShipInput(Today, WithoutCertificate: true));
            Assert.Equal(HttpStatusCode.UnprocessableEntity, res.StatusCode);
            Assert.Contains("consult the access key", await res.Content.ReadAsStringAsync());

            // Delivery and stock rolled back, but the number was NOT given back and the document waits for the lookup.
            Assert.Equal(DeliveryStatus.Planned, (await (await admin.GetAsync($"/api/sales/deliveries/{d.Id}")).Read<DeliveryOut>()).Status);
            Assert.Equal(n + 1, (await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>()).NextNumber);
            var pending = Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?status={FiscalStatus.Pending}&q={n}")).Read<Page<FiscalDocumentSummary>>()).Items);
            var doc = await (await admin.GetAsync($"/api/fiscal/documents/{pending.Id}")).Read<FiscalDocumentOut>();
            Assert.True(doc.KeyLookupRequired);
            Assert.Contains("204", doc.StatusMessage);

            // SEFAZ does not know the key: still the number is not reusable, the row ends Rejected (inutilização candidate or a next-number fix).
            var r = await (await admin.Post($"/api/fiscal/documents/{pending.Id}/reconcile?minAgeMinutes=0", new { })).Read<ReconcileResult>();
            Assert.Equal("rejected", r.Outcome);
            Assert.Equal(FiscalStatus.Rejected, r.Status);
            Assert.Equal(n + 1, (await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>()).NextNumber);
            (await admin.Post($"/api/sales/deliveries/{d.Id}/cancel", new SalesReasonIn("teste"))).EnsureSuccessStatusCode();
        }
        finally { await Enable(admin, false); }
    }

    [Fact]
    public async Task Two_live_nfs_for_one_delivery_are_impossible_in_the_database()
    {
        var admin = await api.AdminAsync();
        var s = await ReleasedSaleAsync(admin);
        try
        {
            await Enable(admin, true);
            var (delivery, nf) = await ShipAsync(admin, s);
            FiscalDocument Another(FiscalStatus status, int number) => new()
            {
                Kind = FiscalKind.Sale, Status = status, CfopCode = "5101", Series = 77, Number = number, AccessKey = $"3526{number:D40}", Protocol = "", RecipientName = "X", RecipientDocument = "26133636000103", RecipientUf = "SP",
                IssuedAt = DateTimeOffset.UtcNow, Xml = "<x/>", DeliveryId = delivery.Id, Simulated = true // real ones would block the data reset tests that share this database
            };
            await using (var db = api.NewDb())
            {
                db.FiscalDocuments.Add(Another(FiscalStatus.Authorized, 1));
                await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
            }
            await using (var db = api.NewDb())
            {
                db.FiscalDocuments.Add(Another(FiscalStatus.Pending, 2));
                await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
            }
            // Rejected and cancelled ones do not count.
            await using (var db = api.NewDb())
            {
                db.FiscalDocuments.Add(Another(FiscalStatus.Rejected, 3));
                db.FiscalDocuments.Add(Another(FiscalStatus.Cancelled, 4));
                await db.SaveChangesAsync();
            }
            Assert.Equal(FiscalStatus.Authorized, (await (await admin.GetAsync($"/api/fiscal/documents/{nf.Id}")).Read<FiscalDocumentOut>()).Status);
        }
        finally { await Enable(admin, false); }
    }

    [Fact]
    public async Task Scheduled_reconciliation_resolves_old_pending_nfs_and_leaves_young_ones()
    {
        var admin = await api.AdminAsync();
        var s = await ReleasedSaleAsync(admin);
        try
        {
            await Enable(admin, true);
            var n = (await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>()).NextNumber;
            var lost = await (await admin.Post($"/api/sales/orders/{s.Order.Id}/deliveries", new DeliveryInput(Today, Notes: StubSefazClient.TimeoutMarker))).Read<DeliveryOut>();
            Assert.Equal(HttpStatusCode.BadGateway, (await admin.Post($"/api/sales/deliveries/{lost.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).StatusCode);
            var pending = Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?status={FiscalStatus.Pending}&q={n}")).Read<Page<FiscalDocumentSummary>>()).Items);

            using var scope = api.CreateScope();
            var job = scope.ServiceProvider.GetServices<IHostedService>().OfType<FiscalReconcileService>().Single();

            // Younger than 5 minutes: the request may still be waiting for SEFAZ.
            var young = await job.RunOnceAsync(CancellationToken.None);
            Assert.Equal("waiting", Assert.Single(young, r => r.Id == pending.Id).Outcome);

            await using (var db = api.NewDb())
                await db.FiscalDocuments.Where(d => d.Id == pending.Id).ExecuteUpdateAsync(u => u.SetProperty(d => d.IssuedAt, DateTimeOffset.UtcNow.AddMinutes(-6)));
            var old = await job.RunOnceAsync(CancellationToken.None);
            Assert.Equal("released", Assert.Single(old, r => r.Id == pending.Id).Outcome);
            Assert.Equal(n, (await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>()).NextNumber);
            (await admin.Post($"/api/sales/deliveries/{lost.Id}/cancel", new SalesReasonIn("teste"))).EnsureSuccessStatusCode();
        }
        finally { await Enable(admin, false); }
    }

    [Fact]
    public async Task Carrier_registry_is_validated_and_guarded_by_fiscal_emit()
    {
        var admin = await api.AdminAsync();
        var stock = await api.UserAsync(UserRole.Stock);
        Assert.Equal(HttpStatusCode.Forbidden, (await stock.Post("/api/fiscal/carriers", new FiscalCarrierIn("Transp", null, null, null, null, null, null))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post("/api/fiscal/carriers", new FiscalCarrierIn("", null, null, null, null, null, null))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post("/api/fiscal/carriers", new FiscalCarrierIn("Transp " + Code("Z", 5), "123", null, null, null, null, null))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post("/api/fiscal/carriers", new FiscalCarrierIn("Transp " + Code("Z", 5), null, null, null, null, "XX", null))).StatusCode);
        var ok = await (await admin.Post("/api/fiscal/carriers", new FiscalCarrierIn("Transp " + Code("Z", 5), "04.252.011/0001-10", null, null, null, "mg", "SP"))).Read<FiscalCarrierOut>();
        Assert.Equal("04252011000110", ok.Document);
        Assert.Equal("MG", ok.Uf);
    }

    [Fact]
    public void Ipi_cst_of_an_entry_mirrors_the_sale_cst()
    {
        Assert.Equal("00", FiscalService.ReturnIpiCst("50"));
        Assert.Equal("49", FiscalService.ReturnIpiCst("99"));
        Assert.Equal("05", FiscalService.ReturnIpiCst("55"));
        Assert.Equal("00", FiscalService.ReturnIpiCst("00"));
    }
}
