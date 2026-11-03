using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Core.Entities;
using Ebt.Core.Purchasing;

namespace Ebt.Tests;

/// <summary>Validation, conflict and not-found branches of PurchasingService.</summary>
[Collection("purchasing")]
public class PurchasingEdgeTests(PurchasingFixture api)
{
    private static readonly DateOnly Today = Ebt.Core.Services.Clock.Today();

    private static string Code(string prefix) => $"{prefix}{Guid.NewGuid():N}"[..12].ToUpper();

    private static async Task<SupplierOut> Supplier(HttpClient c, bool active = true)
    {
        var s = await (await c.Post("/api/suppliers", new SupplierIn("Forn " + Code("X"), null, Code("F"), null))).Read<SupplierOut>();
        if (!active) (await c.Put($"/api/suppliers/{s.Id}", new SupplierIn(s.Name, null, null, null, Active: false))).EnsureSuccessStatusCode();
        return s;
    }

    private static async Task<MaterialOut> Coil(HttpClient c, bool purchased = true) =>
        await (await c.Post("/api/materials", new MaterialIn(Code("B"), "Bobina", null, null, null, "KG", "T", 1000m, 1.5m, 1200m, "72083990", 15, null, null, null, false, purchased, false))).Read<MaterialOut>();

    private static async Task<RequisitionOut> Approved(HttpClient c, int materialId, decimal qty = 2m)
    {
        var r = await (await c.Post("/api/requisitions", new RequisitionIn(materialId, null, null, qty, "PCP", Today.AddDays(20), null, null))).Read<RequisitionOut>();
        return await (await c.Post($"/api/requisitions/{r.Id}/approve", new RequisitionDecisionIn(null, null))).Read<RequisitionOut>();
    }

    private static OrderLineIn Line(int? materialId, decimal qty = 1m, decimal price = 10m, decimal discount = 0m, decimal icms = 0m, decimal ipi = 0m, string? desc = null, string? unit = null, DateOnly? due = null, params int[] reqs) =>
        new(materialId, desc, unit, qty, price, discount, icms, ipi, due ?? Today.AddDays(10), reqs);

    private static Task<HttpResponseMessage> Order(HttpClient c, int supplierId, params OrderLineIn[] lines) =>
        c.Post("/api/purchase-orders", new OrderIn(supplierId, "30", null, lines));

    private static async Task AssertStatus(HttpStatusCode expected, Task<HttpResponseMessage> call) => Assert.Equal(expected, (await call).StatusCode);

    [Fact]
    public async Task Requisition_validation_and_state_errors()
    {
        var c = await api.AdminAsync();
        var coil = await Coil(c);
        var notPurchased = await Coil(c, purchased: false);

        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/requisitions", new RequisitionIn(coil.Id, null, null, 0m, null, null, null, null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/requisitions", new RequisitionIn(999_999, null, null, 1m, null, null, null, null)));
        await AssertStatus(HttpStatusCode.Conflict, c.Post("/api/requisitions", new RequisitionIn(notPurchased.Id, null, null, 1m, null, null, null, null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/requisitions", new RequisitionIn(null, null, "KG", 1m, null, null, null, null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/requisitions", new RequisitionIn(null, "Item livre", null, 1m, null, null, null, null)));
        var free = await (await c.Post("/api/requisitions", new RequisitionIn(null, "  Item livre  ", "pc", 1m, null, null, null, null))).Read<RequisitionOut>();
        Assert.Equal("Item livre", free.Description);
        Assert.Equal("PC", free.Unit);

        var r = await (await c.Post("/api/requisitions", new RequisitionIn(coil.Id, null, null, 3m, null, null, null, null))).Read<RequisitionOut>();
        await AssertStatus(HttpStatusCode.BadRequest, c.Post($"/api/requisitions/{r.Id}/approve", new RequisitionDecisionIn(0m, null)));
        await AssertStatus(HttpStatusCode.NotFound, c.Post("/api/requisitions/999999/approve", new RequisitionDecisionIn(null, null)));
        await AssertStatus(HttpStatusCode.NotFound, c.Post("/api/requisitions/999999/reject", new RequisitionDecisionIn(null, null)));
        await AssertStatus(HttpStatusCode.NotFound, c.Post("/api/requisitions/999999/cancel", new ReasonIn("x")));

        var rejected = await (await c.Post($"/api/requisitions/{r.Id}/reject", new RequisitionDecisionIn(null, "sem verba"))).Read<RequisitionOut>();
        Assert.Equal(RequisitionStatus.Rejected, rejected.Status);
        Assert.Null(rejected.ApprovedQuantity);
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/requisitions/{r.Id}/reject", new RequisitionDecisionIn(null, null)));
        var cancelled = await (await c.Post($"/api/requisitions/{r.Id}/cancel", new ReasonIn("desistiu"))).Read<RequisitionOut>();
        Assert.Equal(RequisitionStatus.Cancelled, cancelled.Status);
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/requisitions/{r.Id}/cancel", new ReasonIn(null)));
    }

    [Fact]
    public async Task Quotation_validation_and_state_errors()
    {
        var c = await api.AdminAsync();
        var coil = await Coil(c);
        var acme = await Supplier(c);
        var dormant = await Supplier(c, active: false);
        var r1 = await Approved(c, coil.Id);

        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/quotations", new QuotationIn([], [acme.Id], null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/quotations", new QuotationIn([r1.Id], [], null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/quotations", new QuotationIn([r1.Id, 999_999], [acme.Id], null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/quotations", new QuotationIn([r1.Id], [999_999], null)));
        await AssertStatus(HttpStatusCode.Conflict, c.Post("/api/quotations", new QuotationIn([r1.Id], [dormant.Id], null)));
        await AssertStatus(HttpStatusCode.NotFound, c.Post("/api/quotations/999999/cancel", new { }));
        await AssertStatus(HttpStatusCode.NotFound, c.Post("/api/quotations/999999/suppliers", new QuotationSupplierIn(acme.Id)));

        var q = await (await c.Post("/api/quotations", new QuotationIn([r1.Id], [acme.Id], null))).Read<QuotationOut>();
        var item = q.Items[0];
        var bid = item.Bids[0];
        var late = await Supplier(c);
        await AssertStatus(HttpStatusCode.BadRequest, c.Post($"/api/quotations/{q.Id}/suppliers", new QuotationSupplierIn(999_999)));
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/quotations/{q.Id}/suppliers", new QuotationSupplierIn(dormant.Id)));
        q = await (await c.Post($"/api/quotations/{q.Id}/suppliers", new QuotationSupplierIn(late.Id))).Read<QuotationOut>();
        Assert.Equal(2, q.Items[0].Bids.Count);
        // adding the same supplier twice is a no-op
        q = await (await c.Post($"/api/quotations/{q.Id}/suppliers", new QuotationSupplierIn(late.Id))).Read<QuotationOut>();
        Assert.Equal(2, q.Items[0].Bids.Count);

        string BidUrl(int id) => $"/api/quotations/{q.Id}/bids/{id}";
        await AssertStatus(HttpStatusCode.NotFound, c.Put($"/api/quotations/{q.Id}/bids/999999", new BidInput(1m, 0m, 0m, 0m, null, null, null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Put(BidUrl(bid.Id), new BidInput(-1m, 0m, 0m, 0m, null, null, null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Put(BidUrl(bid.Id), new BidInput(1m, 100m, 0m, 0m, null, null, null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Put(BidUrl(bid.Id), new BidInput(1m, -1m, 0m, 0m, null, null, null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Put(BidUrl(bid.Id), new BidInput(1m, 0m, 101m, 0m, null, null, null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Put(BidUrl(bid.Id), new BidInput(1m, 0m, 0m, -1m, null, null, null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Put(BidUrl(bid.Id), new BidInput(1m, 0m, 0m, 101m, null, null, null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Put(BidUrl(bid.Id), new BidInput(1m, 0m, 0m, 0m, -1, null, null)));

        // award without a quoted price, unknown item/bid, then a proper award
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/quotations/{q.Id}/items/{item.Id}/award", new AwardIn(bid.Id)));
        await AssertStatus(HttpStatusCode.NotFound, c.Post($"/api/quotations/{q.Id}/items/999999/award", new AwardIn(bid.Id)));
        await AssertStatus(HttpStatusCode.NotFound, c.Post($"/api/quotations/{q.Id}/items/{item.Id}/award", new AwardIn(999_999)));
        await AssertStatus(HttpStatusCode.NotFound, c.Post($"/api/quotations/{q.Id}/items/999999/reject", new { }));
        (await c.Put(BidUrl(bid.Id), new BidInput(5m, 0m, 0m, 0m, 7, "  30  ", null))).EnsureSuccessStatusCode();
        (await c.Put(BidUrl(bid.Id), new BidInput(6m, 0m, 0m, 0m, null, null, null))).EnsureSuccessStatusCode();
        (await c.Post($"/api/quotations/{q.Id}/items/{item.Id}/award", new AwardIn(bid.Id))).EnsureSuccessStatusCode();

        // the quotation is now fully decided and closed
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/quotations/{q.Id}/items/{item.Id}/award", new AwardIn(bid.Id)));
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/quotations/{q.Id}/items/{item.Id}/reject", new { }));
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/quotations/{q.Id}/cancel", new { }));
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/quotations/{q.Id}/suppliers", new QuotationSupplierIn(late.Id)));

        // order from quotation: unknown supplier has nothing awarded, inactive checked after
        await AssertStatus(HttpStatusCode.Conflict, c.Post("/api/purchase-orders/from-quotation", new OrderFromQuotationIn(q.Id, late.Id, null)));
        await AssertStatus(HttpStatusCode.NotFound, c.Post("/api/purchase-orders/from-quotation", new OrderFromQuotationIn(999_999, acme.Id, null)));
        var order = await (await c.Post("/api/purchase-orders/from-quotation", new OrderFromQuotationIn(q.Id, acme.Id, "obs"))).Read<OrderOut>();
        Assert.Equal(Today.AddDays(20), order.Lines[0].DueDate);
        Assert.Null(order.PaymentTerms);
        // everything awarded is already ordered
        await AssertStatus(HttpStatusCode.Conflict, c.Post("/api/purchase-orders/from-quotation", new OrderFromQuotationIn(q.Id, acme.Id, null)));
    }

    [Fact]
    public async Task Quotation_cancel_and_item_reject_release_requisitions()
    {
        var c = await api.AdminAsync();
        var coil = await Coil(c);
        var other = await Coil(c);
        var acme = await Supplier(c);
        var r1 = await Approved(c, coil.Id);
        var r2 = await Approved(c, other.Id);

        var q = await (await c.Post("/api/quotations", new QuotationIn([r1.Id, r2.Id], [acme.Id], null))).Read<QuotationOut>();
        Assert.Equal(2, q.Items.Count);
        var first = q.Items.OrderBy(i => i.Item).First();
        var second = q.Items.OrderBy(i => i.Item).Last();

        // rejecting one item leaves the quotation open, so it cannot be cancelled wholesale
        q = await (await c.Post($"/api/quotations/{q.Id}/items/{first.Id}/reject", new { })).Read<QuotationOut>();
        Assert.Equal(QuotationStatus.Open, q.Status);
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/quotations/{q.Id}/cancel", new { }));
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/quotations/{q.Id}/items/{first.Id}/reject", new { }));
        q = await (await c.Post($"/api/quotations/{q.Id}/items/{second.Id}/reject", new { })).Read<QuotationOut>();
        Assert.Equal(QuotationStatus.Closed, q.Status);

        // a rejected requisition can be quoted again, then the fresh quotation is cancelled and it goes back to approved
        var q2 = await (await c.Post("/api/quotations", new QuotationIn([r1.Id], [acme.Id], null))).Read<QuotationOut>();
        q2 = await (await c.Post($"/api/quotations/{q2.Id}/cancel", new { })).Read<QuotationOut>();
        Assert.Equal(QuotationStatus.Cancelled, q2.Status);
        Assert.Equal(RequisitionStatus.Approved, (await (await c.GetAsync($"/api/requisitions/{r1.Id}")).Read<RequisitionOut>()).Status);
        await AssertStatus(HttpStatusCode.Conflict, c.Post("/api/purchase-orders/from-quotation", new OrderFromQuotationIn(q2.Id, acme.Id, null)));
    }

    [Fact]
    public async Task Order_creation_validation()
    {
        var c = await api.AdminAsync();
        var coil = await Coil(c);
        var noBuy = await Coil(c, purchased: false);
        var acme = await Supplier(c);
        var dormant = await Supplier(c, active: false);
        var r = await Approved(c, coil.Id);
        var pendingReq = await (await c.Post("/api/requisitions", new RequisitionIn(coil.Id, null, null, 1m, null, null, null, null))).Read<RequisitionOut>();
        var otherMaterial = await Coil(c);
        var otherReq = await Approved(c, otherMaterial.Id);

        await AssertStatus(HttpStatusCode.BadRequest, Order(c, acme.Id));
        await AssertStatus(HttpStatusCode.BadRequest, Order(c, 999_999, Line(coil.Id)));
        await AssertStatus(HttpStatusCode.Conflict, Order(c, dormant.Id, Line(coil.Id)));
        await AssertStatus(HttpStatusCode.BadRequest, Order(c, acme.Id, Line(coil.Id, qty: 0m)));
        await AssertStatus(HttpStatusCode.BadRequest, Order(c, acme.Id, Line(coil.Id, price: -1m)));
        await AssertStatus(HttpStatusCode.BadRequest, Order(c, acme.Id, Line(999_999)));
        await AssertStatus(HttpStatusCode.Conflict, Order(c, acme.Id, Line(noBuy.Id)));
        await AssertStatus(HttpStatusCode.BadRequest, Order(c, acme.Id, Line(null, desc: null, unit: "KG")));
        await AssertStatus(HttpStatusCode.BadRequest, Order(c, acme.Id, Line(null, desc: "Servico", unit: null)));
        await AssertStatus(HttpStatusCode.BadRequest, Order(c, acme.Id, Line(coil.Id, reqs: [r.Id, r.Id])));
        await AssertStatus(HttpStatusCode.BadRequest, Order(c, acme.Id, Line(coil.Id, reqs: [999_999])));
        await AssertStatus(HttpStatusCode.Conflict, Order(c, acme.Id, Line(coil.Id, reqs: [pendingReq.Id])));
        await AssertStatus(HttpStatusCode.BadRequest, Order(c, acme.Id, Line(coil.Id, reqs: [otherReq.Id])));

        var free = await (await Order(c, acme.Id, Line(null, desc: " Frete ", unit: "sv"))).Read<OrderOut>();
        Assert.Equal("Frete", free.Lines[0].Description);
        Assert.Equal("SV", free.Lines[0].Unit);
        var linked = await (await Order(c, acme.Id, Line(coil.Id, desc: "Outra", unit: "kg", reqs: [r.Id]))).Read<OrderOut>();
        Assert.Equal("Outra", linked.Lines[0].Description);
        Assert.Equal("KG", linked.Lines[0].Unit);

        // cancelling releases the requisition back to approved; a reason is required
        await AssertStatus(HttpStatusCode.BadRequest, c.Post($"/api/purchase-orders/{linked.Id}/cancel", new ReasonIn(" ")));
        await AssertStatus(HttpStatusCode.NotFound, c.Post("/api/purchase-orders/999999/cancel", new ReasonIn("x")));
        await AssertStatus(HttpStatusCode.NotFound, c.Post("/api/purchase-orders/999999/close", new ReasonIn("x")));
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/purchase-orders/{linked.Id}/close", new ReasonIn("x")));
        (await c.Post($"/api/purchase-orders/{linked.Id}/cancel", new ReasonIn("erro"))).EnsureSuccessStatusCode();
        Assert.Equal(RequisitionStatus.Approved, (await (await c.GetAsync($"/api/requisitions/{r.Id}")).Read<RequisitionOut>()).Status);
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/purchase-orders/{linked.Id}/cancel", new ReasonIn("de novo")));
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/purchase-orders/{linked.Id}/close", new ReasonIn("x")));
        await AssertStatus(HttpStatusCode.Conflict, c.Put($"/api/purchase-orders/{linked.Id}/lines/{linked.Lines[0].Id}/due-date", new DueDateIn(Today.AddDays(5))));
        await AssertStatus(HttpStatusCode.NotFound, c.Put($"/api/purchase-orders/{linked.Id}/lines/999999/due-date", new DueDateIn(Today.AddDays(5))));
    }

    [Fact]
    public async Task Receipt_validation_close_and_installments()
    {
        var c = await api.AdminAsync();
        var coil = await Coil(c);
        var acme = await Supplier(c);
        var other = await Supplier(c);
        var order = await (await Order(c, acme.Id, Line(coil.Id, qty: 10m, price: 10m, due: Today.AddDays(40)))).Read<OrderOut>();
        var line = order.Lines[0];

        ReceiptIn Rec(decimal qty, string? invoice = "NF1", DateOnly? invDate = null, DateTimeOffset? at = null, decimal? total = null, string? just = null, decimal? price = null, int? supplier = null, params ReceiptLineIn[] extra) =>
            new(supplier ?? acme.Id, invoice ?? "", "1", invDate ?? Today, at, total, just, null, [new ReceiptLineIn(line.Id, qty, price, null), .. extra]);

        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/goods-receipts", Rec(1m, invoice: " ")));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/goods-receipts", new ReceiptIn(acme.Id, "N", null, Today, null, null, null, null, [])));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/goods-receipts", Rec(1m, extra: new ReceiptLineIn(line.Id, 1m, null, null))));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/goods-receipts", Rec(1m, at: DateTimeOffset.UtcNow.AddDays(2))));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/goods-receipts", Rec(1m, invDate: Today.AddDays(3))));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/goods-receipts", new ReceiptIn(acme.Id, "N", null, Today, null, null, null, null, [new ReceiptLineIn(999_999, 1m, null, null)])));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/goods-receipts", Rec(1m, supplier: other.Id)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/goods-receipts", Rec(0m)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/goods-receipts", Rec(1m, price: -1m)));
        await AssertStatus(HttpStatusCode.Conflict, c.Post("/api/goods-receipts", Rec(1000m)));
        // default settings forbid receipts well before the due date
        await AssertStatus(HttpStatusCode.Conflict, c.Post("/api/goods-receipts", Rec(1m)));

        var original = await (await c.GetAsync("/api/purchasing/settings")).Read<PurchasingSettingsDto>();
        (await c.Put("/api/purchasing/settings", new PurchasingSettingsDto(0m, true, 0))).EnsureSuccessStatusCode();
        try { await AfterRelaxedSettings(); }
        finally { (await c.Put("/api/purchasing/settings", original)).EnsureSuccessStatusCode(); }

        async Task AfterRelaxedSettings()
        {
        // invoice total differing from the calculated one needs a justification
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/goods-receipts", Rec(2m, total: 50m)));
        var receipt = await (await c.Post("/api/goods-receipts", Rec(2m, total: 50m, just: "frete incluso", price: 12m))).Read<ReceiptOut>();
        Assert.True(receipt.Divergent);
        Assert.Equal(24m, receipt.CalculatedTotal);
        Assert.Equal(50m, Assert.Single(receipt.Installments).Amount);

        // before anything was received a close is refused; after a partial receipt it closes
        var order2 = await (await Order(c, acme.Id, Line(coil.Id, qty: 5m, price: 10m))).Read<OrderOut>();
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/purchase-orders/{order2.Id}/close", new ReasonIn("x")));
        var partial = new ReceiptIn(acme.Id, "NF2", null, Today, null, null, null, null, [new ReceiptLineIn(order2.Lines[0].Id, 2m, null, null)]);
        (await c.Post("/api/goods-receipts", partial)).EnsureSuccessStatusCode();
        await AssertStatus(HttpStatusCode.BadRequest, c.Post($"/api/purchase-orders/{order2.Id}/close", new ReasonIn("")));
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/purchase-orders/{order2.Id}/cancel", new ReasonIn("x")));
        (await c.Put($"/api/purchase-orders/{order2.Id}/lines/{order2.Lines[0].Id}/due-date", new DueDateIn(Today.AddDays(9)))).EnsureSuccessStatusCode();
        (await c.Post($"/api/purchase-orders/{order2.Id}/close", new ReasonIn("saldo cancelado"))).EnsureSuccessStatusCode();
        await AssertStatus(HttpStatusCode.Conflict, c.Post("/api/goods-receipts", new ReceiptIn(acme.Id, "NF3", null, Today, null, null, null, null, [new ReceiptLineIn(order2.Lines[0].Id, 1m, null, null)])));
        await AssertStatus(HttpStatusCode.Conflict, c.Put($"/api/purchase-orders/{order2.Id}/lines/{order2.Lines[0].Id}/due-date", new DueDateIn(Today.AddDays(5))));
        }
    }

    [Fact]
    public void Installments_split_terms_and_default_to_single_payment()
    {
        var invoice = new DateOnly(2026, 1, 31);
        var none = Ebt.Core.Purchasing.PurchasingService.Installments(null, invoice, 100m).ToList();
        Assert.Equal(invoice, Assert.Single(none).DueDate);
        var three = Ebt.Core.Purchasing.PurchasingService.Installments("30/60/90", invoice, 100m).ToList();
        Assert.Equal([33.33m, 33.33m, 33.34m], three.Select(i => i.Amount));
        Assert.Equal(invoice.AddDays(90), three[2].DueDate);
        // terms beyond 720 days are ignored
        Assert.Single(Ebt.Core.Purchasing.PurchasingService.Installments("999", invoice, 10m));
    }
}
