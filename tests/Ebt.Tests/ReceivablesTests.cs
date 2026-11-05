using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Receivables;
using Ebt.Core.Sales;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Tests;

/// <summary>Contas a receber: duplicatas of authorized NFs, baixa and estorno, aging, the cancelled-NF rule and the credit exposure.</summary>
[Collection("api")]
public class ReceivablesTests(ApiFixture api)
{
    private static DateOnly Today => Clock.Today();

    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();

    private sealed record Sale(CustomerOut Customer, CustomerAddressOut Address, ProductOut Tube, PaymentTermOut Term, FiscalDocumentOut Nf);

    private static async Task SetFiscal(HttpClient admin, bool enabled)
    {
        var s = await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>();
        (await admin.Put("/api/fiscal/settings", s with
        {
            Enabled = enabled, Environment = SefazEnvironment.Homologation, CompanyName = "EBT Tubos Ltda", TradeName = "EBT", Cnpj = "11222333000181", StateRegistration = "111222333444", TaxRegime = 3,
            Street = "Rua das Industrias", Number = "10", District = "Distrito", City = "Embu das Artes", CityIbgeCode = "3515004", Uf = "SP", ZipCode = "06800000", Phone = "1144444444"
        })).EnsureSuccessStatusCode();
    }

    /// <summary>A customer with a shipped delivery whose NF carries two duplicatas (15 and 30 days). Fiscal emission is left on; the caller turns it off.</summary>
    private async Task<Sale> ShippedWithNfAsync(HttpClient admin, string days = "15/30")
    {
        var customer = await (await admin.Post("/api/customers", new CustomerIn("Cliente " + Code("C"), null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var address = await (await admin.Post($"/api/customers/{customer.Id}/addresses", new CustomerAddressIn("26133636000103", "SP", null, "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", "3515004", "06800000", "5101", "Edilto", "compras@cliente.com", null))).Read<CustomerAddressOut>();
        var tube = await (await admin.Post("/api/products", new ProductIn(Code("T"), "Tubo", ProductKind.Part, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, null, null, "73063010", "PC", 50, false, null, null))).Read<ProductOut>();
        var shipping = await (await admin.Post("/api/stock-locations", new StockLocationIn(Code("E", 10), "Expedição", StockLocationKind.Internal))).Read<StockLocationOut>();
        (await admin.Put("/api/sales/settings", new SalesSettingsDto(5m, 15, 0m, shipping.Id, null))).EnsureSuccessStatusCode();
        (await admin.Post("/api/stock/documents", new Ebt.Core.Inventory.StockPost(MovementType.AdjustmentIn, Today, [new Ebt.Core.Inventory.StockLine(null, tube.Id, shipping.Id, 50m, UnitCost: 5m)], "INV"))).EnsureSuccessStatusCode();
        var term = await (await admin.Post("/api/sales/payment-terms", new PaymentTermIn(Code("P", 8), days, days, 1_000_000m))).Read<PaymentTermOut>();
        (await admin.Post("/api/sales/price-list", new PriceListIn(tube.Id, null, 100m, 5m, 18m, Today.AddDays(-1), null))).EnsureSuccessStatusCode();
        (await admin.Post("/api/fiscal/monthly-prices", new MonthlyPriceIn(tube.Id, customer.Id, "5101", Today.Year, Today.Month, 110m))).EnsureSuccessStatusCode();
        await SetFiscal(admin, true);
        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(customer.Id, address.Id, [new SalesLineInput(tube.Id, 10m)], "PO-9", term.Id))).Read<SalesOrderOut>();
        (await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn())).EnsureSuccessStatusCode();
        var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, WithoutCertificate: true))).EnsureSuccessStatusCode();
        var doc = Assert.Single((await (await admin.GetAsync($"/api/fiscal/documents?deliveryId={delivery.Id}")).Read<Page<FiscalDocumentSummary>>()).Items);
        var nf = await (await admin.GetAsync($"/api/fiscal/documents/{doc.Id}")).Read<FiscalDocumentOut>();
        return new Sale(customer, address, tube, term, nf);
    }

    private static async Task<List<ReceivableOut>> RowsAsync(HttpClient c, int customerId, string extra = "") =>
        (await (await c.GetAsync($"/api/receivables?customerId={customerId}{extra}")).Read<Page<ReceivableOut>>()).Items.ToList();

    [Fact]
    public async Task Duplicatas_take_partial_payments_reversals_and_follow_the_nf_status()
    {
        var admin = await api.AdminAsync();
        var reader = await api.UserAsync(UserRole.Reader);
        try
        {
            var s = await ShippedWithNfAsync(admin);
            var total = s.Nf.InvoiceTotal;
            var rows = await RowsAsync(admin, s.Customer.Id);
            Assert.Equal(2, rows.Count);
            Assert.All(rows, r => Assert.Equal(ReceivableStatus.Open, r.Status));
            Assert.Equal(total, rows.Sum(r => r.Balance));
            var first = rows[0];

            // Posting rules: positive amount, no future date, never above the balance, a role with the policy.
            Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post($"/api/receivables/installments/{first.Id}/payments", new ReceivablePaymentIn(null, 0m, null, null))).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post($"/api/receivables/installments/{first.Id}/payments", new ReceivablePaymentIn(Today.AddDays(1), 10m, null, null))).StatusCode);
            Assert.Equal(HttpStatusCode.Conflict, (await admin.Post($"/api/receivables/installments/{first.Id}/payments", new ReceivablePaymentIn(null, first.Amount + 0.01m, null, null))).StatusCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await reader.Post($"/api/receivables/installments/{first.Id}/payments", new ReceivablePaymentIn(null, 10m, null, null))).StatusCode);
            Assert.Equal(HttpStatusCode.OK, (await reader.GetAsync($"/api/receivables?customerId={s.Customer.Id}")).StatusCode);

            // Partial payment, then the rest.
            var part = await (await admin.Post($"/api/receivables/installments/{first.Id}/payments", new ReceivablePaymentIn(null, 100m, "PIX", "sinal"))).Read<ReceivablePaymentOut>();
            Assert.Equal("PIX", part.Method);
            Assert.Equal("admin", part.CreatedBy);
            var after = (await RowsAsync(admin, s.Customer.Id))[0];
            Assert.Equal((100m, first.Amount - 100m, ReceivableStatus.Partial), (after.Paid, after.Balance, after.Status));
            var balance = Assert.Single(await (await admin.GetAsync($"/api/receivables/balances?customerId={s.Customer.Id}")).Read<List<CustomerBalance>>());
            Assert.Equal((total - 100m, 0m), (balance.Open, balance.Overdue));

            var aging = await (await admin.GetAsync($"/api/receivables/aging?customerId={s.Customer.Id}")).Read<List<AgingRow>>();
            var sum = Assert.Single(aging, a => a.CustomerId is null);
            Assert.Equal((total - 100m, total - 100m), (sum.NotDue, sum.Total));

            // Estorno needs a reason, happens once, keeps the row and is audited.
            Assert.Equal(HttpStatusCode.BadRequest, (await admin.DeleteAsync($"/api/receivables/payments/{part.Id}")).StatusCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await reader.DeleteAsync($"/api/receivables/payments/{part.Id}?reason=teste")).StatusCode);
            Assert.Equal(HttpStatusCode.NoContent, (await admin.DeleteAsync($"/api/receivables/payments/{part.Id}?reason=Pagamento%20lan%C3%A7ado%20errado")).StatusCode);
            Assert.Equal(HttpStatusCode.Conflict, (await admin.DeleteAsync($"/api/receivables/payments/{part.Id}?reason=de%20novo")).StatusCode);
            Assert.Equal(ReceivableStatus.Open, (await RowsAsync(admin, s.Customer.Id))[0].Status);
            var listed = Assert.Single(await (await admin.GetAsync($"/api/receivables/installments/{first.Id}/payments")).Read<List<ReceivablePaymentOut>>());
            Assert.NotNull(listed.ReversedAt);
            Assert.Equal("Pagamento lançado errado", listed.ReverseReason);
            var audit = (await (await admin.GetAsync($"/api/audit?entity=ReceivablePayment&entityId={part.Id}")).Read<Page<AuditOut>>()).Items;
            Assert.Contains(audit, a => a.Action == "Insert");
            Assert.Contains(audit, a => a.Action == "Update" && a.Changes.Contains("ReversedAt"));

            // Paid in full leaves the open list.
            (await admin.Post($"/api/receivables/installments/{first.Id}/payments", new ReceivablePaymentIn(Today.AddDays(-1), first.Amount, null, null))).EnsureSuccessStatusCode();
            Assert.Equal(ReceivableStatus.Paid, (await RowsAsync(admin, s.Customer.Id))[0].Status);
            Assert.Single(await RowsAsync(admin, s.Customer.Id, "&status=pending"));
            Assert.Single(await RowsAsync(admin, s.Customer.Id, "&status=paid"));
            Assert.Equal(HttpStatusCode.BadRequest, (await admin.GetAsync("/api/receivables?status=nope")).StatusCode);

            // Past due moves the balance through the aging buckets and the status turns Overdue.
            var second = (await RowsAsync(admin, s.Customer.Id))[1];
            await using (var db = api.NewDb())
                await db.FiscalInstallments.Where(i => i.Id == second.Id).ExecuteUpdateAsync(x => x.SetProperty(i => i.DueDate, Today.AddDays(-45)));
            var late = Assert.Single(await RowsAsync(admin, s.Customer.Id, "&overdue=true"));
            Assert.Equal((ReceivableStatus.Overdue, 45), (late.Status, late.DaysOverdue));
            var lateAging = Assert.Single(await (await admin.GetAsync($"/api/receivables/aging?customerId={s.Customer.Id}")).Read<List<AgingRow>>(), a => a.CustomerId is null);
            Assert.Equal((second.Amount, 0m), (lateAging.Days31To60, lateAging.NotDue));
            var lateBalance = Assert.Single(await (await admin.GetAsync($"/api/receivables/balances?customerId={s.Customer.Id}")).Read<List<CustomerBalance>>());
            Assert.Equal(second.Amount, lateBalance.Overdue);

            // Cancelling the NF stops the balance at once and blocks new payments.
            (await admin.Post($"/api/fiscal/documents/{s.Nf.Id}/cancel", new CancelInvoiceIn("Erro de digitação no pedido do cliente", ApiFixture.AdminPassword))).EnsureSuccessStatusCode();
            Assert.All(await RowsAsync(admin, s.Customer.Id, "&status=cancelled"), r => Assert.Equal((0m, ReceivableStatus.Cancelled), (r.Balance, r.Status)));
            Assert.Empty(await (await admin.GetAsync($"/api/receivables/balances?customerId={s.Customer.Id}")).Read<List<CustomerBalance>>());
            Assert.Equal(HttpStatusCode.Conflict, (await admin.Post($"/api/receivables/installments/{second.Id}/payments", new ReceivablePaymentIn(null, 10m, null, null))).StatusCode);
        }
        finally { await SetFiscal(admin, false); }
    }

    [Fact]
    public async Task Two_simultaneous_estornos_of_the_same_payment_only_succeed_once()
    {
        var admin = await api.AdminAsync();
        try
        {
            var s = await ShippedWithNfAsync(admin);
            var first = (await RowsAsync(admin, s.Customer.Id))[0];
            var payment = await (await admin.Post($"/api/receivables/installments/{first.Id}/payments", new ReceivablePaymentIn(null, 50m, "PIX", null))).Read<ReceivablePaymentOut>();
            var both = await Task.WhenAll(admin.DeleteAsync($"/api/receivables/payments/{payment.Id}?reason=primeiro"), admin.DeleteAsync($"/api/receivables/payments/{payment.Id}?reason=segundo"));
            Assert.Single(both, r => r.StatusCode == HttpStatusCode.NoContent);
            Assert.Single(both, r => r.StatusCode == HttpStatusCode.Conflict);
            var listed = Assert.Single(await (await admin.GetAsync($"/api/receivables/installments/{first.Id}/payments")).Read<List<ReceivablePaymentOut>>());
            Assert.Contains(listed.ReverseReason, new[] { "primeiro", "segundo" });
        }
        finally { await SetFiscal(admin, false); }
    }

    [Fact]
    public async Task Open_receivables_count_in_the_credit_exposure_until_they_are_paid()
    {
        var admin = await api.AdminAsync();
        try
        {
            var s = await ShippedWithNfAsync(admin, "30");
            var owed = s.Nf.InvoiceTotal;
            // Room for 100 beyond what is already owed; the next order is worth 1,050 (10 x 100 + 5% IPI).
            await using (var db = api.NewDb())
                await db.Customers.Where(c => c.Id == s.Customer.Id).ExecuteUpdateAsync(x => x.SetProperty(c => c.CreditLimit, owed + 100m));
            var input = new SalesOrderIn(s.Customer.Id, s.Address.Id, [new SalesLineInput(s.Tube.Id, 10m)], "PO-10", s.Term.Id);

            var blocked = await admin.Post("/api/sales/orders", input);
            Assert.Equal(HttpStatusCode.Conflict, blocked.StatusCode);
            var message = await blocked.Content.ReadAsStringAsync();
            Assert.Contains($"open orders {0m:0.00}", message);
            Assert.Contains($"receivable {owed:0.00}", message);
            Assert.Contains($"this order {1050m:0.00}", message);

            var forced = await (await admin.Post("/api/sales/orders", input with { OverrideCredit = true })).Read<SalesOrderOut>();
            Assert.Equal(owed, forced.Credit.Receivable);
            Assert.True(forced.Credit.Exceeded);

            // Paying the duplicata frees the limit (the forced order itself still counts as open).
            var duplicata = Assert.Single(await RowsAsync(admin, s.Customer.Id));
            (await admin.Post($"/api/receivables/installments/{duplicata.Id}/payments", new ReceivablePaymentIn(null, duplicata.Amount, "boleto", null))).EnsureSuccessStatusCode();
            var cleared = await (await admin.GetAsync($"/api/sales/orders/{forced.Id}")).Read<SalesOrderOut>();
            Assert.Equal(0m, cleared.Credit.Receivable);
            Assert.False(cleared.Credit.Exceeded);
        }
        finally { await SetFiscal(admin, false); }
    }
}
