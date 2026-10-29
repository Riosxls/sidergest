using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Production;

namespace Ebt.Tests;

[Collection("api")]
public class ProductionTests(ApiFixture api)
{
    private static readonly DateOnly Today = Ebt.Core.Services.Clock.Today();

    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();

    private sealed record Setup(ProductOut Product, ProductOut Component, MaterialOut Material, MachineOut Machine, StockLocationOut Store, StockLocationOut Finished, OccurrenceOut Scrap);

    private static async Task<Setup> Arrange(HttpClient c, decimal pph10 = 50m, decimal pph20 = 25m, decimal materialStock = 1000m, decimal componentStock = 50m)
    {
        await Settings(c);
        var wc = await (await c.Post("/api/work-centers", new WorkCenterIn(Code("W", 10), "Corte", null))).Read<WorkCenterOut>();
        var machine = await (await c.Post("/api/machines", new MachineIn(Code("MQ", 10), "Serra", wc.Id, "SERRAS"))).Read<MachineOut>();
        var material = await (await c.Post("/api/materials", new MaterialIn(Code("MP"), "Tubo bruto", null, null, null, "KG", "KG", 1m, null, null, null, null, null, null, null, false, true, false))).Read<MaterialOut>();
        var component = await (await c.Post("/api/products", Tube(Code("C")))).Read<ProductOut>();
        var product = await (await c.Post("/api/products", Tube(Code("P")))).Read<ProductOut>();
        var op10 = await (await c.Post($"/api/products/{product.Id}/routing", new RoutingOperationIn(10, null, machine.Id, wc.Id, null, 1m, pph10, 1m, "Corte", null, null))).Read<RoutingOperationOut>();
        var op20 = await (await c.Post($"/api/products/{product.Id}/routing", new RoutingOperationIn(20, null, machine.Id, wc.Id, null, 1m, pph20, 1m, "Montagem", null, null))).Read<RoutingOperationOut>();
        (await c.Post($"/api/routing-operations/{op10.Id}/items", new BomItemIn(material.Id, null, 2.5m, "KG"))).EnsureSuccessStatusCode();
        (await c.Post($"/api/routing-operations/{op20.Id}/items", new BomItemIn(null, component.Id, 1m, "PC"))).EnsureSuccessStatusCode();
        var store = await (await c.Post("/api/stock-locations", new StockLocationIn(Code("A", 10), "Almox", StockLocationKind.Internal))).Read<StockLocationOut>();
        var finished = await (await c.Post("/api/stock-locations", new StockLocationIn(Code("F", 10), "PA", StockLocationKind.Internal))).Read<StockLocationOut>();
        if (materialStock > 0) (await c.Post("/api/stock/documents", new StockPost(MovementType.Receipt, Today, [new StockLine(material.Id, null, store.Id, materialStock, UnitCost: 10m)], "NF 1"))).EnsureSuccessStatusCode();
        if (componentStock > 0) (await c.Post("/api/stock/documents", new StockPost(MovementType.AdjustmentIn, Today, [new StockLine(null, component.Id, store.Id, componentStock, UnitCost: 3m)], "INV"))).EnsureSuccessStatusCode();
        var scrap = await (await c.Post("/api/production/occurrences", new OccurrenceIn(Code("S", 10), "Rebarba", OccurrenceKind.Scrap, false))).Read<OccurrenceOut>();
        return new Setup(product, component, material, machine, store, finished, scrap);
    }

    private static ProductIn Tube(string code) => new(code, "Tubo " + code, ProductKind.Part, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, null, null, "73063010", "PC", null, false, null, null);

    private static async Task Settings(HttpClient c, decimal tolerance = 3m) =>
        (await c.Put("/api/production/settings", new ProductionSettingsDto(tolerance, 8m, false, null, null))).EnsureSuccessStatusCode();

    private static async Task<ProductionOrderOut> Create(HttpClient c, int productId, decimal qty, DateOnly? due = null, int? parent = null) =>
        await (await c.Post("/api/production/orders", new ProductionOrderIn(productId, qty, due ?? Today.AddDays(30), ParentOrderId: parent))).Read<ProductionOrderOut>();

    private static async Task<ProductionOrderOut> Get(HttpClient c, int id) => await (await c.GetAsync($"/api/production/orders/{id}")).Read<ProductionOrderOut>();

    private static Task<HttpResponseMessage> Report(HttpClient c, int orderId, int seq, decimal good, decimal scrap = 0, int? scrapReason = null) =>
        c.Post("/api/production/reports", new ReportInput(orderId, seq, Today, good, scrap, scrapReason, Hours: 1m));

    private static Task<HttpResponseMessage> Transition(HttpClient c, int id, string action, string? reason = null, bool technical = false) =>
        c.Post($"/api/production/orders/{id}/{action}", new ProductionReasonIn(reason, technical));

    private static async Task<decimal> Balance(HttpClient c, string item, int id, int locationId) =>
        (await (await c.GetAsync($"/api/stock/balances?{item}={id}&locationId={locationId}")).Read<Page<StockBalanceOut>>()).Items.Sum(b => b.Quantity);

    [Fact]
    public async Task Roles_guard_production_endpoints()
    {
        var admin = await api.AdminAsync();
        var s = await Arrange(admin);
        var reader = await api.UserAsync(UserRole.Reader);
        var stock = await api.UserAsync(UserRole.Stock);
        var production = await api.UserAsync(UserRole.Production);
        var body = new ProductionOrderIn(s.Product.Id, 10m, Today.AddDays(10));

        Assert.Equal(HttpStatusCode.Forbidden, (await reader.Post("/api/production/orders", body)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await stock.Post("/api/production/orders", body)).StatusCode);
        var order = await (await production.Post("/api/production/orders", body)).Read<ProductionOrderOut>();
        Assert.Equal(HttpStatusCode.OK, (await production.Post($"/api/production/orders/{order.Id}/release", new ReleaseIn())).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await reader.Post($"/api/production/orders/{order.Id}/issues", new IssueInput(Today, s.Store.Id))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await stock.Post($"/api/production/orders/{order.Id}/issues", new IssueInput(Today, s.Store.Id))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Report(stock, order.Id, 10, 1)).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await Report(production, order.Id, 10, 1)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await production.Put("/api/production/settings", new ProductionSettingsDto(3m, 8m, false, null, null))).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await reader.GetAsync($"/api/production/orders/{order.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().GetAsync("/api/production/orders")).StatusCode);
    }

    [Fact]
    public async Task Full_order_flow_from_bom_to_finished_goods_and_close()
    {
        var c = await api.AdminAsync();
        var s = await Arrange(c);
        var order = await Create(c, s.Product.Id, 100m);
        Assert.Equal(ProductionOrderStatus.Created, order.Status);
        Assert.StartsWith("OF ", order.Reference);
        Assert.Equal([10, 20], order.Operations.Select(o => o.Sequence));
        var mp = Assert.Single(order.Materials, m => m.MaterialId == s.Material.Id);
        Assert.Equal(250m, mp.Required);
        Assert.Equal(100m, Assert.Single(order.Materials, m => m.ComponentProductId == s.Component.Id).Required);
        Assert.Empty(order.Warnings);

        var availability = await (await c.GetAsync($"/api/production/orders/{order.Id}/availability")).Read<AvailabilityResult>();
        Assert.False(availability.Complete);
        Assert.Equal(50m, Assert.Single(availability.Lines, l => l.ProductId == s.Component.Id).Shortage);
        Assert.Equal(0m, Assert.Single(availability.Lines, l => l.MaterialId == s.Material.Id).Shortage);

        var refused = await c.Post($"/api/production/orders/{order.Id}/release", new ReleaseIn());
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Contains(s.Component.Code, await refused.Content.ReadAsStringAsync());
        Assert.Equal(ProductionOrderStatus.Created, (await Get(c, order.Id)).Status);

        var children = await (await c.Post($"/api/production/orders/{order.Id}/child-orders", new { })).Read<List<ProductionOrderSummaryOut>>();
        var child = Assert.Single(children);
        Assert.Equal(s.Component.Id, child.ProductId);
        Assert.Equal(50m, child.Quantity);
        Assert.Empty(await (await c.Post($"/api/production/orders/{order.Id}/child-orders", new { })).Read<List<ProductionOrderSummaryOut>>());

        var released = await (await c.Post($"/api/production/orders/{order.Id}/release", new ReleaseIn(true))).Read<ReleaseOut>();
        Assert.Equal(ProductionOrderStatus.Released, released.Order.Status);
        Assert.Equal(50m, Assert.Single(released.Shortages).Shortage);
        Assert.Equal(250m, released.Order.Materials.Single(m => m.MaterialId == s.Material.Id).Reserved);
        Assert.Equal(50m, released.Order.Materials.Single(m => m.ComponentProductId == s.Component.Id).Reserved);
        var reservations = await (await c.GetAsync($"/api/stock/reservations?reference={Uri.EscapeDataString(order.Reference)}")).Read<Page<ReservationOut>>();
        Assert.Equal(2, reservations.Total);

        Assert.Equal(HttpStatusCode.Conflict, (await c.Post("/api/stock/documents", new StockPost(MovementType.Issue, Today, [new StockLine(s.Material.Id, null, s.Store.Id, 800m)]))).StatusCode);

        var issue = await (await c.Post($"/api/production/orders/{order.Id}/issues", new IssueInput(Today, s.Store.Id, [new IssueLineInput(mp.Id, 250m)]))).Read<StockDocumentSummary>();
        Assert.Equal(order.Reference, issue.Reference);
        Assert.Equal(750m, await Balance(c, "materialId", s.Material.Id, s.Store.Id));
        var afterIssue = await Get(c, order.Id);
        Assert.Equal(ProductionOrderStatus.InProduction, afterIssue.Status);
        Assert.Equal(250m, afterIssue.Materials.Single(m => m.Id == mp.Id).Issued);
        Assert.Equal(0m, afterIssue.Materials.Single(m => m.Id == mp.Id).Reserved);

        Assert.Equal(HttpStatusCode.BadRequest, (await Report(c, order.Id, 10, 98, 2)).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await Report(c, order.Id, 10, 98, 2, s.Scrap.Id)).StatusCode);
        var tooMany = await Report(c, order.Id, 20, 99);
        Assert.Equal(HttpStatusCode.Conflict, tooMany.StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await Report(c, order.Id, 20, 97, 1, s.Scrap.Id)).StatusCode);

        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"/api/production/orders/{order.Id}/receipts", new FinishedGoodsInput(Today, 98m, s.Finished.Id))).StatusCode);
        var receipt = await (await c.Post($"/api/production/orders/{order.Id}/receipts", new FinishedGoodsInput(Today, 97m, s.Finished.Id))).Read<StockDocumentSummary>();
        Assert.Equal(MovementType.ProductionReceipt, receipt.Type);
        Assert.Equal(97m, await Balance(c, "productId", s.Product.Id, s.Finished.Id));
        var doc = await (await c.GetAsync($"/api/stock/documents/{receipt.Id}")).Read<StockDocumentOut>();
        Assert.Equal(25m, Assert.Single(doc.Movements).UnitCost);
        Assert.Equal(order.Reference.Replace(" ", ""), doc.Movements[0].LotCode);

        var progress = await Get(c, order.Id);
        Assert.Equal(97m, progress.Good);
        Assert.Equal(3m, progress.Scrap);
        Assert.Equal(97m, progress.Received);
        Assert.Equal(0m, progress.Receivable);
        Assert.Equal(0m, progress.WorkInProcess);

        var rec = await (await c.GetAsync($"/api/production/orders/{order.Id}/reconciliation")).Read<Reconciliation>();
        var line = Assert.Single(rec.Lines, l => l.MaterialId == s.Material.Id);
        Assert.Equal(250m, line.Issued);
        Assert.Equal(7.5m, line.InScrap);
        Assert.Equal(242.5m, line.InFinishedGoods);
        Assert.Equal(0m, line.Balance);
        Assert.Equal(2500m, rec.MaterialCost);

        Assert.Equal(HttpStatusCode.Conflict, (await Transition(c, order.Id, "close")).StatusCode);
        var finished = await (await Transition(c, order.Id, "finish")).Read<ProductionOrderOut>();
        Assert.Equal(ProductionOrderStatus.Finished, finished.Status);
        Assert.All(finished.Materials, m => Assert.Equal(0m, m.Reserved));
        Assert.Equal(HttpStatusCode.Conflict, (await Report(c, order.Id, 20, 1)).StatusCode);

        var blocked = await Transition(c, order.Id, "close");
        Assert.Equal(HttpStatusCode.Conflict, blocked.StatusCode);
        Assert.Contains(child.Reference, await blocked.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, (await Transition(c, child.Id, "cancel")).StatusCode);
        Assert.Equal(ProductionOrderStatus.Cancelled, (await (await Transition(c, child.Id, "cancel", "Comprado pronto")).Read<ProductionOrderOut>()).Status);
        var closed = await (await Transition(c, order.Id, "close")).Read<ProductionOrderOut>();
        Assert.Equal(ProductionOrderStatus.Closed, closed.Status);
        Assert.NotNull(closed.ClosedAt);
        var costed = await (await Transition(c, order.Id, "close-cost")).Read<ProductionOrderOut>();
        Assert.Equal(2500m, costed.MaterialCost);
        Assert.Equal(Math.Round(2500m / 97m, 6), costed.UnitCost);
        Assert.Equal(HttpStatusCode.Conflict, (await Transition(c, order.Id, "close-cost")).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"/api/production/orders/{order.Id}/issues", new IssueInput(Today, s.Store.Id))).StatusCode);
    }

    [Fact]
    public async Task Overrun_above_tolerance_needs_a_release()
    {
        var c = await api.AdminAsync();
        var s = await Arrange(c, componentStock: 200m);
        var order = await Create(c, s.Product.Id, 100m);
        Assert.Equal(HttpStatusCode.Conflict, (await Report(c, order.Id, 10, 5)).StatusCode);
        await c.Post($"/api/production/orders/{order.Id}/release", new ReleaseIn());

        Assert.Equal(HttpStatusCode.Created, (await Report(c, order.Id, 10, 103)).StatusCode);
        var over = await Report(c, order.Id, 10, 2);
        Assert.Equal(HttpStatusCode.Conflict, over.StatusCode);
        Assert.Contains("overrun", await over.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, (await c.Post($"/api/production/orders/{order.Id}/operations/10/overrun-releases", new OverrunIn(5m, " "))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await c.Post($"/api/production/orders/{order.Id}/operations/10/overrun-releases", new OverrunIn(5m, "Cliente aceitou"))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await Report(c, order.Id, 10, 2)).StatusCode);
        var o = await Get(c, order.Id);
        var op10 = o.Operations.Single(x => x.Sequence == 10);
        Assert.Equal(108m, op10.Limit);
        Assert.Equal(3m, op10.Remaining);
        Assert.Equal(105m, o.Operations.Single(x => x.Sequence == 20).Limit);

        Assert.Equal(HttpStatusCode.Created, (await Report(c, order.Id, 20, 100)).StatusCode);
        var reports = await (await c.GetAsync($"/api/production/reports?orderId={order.Id}")).Read<Page<ProductionReportOut>>();
        var first = reports.Items.Single(r => r.OperationSequence == 10 && r.GoodQuantity == 103);
        Assert.Equal(HttpStatusCode.Conflict, (await c.DeleteAsync($"/api/production/reports/{first.Id}")).StatusCode);
        var small = reports.Items.Single(r => r.OperationSequence == 10 && r.GoodQuantity == 2);
        Assert.Equal(HttpStatusCode.NoContent, (await c.DeleteAsync($"/api/production/reports/{small.Id}")).StatusCode);
        Assert.Equal(103m, (await Get(c, order.Id)).Operations.Single(x => x.Sequence == 10).Good);
    }

    [Fact]
    public async Task Outside_processing_sends_and_returns_with_service_cost()
    {
        var c = await api.AdminAsync();
        var s = await Arrange(c, componentStock: 200m);
        var supplier = await (await c.Post("/api/suppliers", new SupplierIn("Galvanica " + Code("G"), null, null, null))).Read<SupplierOut>();
        var order = await Create(c, s.Product.Id, 50m);
        var outsourced = await (await c.Put($"/api/production/orders/{order.Id}/operations/20/outsource", new OutsourceInput(supplier.Id, 5))).Read<ProductionOrderOut>();
        Assert.True(outsourced.Operations.Single(o => o.Sequence == 20).External);
        await c.Post($"/api/production/orders/{order.Id}/release", new ReleaseIn());
        await c.Post($"/api/production/orders/{order.Id}/issues", new IssueInput(Today, s.Store.Id));
        Assert.Equal(HttpStatusCode.Created, (await Report(c, order.Id, 10, 50)).StatusCode);

        Assert.Equal(HttpStatusCode.Conflict, (await Report(c, order.Id, 20, 10)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"/api/production/orders/{order.Id}/operations/10/outside-shipments", new OutsideSendInput(Today, 10m, null, null))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"/api/production/orders/{order.Id}/operations/20/outside-shipments", new OutsideSendInput(Today, 51m, null, null))).StatusCode);
        var shipment = await (await c.Post($"/api/production/orders/{order.Id}/operations/20/outside-shipments", new OutsideSendInput(Today, 50m, "1234", null))).Read<OutsideShipmentOut>();
        Assert.Equal(50m, shipment.Open);
        Assert.Equal(0m, (await Get(c, order.Id)).Operations.Single(o => o.Sequence == 20).Remaining);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Put($"/api/production/orders/{order.Id}/operations/20/outsource", new OutsourceInput(supplier.Id, 3))).StatusCode);

        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"/api/production/outside-shipments/{shipment.Id}/returns", new OutsideReturnInput(Today, 49m, 2m, 1.5m, s.Scrap.Id, "88", null))).StatusCode);
        var ret = await (await c.Post($"/api/production/outside-shipments/{shipment.Id}/returns", new OutsideReturnInput(Today, 48m, 2m, 1.5m, s.Scrap.Id, "88", null))).Read<ProductionReportOut>();
        Assert.Equal(20, ret.OperationSequence);
        Assert.Equal(shipment.Id, ret.OutsideShipmentId);
        var after = await (await c.GetAsync($"/api/production/outside-shipments/{shipment.Id}")).Read<OutsideShipmentOut>();
        Assert.Equal(0m, after.Open);
        Assert.Equal(72m, after.ServiceValue);

        var o = await Get(c, order.Id);
        Assert.Equal(48m, o.Receivable);
        await c.Post($"/api/production/orders/{order.Id}/receipts", new FinishedGoodsInput(Today, 48m, s.Finished.Id));
        var rec = await (await c.GetAsync($"/api/production/orders/{order.Id}/reconciliation")).Read<Reconciliation>();
        Assert.Equal(72m, rec.ServiceCost);
        Assert.Equal(1250m, rec.MaterialCost);
        Assert.Equal(Math.Round((1250m + 72m) / 48m, 6), rec.UnitCost);
    }

    [Fact]
    public async Task Status_rules_cancel_delete_stop_and_returns()
    {
        var c = await api.AdminAsync();
        var s = await Arrange(c, componentStock: 500m);
        var draft = await Create(c, s.Product.Id, 10m);
        Assert.Equal(HttpStatusCode.Conflict, (await Report(c, draft.Id, 10, 1)).StatusCode);
        var edited = await (await c.Put($"/api/production/orders/{draft.Id}", new OrderUpdateIn(20m, Today.AddDays(5), null, null, "dobrado"))).Read<ProductionOrderOut>();
        Assert.Equal(50m, edited.Materials.Single(m => m.MaterialId == s.Material.Id).Required);
        Assert.Equal(HttpStatusCode.NoContent, (await c.DeleteAsync($"/api/production/orders/{draft.Id}")).StatusCode);

        var order = await Create(c, s.Product.Id, 10m);
        await c.Post($"/api/production/orders/{order.Id}/release", new ReleaseIn());
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"/api/production/orders/{order.Id}/release", new ReleaseIn())).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Put($"/api/production/orders/{order.Id}", new OrderUpdateIn(11m, Today, null, null, null))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await c.DeleteAsync($"/api/production/orders/{order.Id}")).StatusCode);

        var mp = order.Materials.Single(m => m.MaterialId == s.Material.Id);
        await c.Post($"/api/production/orders/{order.Id}/issues", new IssueInput(Today, s.Store.Id, [new IssueLineInput(mp.Id, 30m)]));
        Assert.Equal(970m, await Balance(c, "materialId", s.Material.Id, s.Store.Id));
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"/api/production/orders/{order.Id}/material-returns", new IssueInput(Today, s.Store.Id, [new IssueLineInput(mp.Id, 31m)]))).StatusCode);
        var ret = await (await c.Post($"/api/production/orders/{order.Id}/material-returns", new IssueInput(Today, s.Store.Id, [new IssueLineInput(mp.Id, 5m)]))).Read<StockDocumentSummary>();
        Assert.Equal(MovementType.AdjustmentIn, ret.Type);
        Assert.Equal(975m, await Balance(c, "materialId", s.Material.Id, s.Store.Id));
        Assert.Equal(25m, (await Get(c, order.Id)).Materials.Single(m => m.Id == mp.Id).Issued);
        var docs = await (await c.GetAsync($"/api/production/orders/{order.Id}/stock-documents")).Read<List<StockDocumentSummary>>();
        Assert.Equal(2, docs.Count);

        var stop = await c.Post("/api/production/occurrences", new OccurrenceIn(Code("Q", 10), "Quebra de máquina", OccurrenceKind.Downtime, true));
        var breakdown = await stop.Read<OccurrenceOut>();
        Assert.Equal(HttpStatusCode.BadRequest, (await c.Post("/api/production/reports", new ReportInput(order.Id, 10, Today, 0, DowntimeHours: 2m, DowntimeOccurrenceId: s.Scrap.Id))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await c.Post("/api/production/reports", new ReportInput(order.Id, 10, Today, 4, DowntimeHours: 2m, DowntimeOccurrenceId: breakdown.Id, StartTime: new TimeOnly(22, 0), EndTime: new TimeOnly(2, 30)))).StatusCode);
        var stopped = await Get(c, order.Id);
        Assert.Equal(ProductionOrderStatus.Stopped, stopped.Status);
        Assert.Equal("Quebra de máquina", stopped.StatusReason);
        var reports = await (await c.GetAsync($"/api/production/reports?orderId={order.Id}")).Read<Page<ProductionReportOut>>();
        Assert.Equal(4.5m, Assert.Single(reports.Items).Hours);
        Assert.Equal(s.Machine.Id, reports.Items[0].MachineId);
        Assert.Equal(HttpStatusCode.Conflict, (await Report(c, order.Id, 10, 1)).StatusCode);
        Assert.Equal(ProductionOrderStatus.InProduction, (await (await Transition(c, order.Id, "resume")).Read<ProductionOrderOut>()).Status);
        Assert.Equal(HttpStatusCode.Created, (await Report(c, order.Id, 10, 1)).StatusCode);

        Assert.Equal(HttpStatusCode.Conflict, (await Transition(c, order.Id, "cancel", "Cliente desistiu")).StatusCode);
        var cancelled = await (await Transition(c, order.Id, "cancel", "Cliente desistiu", technical: true)).Read<ProductionOrderOut>();
        Assert.Equal(ProductionOrderStatus.Cancelled, cancelled.Status);
        Assert.All(cancelled.Materials, m => Assert.Equal(0m, m.Reserved));
        Assert.Equal(HttpStatusCode.Conflict, (await Transition(c, order.Id, "resume")).StatusCode);
    }

    [Fact]
    public async Task Backward_schedule_respects_calendar_and_feeds_machine_load()
    {
        var c = await api.AdminAsync();
        var s = await Arrange(c, materialStock: 0, componentStock: 0);
        (await c.Post("/api/production/holidays", new HolidayIn(new DateOnly(2031, 3, 4), "Carnaval"))).EnsureSuccessStatusCode();
        var order = await Create(c, s.Product.Id, 1000m, new DateOnly(2031, 3, 12));
        var result = Assert.Single(await (await c.Post($"/api/production/orders/{order.Id}/schedule", new { })).Read<List<ScheduleResult>>());
        Assert.False(result.Late);
        Assert.Equal(new DateOnly(2031, 3, 5), result.Operations.Single(o => o.Sequence == 20).Start);
        Assert.Equal(new DateOnly(2031, 3, 12), result.Operations.Single(o => o.Sequence == 20).End);
        Assert.Equal(41m, result.Operations.Single(o => o.Sequence == 20).Hours);
        Assert.Equal(new DateOnly(2031, 2, 28), result.Operations.Single(o => o.Sequence == 10).Start);
        Assert.Equal(new DateOnly(2031, 2, 28), result.PlannedStart);
        Assert.Equal(new DateOnly(2031, 2, 28), (await Get(c, order.Id)).PlannedStart);

        var load = await (await c.GetAsync($"/api/production/load?from=2031-02-24&to=2031-03-09&groupBy=machine")).Read<List<LoadRow>>();
        var mine = load.Where(r => r.Id == s.Machine.Id).ToList();
        Assert.Equal(2, mine.Count);
        Assert.Equal(new LoadRow(s.Machine.Id, s.Machine.Code, new DateOnly(2031, 2, 24), 21m, 40m, 52.5m, 1), mine[0]);
        Assert.Equal(41m, mine[1].Hours);
        Assert.Equal(32m, mine[1].Capacity);

        var late = await Create(c, s.Product.Id, 100m, Today.AddDays(-3));
        var lr = Assert.Single(await (await c.Post($"/api/production/orders/{late.Id}/schedule", new { })).Read<List<ScheduleResult>>());
        Assert.True(lr.Late);
        Assert.True(lr.AdjustedStart >= Today);
        Assert.True(lr.AdjustedEnd >= lr.AdjustedStart);

        var parent = await Create(c, s.Product.Id, 10m, new DateOnly(2031, 3, 12));
        var child = await Create(c, s.Component.Id, 10m, new DateOnly(2031, 6, 1), parent.Id);
        var tree = await (await c.Post($"/api/production/orders/{parent.Id}/schedule", new { })).Read<List<ScheduleResult>>();
        Assert.Equal(2, tree.Count);
        var childResult = tree.Single(t => t.OrderId == child.Id);
        Assert.True(childResult.PlannedEnd < tree.Single(t => t.OrderId == parent.Id).Operations.Single(o => o.Sequence == 20).Start);
        Assert.Contains("Sem operação", childResult.Warnings);
    }

    [Fact]
    public async Task What_if_availability_explodes_bom_and_shows_open_purchase_orders()
    {
        var c = await api.AdminAsync();
        var s = await Arrange(c, materialStock: 100m);
        var top = await (await c.Post("/api/products", Tube(Code("T")))).Read<ProductOut>();
        var op = await (await c.Post($"/api/products/{top.Id}/routing", new RoutingOperationIn(10, null, s.Machine.Id, null, null, null, 10m, null, "Solda", null, null))).Read<RoutingOperationOut>();
        (await c.Post($"/api/routing-operations/{op.Id}/items", new BomItemIn(null, s.Product.Id, 2m, "PC"))).EnsureSuccessStatusCode();
        var supplier = await (await c.Post("/api/suppliers", new SupplierIn("Usina " + Code("U"), null, null, null))).Read<SupplierOut>();
        (await c.Post("/api/purchase-orders", new OrderIn(supplier.Id, null, null, [new OrderLineIn(s.Material.Id, null, null, 400m, 9m, 0, 0, 0, Today.AddDays(10), null)]))).EnsureSuccessStatusCode();

        var res = await (await c.Post("/api/production/availability", new AvailabilityCheckIn(top.Id, 30m))).Read<AvailabilityResult>();
        Assert.False(res.Complete);
        var line = Assert.Single(res.Lines);
        Assert.Equal(s.Material.Id, line.MaterialId);
        Assert.Equal(150m, line.Required);
        Assert.Equal(100m, line.Free);
        Assert.Equal(400m, line.OnOrder);
        Assert.Equal(50m, line.Shortage);
        Assert.Equal(HttpStatusCode.NotFound, (await c.Post("/api/production/availability", new AvailabilityCheckIn(int.MaxValue, 1m))).StatusCode);
    }

    [Fact]
    public async Task Internal_orders_use_their_own_numbering()
    {
        var c = await api.AdminAsync();
        var s = await Arrange(c, materialStock: 0, componentStock: 0);
        var opi = await (await c.Post("/api/production/orders", new ProductionOrderIn(s.Product.Id, 5m, Today, ProductionOrderKind.Internal, Bales: 3))).Read<ProductionOrderOut>();
        Assert.StartsWith("OPI ", opi.Reference);
        Assert.Equal(3, opi.Bales);
        var page = await (await c.GetAsync($"/api/production/orders?kind=Internal&productId={s.Product.Id}")).Read<Page<ProductionOrderSummaryOut>>();
        Assert.Equal(opi.Id, Assert.Single(page.Items).Id);
        Assert.Equal(HttpStatusCode.BadRequest, (await c.Post("/api/production/orders", new ProductionOrderIn(s.Product.Id, 0m, Today))).StatusCode);
    }

    [Fact]
    public async Task Concurrent_reports_cannot_exceed_the_operation_limit()
    {
        var c = await api.AdminAsync();
        var s = await Arrange(c, componentStock: 500m);
        var order = await Create(c, s.Product.Id, 100m);
        await c.Post($"/api/production/orders/{order.Id}/release", new ReleaseIn());
        var results = await Task.WhenAll(Enumerable.Range(0, 6).Select(async _ => (await Report(await api.AdminAsync(), order.Id, 10, 30)).StatusCode));
        Assert.Equal(3, results.Count(r => r == HttpStatusCode.Created));
        Assert.Equal(3, results.Count(r => r == HttpStatusCode.Conflict));
        Assert.Equal(90m, (await Get(c, order.Id)).Operations.Single(o => o.Sequence == 10).Good);
    }
}
