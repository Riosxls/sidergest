using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Ebt.Core.Purchasing;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Tests;

[Collection("purchasing")]
public class PurchasingTests(PurchasingFixture api)
{
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.UtcNow);

    private static string Code(string prefix) => $"{prefix}{Guid.NewGuid():N}"[..12].ToUpper();

    private static async Task<SupplierOut> Supplier(HttpClient c, string name) =>
        await (await c.Post("/api/suppliers", new SupplierIn(name, null, Code("F"), null))).Read<SupplierOut>();

    private static async Task<MaterialOut> Coil(HttpClient c, bool inspect = true) =>
        await (await c.Post("/api/materials", new MaterialIn(Code("B"), "Bobina 1,50mm", null, null, null, "KG", "T", 1000m, 1.5m, 1200m, "72083990", 15, null, null, null, inspect, true, false))).Read<MaterialOut>();

    private static async Task<RequisitionOut> ApprovedRequisition(HttpClient c, int materialId, decimal qty)
    {
        var r = await (await c.Post("/api/requisitions", new RequisitionIn(materialId, null, null, qty, "PCP", Today.AddDays(20), null, null))).Read<RequisitionOut>();
        return await (await c.Post($"/api/requisitions/{r.Id}/approve", new RequisitionDecisionIn(null, null))).Read<RequisitionOut>();
    }

    private static async Task<OrderOut> DirectOrder(HttpClient c, int supplierId, int materialId, decimal qty, decimal price, DateOnly due, string terms = "30/60", params int[] requisitionIds) =>
        await (await c.Post("/api/purchase-orders", new OrderIn(supplierId, terms, null,
            [new OrderLineIn(materialId, null, null, qty, price, 0m, 18m, 0m, due, requisitionIds)]))).Read<OrderOut>();

    private static ReceiptIn Receipt(int supplierId, int lineId, decimal qty, decimal? invoiceTotal = null, string? justification = null, string? lot = null) =>
        new(supplierId, Code("NF"), "1", Today, null, invoiceTotal, justification, null, [new ReceiptLineIn(lineId, qty, null, lot)]);

    [Fact]
    public async Task Requisition_quotation_order_receipt_flow()
    {
        var c = await api.AdminAsync();
        var coil = await Coil(c);
        var acme = await Supplier(c, "Acme Aços");
        var beta = await Supplier(c, "Beta Metais");

        var r1 = await (await c.Post("/api/requisitions", new RequisitionIn(coil.Id, null, null, 3m, "PCP", Today.AddDays(30), "OF 123", null))).Read<RequisitionOut>();
        Assert.Equal(RequisitionStatus.PendingApproval, r1.Status);
        Assert.Equal("T", r1.Unit);
        r1 = await (await c.Post($"/api/requisitions/{r1.Id}/approve", new RequisitionDecisionIn(4m, "ok"))).Read<RequisitionOut>();
        Assert.Equal(RequisitionStatus.Approved, r1.Status);
        Assert.Equal(4m, r1.Quantity);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"/api/requisitions/{r1.Id}/approve", new RequisitionDecisionIn(null, null))).StatusCode);
        var r2 = await ApprovedRequisition(c, coil.Id, 1m);

        var pending = await (await c.Post("/api/requisitions", new RequisitionIn(coil.Id, null, null, 1m, null, null, null, null))).Read<RequisitionOut>();
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post("/api/quotations", new QuotationIn([pending.Id], [acme.Id], null))).StatusCode);

        var q = await (await c.Post("/api/quotations", new QuotationIn([r1.Id, r2.Id], [acme.Id, beta.Id], null))).Read<QuotationOut>();
        var item = Assert.Single(q.Items);
        Assert.Equal(5m, item.Quantity);
        Assert.Equal(2, item.Bids.Count);
        Assert.Equal(RequisitionStatus.Quoting, (await (await c.GetAsync($"/api/requisitions/{r1.Id}")).Read<RequisitionOut>()).Status);

        var acmeBid = item.Bids.Single(b => b.SupplierId == acme.Id);
        var betaBid = item.Bids.Single(b => b.SupplierId == beta.Id);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"/api/quotations/{q.Id}/items/{item.Id}/award", new AwardIn(acmeBid.Id))).StatusCode);
        await (await c.Put($"/api/quotations/{q.Id}/bids/{acmeBid.Id}", new BidInput(6000m, 0m, 18m, 5m, 0, "28/56", null))).Read<QuotationOut>();
        await (await c.Put($"/api/quotations/{q.Id}/bids/{betaBid.Id}", new BidInput(6100m, 5m, 18m, 0m, 10, "30", null))).Read<QuotationOut>();

        var cmp = Assert.Single(await (await c.GetAsync($"/api/quotations/{q.Id}/comparison")).Read<List<ComparisonItemOut>>());
        Assert.Equal(beta.Id, cmp.Bids[0].SupplierId);
        Assert.Equal(5795m, cmp.Bids[0].LandedUnitPrice);
        Assert.Equal(6300m, cmp.Bids[1].LandedUnitPrice);

        q = await (await c.Post($"/api/quotations/{q.Id}/items/{item.Id}/award", new AwardIn(acmeBid.Id))).Read<QuotationOut>();
        Assert.Equal(QuotationStatus.Closed, q.Status);
        Assert.Equal(BidStatus.Rejected, q.Items[0].Bids.Single(b => b.SupplierId == beta.Id).Status);
        Assert.Equal(RequisitionStatus.QuoteApproved, (await (await c.GetAsync($"/api/requisitions/{r2.Id}")).Read<RequisitionOut>()).Status);

        Assert.Equal(HttpStatusCode.Conflict, (await c.Post("/api/purchase-orders/from-quotation", new OrderFromQuotationIn(q.Id, beta.Id, null))).StatusCode);
        var po = await (await c.Post("/api/purchase-orders/from-quotation", new OrderFromQuotationIn(q.Id, acme.Id, null))).Read<OrderOut>();
        Assert.Equal(PurchaseOrderStatus.Open, po.Status);
        Assert.Equal("28/56", po.PaymentTerms);
        var line = Assert.Single(po.Lines);
        Assert.Equal(Today, line.DueDate);
        Assert.Equal(31500m, line.Total);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post("/api/purchase-orders/from-quotation", new OrderFromQuotationIn(q.Id, acme.Id, null))).StatusCode);
        var r1Ordered = await (await c.GetAsync($"/api/requisitions/{r1.Id}")).Read<RequisitionOut>();
        Assert.Equal(RequisitionStatus.OrderIssued, r1Ordered.Status);
        Assert.Equal(po.Number, r1Ordered.PurchaseOrderNumber);

        var before = api.Handler.Events.Count;
        var rec = await (await c.Post("/api/goods-receipts", Receipt(acme.Id, line.Id, 2m, lot: "L-77"))).Read<ReceiptOut>();
        Assert.Equal(12600m, rec.CalculatedTotal);
        Assert.Equal([new InstallmentOut(1, Today.AddDays(28), 6300m), new InstallmentOut(2, Today.AddDays(56), 6300m)], rec.Installments);
        var evt = api.Handler.Events.Skip(before).Single(e => e.ReceiptId == rec.Id);
        var el = Assert.Single(evt.Lines);
        Assert.Equal(coil.Id, el.MaterialId);
        Assert.Equal(2000m, el.Quantity);
        Assert.Equal("KG", el.StockUnit);
        Assert.Equal(6m, el.UnitCost);
        Assert.Equal("L-77", el.LotCode);
        Assert.True(el.RequiresInspection);
        Assert.Equal(po.Id, el.PurchaseOrderId);
        await using (var db = api.NewDb())
        {
            var bal = await db.StockBalances.Include(b => b.Lot).SingleAsync(b => b.MaterialId == coil.Id);
            Assert.Equal((2000m, api.ReceivingLocationId, "L-77", LotStatus.Quarantine), (bal.Quantity, bal.LocationId, bal.Lot!.Code, bal.Lot.Status));
            var doc = await db.StockDocuments.SingleAsync(d => d.Reference!.Contains($"REC {rec.Number}"));
            Assert.Equal((MovementType.Receipt, (int?)acme.Id), (doc.Type, doc.SupplierId));
        }

        po = await (await c.GetAsync($"/api/purchase-orders/{po.Id}")).Read<OrderOut>();
        Assert.Equal(PurchaseOrderStatus.PartiallyReceived, po.Status);
        Assert.Equal(3m, po.Lines[0].OpenQuantity);
        Assert.Equal(RequisitionStatus.PartiallyReceived, (await (await c.GetAsync($"/api/requisitions/{r1.Id}")).Read<RequisitionOut>()).Status);

        await (await c.Post("/api/goods-receipts", Receipt(acme.Id, line.Id, 3m))).Read<ReceiptOut>();
        po = await (await c.GetAsync($"/api/purchase-orders/{po.Id}")).Read<OrderOut>();
        Assert.Equal(PurchaseOrderStatus.Received, po.Status);
        Assert.Equal(RequisitionStatus.Received, (await (await c.GetAsync($"/api/requisitions/{r2.Id}")).Read<RequisitionOut>()).Status);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post("/api/goods-receipts", Receipt(acme.Id, line.Id, 0.1m))).StatusCode);

        var sm = Assert.Single(await (await c.GetAsync($"/api/suppliers/{acme.Id}/materials")).Read<List<SupplierMaterialOut>>());
        Assert.Equal(6000m, sm.LastUnitPrice);
        Assert.Equal(Today, sm.LastPurchaseDate);
        var history = await (await c.GetAsync($"/api/purchasing/materials/{coil.Id}/history")).Read<List<PurchaseHistoryOut>>();
        Assert.Equal(2, history.Count);
        var perf = await (await c.GetAsync($"/api/suppliers/{acme.Id}/performance")).Read<SupplierPerformanceOut>();
        Assert.Equal((1, 2, 2, 100m), (perf.Orders, perf.Receipts, perf.OnTimeLines, perf.OnTimePercent));
        Assert.Equal(31500m, perf.ReceivedValue);
    }

    [Fact]
    public async Task Receiving_enforces_tolerance_early_receipt_and_divergence()
    {
        var c = await api.AdminAsync();
        var coil = await Coil(c, inspect: false);
        var s = await Supplier(c, "Gama");
        var other = await Supplier(c, "Delta");
        var po = await DirectOrder(c, s.Id, coil.Id, 10m, 100m, Today.AddDays(10));
        var lineId = po.Lines[0].Id;

        var early = await c.Post("/api/goods-receipts", Receipt(s.Id, lineId, 5m));
        Assert.Equal(HttpStatusCode.Conflict, early.StatusCode);
        Assert.Contains("early receipt", await early.Content.ReadAsStringAsync());
        await (await c.Put($"/api/purchase-orders/{po.Id}/lines/{lineId}/due-date", new DueDateIn(Today.AddDays(-3)))).Read<OrderOut>();

        Assert.Equal(HttpStatusCode.BadRequest, (await c.Post("/api/goods-receipts", Receipt(other.Id, lineId, 1m))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post("/api/goods-receipts", Receipt(s.Id, lineId, 10.6m))).StatusCode);

        var noReason = await c.Post("/api/goods-receipts", Receipt(s.Id, lineId, 4m, invoiceTotal: 450m));
        Assert.Equal(HttpStatusCode.BadRequest, noReason.StatusCode);
        Assert.Contains("divergenceJustification", await noReason.Content.ReadAsStringAsync());

        var ok = await (await c.Post("/api/goods-receipts", Receipt(s.Id, lineId, 4m, invoiceTotal: 400.01m))).Read<ReceiptOut>();
        Assert.False(ok.Divergent);
        var justified = await (await c.Post("/api/goods-receipts", Receipt(s.Id, lineId, 6.5m, invoiceTotal: 700m, justification: "Frete incluso"))).Read<ReceiptOut>();
        Assert.True(justified.Divergent);
        Assert.Equal(700m, justified.Installments.Sum(i => i.Amount));

        var dup = Receipt(s.Id, lineId, 0.1m) with { InvoiceNumber = ok.InvoiceNumber };
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post("/api/goods-receipts", dup)).StatusCode);

        po = await (await c.GetAsync($"/api/purchase-orders/{po.Id}")).Read<OrderOut>();
        Assert.Equal(10.5m, po.Lines[0].ReceivedQuantity);
        Assert.Equal(PurchaseOrderStatus.Received, po.Status);

        var overdue = await DirectOrder(c, s.Id, coil.Id, 2m, 50m, Today.AddDays(-5));
        var late = await (await c.GetAsync($"/api/purchasing/overdue?supplierId={s.Id}")).Read<List<OverdueLineOut>>();
        var row = Assert.Single(late);
        Assert.Equal((overdue.Number, 5, 2m), (row.PurchaseOrderNumber, row.DaysLate, row.OpenQuantity));
    }

    [Fact]
    public async Task Stock_hook_failure_rolls_back_the_receipt()
    {
        var c = await api.AdminAsync();
        var coil = await Coil(c);
        var s = await Supplier(c, "Epsilon");
        var po = await DirectOrder(c, s.Id, coil.Id, 1m, 10m, Today);
        var input = Receipt(s.Id, po.Lines[0].Id, 1m);

        api.Handler.Fail = true;
        try
        {
            Assert.Equal(HttpStatusCode.InternalServerError, (await c.Post("/api/goods-receipts", input)).StatusCode);
        }
        finally
        {
            api.Handler.Fail = false;
        }

        await using (var db = api.NewDb())
        {
            Assert.False(await db.GoodsReceipts.AnyAsync(r => r.InvoiceNumber == input.InvoiceNumber));
            Assert.Equal(0m, (await db.PurchaseOrderLines.SingleAsync(l => l.Id == po.Lines[0].Id)).ReceivedQuantity);
            Assert.False(await db.SupplierMaterials.AnyAsync(x => x.SupplierId == s.Id));
            Assert.False(await db.StockBalances.AnyAsync(b => b.MaterialId == coil.Id));
        }
        await (await c.Post("/api/goods-receipts", input)).Read<ReceiptOut>();
        await using (var db = api.NewDb())
            Assert.Equal(1000m, (await db.StockBalances.SingleAsync(b => b.MaterialId == coil.Id)).Quantity);
    }

    [Fact]
    public async Task Cancel_and_close_orders_release_requisitions()
    {
        var c = await api.AdminAsync();
        var coil = await Coil(c);
        var s = await Supplier(c, "Zeta");
        var req = await ApprovedRequisition(c, coil.Id, 2m);
        var po = await DirectOrder(c, s.Id, coil.Id, 2m, 10m, Today, "", req.Id);
        Assert.Equal(RequisitionStatus.OrderIssued, (await (await c.GetAsync($"/api/requisitions/{req.Id}")).Read<RequisitionOut>()).Status);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post("/api/purchase-orders", new OrderIn(s.Id, null, null, [new OrderLineIn(coil.Id, null, null, 1m, 1m, 0, 0, 0, Today, [req.Id])]))).StatusCode);

        Assert.Equal(HttpStatusCode.BadRequest, (await c.Post($"/api/purchase-orders/{po.Id}/cancel", new ReasonIn(null))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"/api/purchase-orders/{po.Id}/close", new ReasonIn("x"))).StatusCode);
        po = await (await c.Post($"/api/purchase-orders/{po.Id}/cancel", new ReasonIn("Preço revisto"))).Read<OrderOut>();
        Assert.Equal(PurchaseOrderStatus.Cancelled, po.Status);
        var released = await (await c.GetAsync($"/api/requisitions/{req.Id}")).Read<RequisitionOut>();
        Assert.Equal((RequisitionStatus.Approved, (int?)null), (released.Status, released.PurchaseOrderId));

        var po2 = await DirectOrder(c, s.Id, coil.Id, 2m, 10m, Today, "", req.Id);
        var rec = await (await c.Post("/api/goods-receipts", Receipt(s.Id, po2.Lines[0].Id, 1m))).Read<ReceiptOut>();
        Assert.Single(rec.Installments);
        Assert.Equal(Today, rec.Installments[0].DueDate);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"/api/purchase-orders/{po2.Id}/cancel", new ReasonIn("x"))).StatusCode);
        po2 = await (await c.Post($"/api/purchase-orders/{po2.Id}/close", new ReasonIn("Saldo cancelado"))).Read<OrderOut>();
        Assert.Equal(PurchaseOrderStatus.Closed, po2.Status);
        Assert.Equal(0m, po2.Lines[0].OpenQuantity);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post("/api/goods-receipts", Receipt(s.Id, po2.Lines[0].Id, 1m))).StatusCode);
        Assert.Equal(RequisitionStatus.PartiallyReceived, (await (await c.GetAsync($"/api/requisitions/{req.Id}")).Read<RequisitionOut>()).Status);

        var other = await ApprovedRequisition(c, coil.Id, 1m);
        var q = await (await c.Post("/api/quotations", new QuotationIn([other.Id], [s.Id], null))).Read<QuotationOut>();
        q = await (await c.Post($"/api/quotations/{q.Id}/cancel", new { })).Read<QuotationOut>();
        Assert.Equal(QuotationStatus.Cancelled, q.Status);
        Assert.Equal(RequisitionStatus.Approved, (await (await c.GetAsync($"/api/requisitions/{other.Id}")).Read<RequisitionOut>()).Status);
        Assert.Equal(RequisitionStatus.Cancelled, (await (await c.Post($"/api/requisitions/{other.Id}/cancel", new ReasonIn("Não precisa"))).Read<RequisitionOut>()).Status);
    }

    [Fact]
    public async Task Non_stock_items_and_validation()
    {
        var c = await api.AdminAsync();
        var s = await Supplier(c, "Serviços Eta");
        Assert.Equal(HttpStatusCode.BadRequest, (await c.Post("/api/requisitions", new RequisitionIn(null, null, null, 1m, null, null, null, null))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await c.Post("/api/requisitions", new RequisitionIn(null, "Calibração", "SV", 0m, null, null, null, null))).StatusCode);
        var req = await (await c.Post("/api/requisitions", new RequisitionIn(null, "Calibração paquímetros", "sv", 1m, "QUAL", null, null, null))).Read<RequisitionOut>();
        Assert.Equal("SV", req.Unit);
        req = await (await c.Post($"/api/requisitions/{req.Id}/approve", new RequisitionDecisionIn(null, null))).Read<RequisitionOut>();
        var po = await (await c.Post("/api/purchase-orders", new OrderIn(s.Id, "15", null, [new OrderLineIn(null, "Calibração paquímetros", "SV", 1m, 350m, 0, 0, 0, Today, [req.Id])]))).Read<OrderOut>();
        var before = api.Handler.Events.Count;
        var rec = await (await c.Post("/api/goods-receipts", Receipt(s.Id, po.Lines[0].Id, 1m))).Read<ReceiptOut>();
        Assert.Empty(api.Handler.Events.Skip(before).Single(e => e.ReceiptId == rec.Id).Lines);
        Assert.Equal(Today.AddDays(15), rec.Installments[0].DueDate);
    }

    [Fact]
    public async Task Roles_guard_purchasing_actions()
    {
        var admin = await api.AdminAsync();
        var coil = await Coil(admin);
        var s = await Supplier(admin, "Theta");
        var reader = await api.UserAsync(UserRole.Reader);
        var engineering = await api.UserAsync(UserRole.Engineering);
        var stock = await api.UserAsync(UserRole.Stock);
        var buyer = await api.UserAsync(UserRole.Purchasing);
        var body = new RequisitionIn(coil.Id, null, null, 1m, null, null, null, null);

        Assert.Equal(HttpStatusCode.Forbidden, (await reader.Post("/api/requisitions", body)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await reader.GetAsync("/api/requisitions")).StatusCode);
        var req = await (await engineering.Post("/api/requisitions", body)).Read<RequisitionOut>();
        Assert.Equal(HttpStatusCode.Forbidden, (await engineering.Post($"/api/requisitions/{req.Id}/approve", new RequisitionDecisionIn(null, null))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await stock.Post($"/api/requisitions/{req.Id}/approve", new RequisitionDecisionIn(null, null))).StatusCode);
        await (await buyer.Post($"/api/requisitions/{req.Id}/approve", new RequisitionDecisionIn(null, null))).Read<RequisitionOut>();

        var order = new OrderIn(s.Id, null, null, [new OrderLineIn(coil.Id, null, null, 1m, 5m, 0, 0, 0, Today, [req.Id])]);
        Assert.Equal(HttpStatusCode.Forbidden, (await stock.Post("/api/purchase-orders", order)).StatusCode);
        var po = await (await buyer.Post("/api/purchase-orders", order)).Read<OrderOut>();
        Assert.Equal(HttpStatusCode.Forbidden, (await engineering.Post("/api/goods-receipts", Receipt(s.Id, po.Lines[0].Id, 1m))).StatusCode);
        var rec = await (await stock.Post("/api/goods-receipts", Receipt(s.Id, po.Lines[0].Id, 1m))).Read<ReceiptOut>();
        Assert.StartsWith("stock", rec.ReceivedBy);

        Assert.Equal(HttpStatusCode.Forbidden, (await buyer.Put("/api/purchasing/settings", new PurchasingSettingsDto(10m, true, 0))).StatusCode);
        Assert.Equal(5m, (await (await reader.GetAsync("/api/purchasing/settings")).Read<PurchasingSettingsDto>()).ReceivingTolerancePercent);
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().GetAsync("/api/requisitions")).StatusCode);
    }

    [Fact]
    public void Payment_terms_split_into_installments()
    {
        var d = new DateOnly(2026, 1, 10);
        var parts = PurchasingService.Installments("30/60/90 DDL", d, 100m).ToList();
        Assert.Equal([33.33m, 33.33m, 33.34m], parts.Select(p => p.Amount));
        Assert.Equal(d.AddDays(90), parts[2].DueDate);
        Assert.Equal(d, Assert.Single(PurchasingService.Installments("À VISTA", d, 10m)).DueDate);
    }
}
