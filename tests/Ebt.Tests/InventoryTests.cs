using System.Net.Http.Json;
using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;

namespace Ebt.Tests;

[Collection("api")]
public class InventoryTests(ApiFixture api)
{
    private static readonly DateOnly Today = Ebt.Core.Services.Clock.Today();

    private static string Code(string prefix) => $"{prefix}{Guid.NewGuid():N}"[..12].ToUpper();

    private static async Task<MaterialOut> Material(HttpClient c, decimal? thickness = 1.5m, bool inspection = false) =>
        await (await c.Post("/api/materials", new MaterialIn(Code("M"), "Bobina", null, null, null, "KG", "KG", 1m, thickness, 80m, null, null, null, null, null, inspection, true, false))).Read<MaterialOut>();

    private static async Task<StockLocationOut> Location(HttpClient c, StockLocationKind kind = StockLocationKind.Internal) =>
        await (await c.Post("/api/stock-locations", new StockLocationIn(Code("L")[..10], "Local", kind))).Read<StockLocationOut>();

    private static async Task<StockDocumentOut> Post(HttpClient c, MovementType type, DateOnly date, params StockLine[] lines) =>
        await (await c.Post("/api/stock/documents", new StockPost(type, date, lines, "REF-" + type))).Read<StockDocumentOut>();

    private static Task<HttpResponseMessage> TryPost(HttpClient c, MovementType type, DateOnly date, params StockLine[] lines) =>
        c.Post("/api/stock/documents", new StockPost(type, date, lines));

    private static async Task<AvailabilityOut> Availability(HttpClient c, int materialId) =>
        await (await c.GetAsync($"/api/stock/availability?materialId={materialId}")).Read<AvailabilityOut>();

    private static async Task<decimal> Balance(HttpClient c, int materialId, int locationId) =>
        (await (await c.GetAsync($"/api/stock/balances?materialId={materialId}&locationId={locationId}")).Read<Page<StockBalanceOut>>()).Items.Sum(b => b.Quantity);

    [Fact]
    public async Task Roles_guard_stock_writes()
    {
        var admin = await api.AdminAsync();
        var m = await Material(admin);
        var loc = await Location(admin);
        var line = new StockLine(m.Id, null, loc.Id, 10m, UnitCost: 5m);

        var reader = await api.UserAsync(UserRole.Reader);
        var engineering = await api.UserAsync(UserRole.Engineering);
        var stock = await api.UserAsync(UserRole.Stock);
        Assert.Equal(HttpStatusCode.Forbidden, (await TryPost(reader, MovementType.Receipt, Today, line)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await TryPost(engineering, MovementType.Receipt, Today, line)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await engineering.Post("/api/stock-locations", new StockLocationIn("X1", "X", StockLocationKind.Internal))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await TryPost(stock, MovementType.Receipt, Today, line)).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await stock.Post("/api/stock-locations", new StockLocationIn(Code("S")[..10], "Stock", StockLocationKind.Internal))).StatusCode);
        Assert.Equal(10m, await Balance(reader, m.Id, loc.Id));
        Assert.Equal(HttpStatusCode.Forbidden, (await stock.Put("/api/stock/settings", new StockSettingsIn(false, true, 0, 0, 0))).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().GetAsync("/api/stock/balances")).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await admin.DeleteAsync($"/api/stock-locations/{loc.Id}")).StatusCode);
    }

    [Fact]
    public async Task Receipts_create_lots_and_issues_consume_fifo_with_fractional_quantities()
    {
        var c = await api.AdminAsync();
        var m = await Material(c);
        var loc = await Location(c);
        var first = await Post(c, MovementType.Receipt, Today.AddDays(-2), new StockLine(m.Id, null, loc.Id, 100.75m, LotCode: "A1", UnitCost: 10m, HeatNumber: "C123"));
        await Post(c, MovementType.Receipt, Today.AddDays(-1), new StockLine(m.Id, null, loc.Id, 50.5m, UnitCost: 12m));
        Assert.Equal("A1", Assert.Single(first.Movements).LotCode);

        var issue = await Post(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 120.25m));
        Assert.Equal(2, issue.Movements.Count);
        Assert.Equal(-100.75m, issue.Movements[0].Quantity);
        Assert.Equal("A1", issue.Movements[0].LotCode);
        Assert.Equal(-19.5m, issue.Movements[1].Quantity);
        Assert.Equal(31m, await Balance(c, m.Id, loc.Id));

        var tooMuch = await TryPost(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 31.0001m));
        Assert.Equal(HttpStatusCode.Conflict, tooMuch.StatusCode);
        Assert.Equal(31m, await Balance(c, m.Id, loc.Id));

        var kardex = await (await c.GetAsync($"/api/stock/movements?materialId={m.Id}")).Read<Page<StockMovementOut>>();
        Assert.Equal([100.75m, 151.25m, 50.5m, 31m], kardex.Items.Select(x => x.BalanceAfter!.Value));

        var lots = await (await c.GetAsync($"/api/stock/lots?materialId={m.Id}")).Read<Page<StockLotOut>>();
        Assert.Equal(2, lots.Total);
        Assert.Contains(lots.Items, l => l.Code == "A1" && l.HeatNumber == "C123" && l.Quantity == 0m);
    }

    [Fact]
    public async Task Quarantined_lots_cannot_be_issued_until_released()
    {
        var c = await api.AdminAsync();
        var m = await Material(c, inspection: true);
        var loc = await Location(c);
        var doc = await Post(c, MovementType.Receipt, Today, new StockLine(m.Id, null, loc.Id, 40m, UnitCost: 7m));
        var lotId = doc.Movements[0].LotId!.Value;

        var a = await Availability(c, m.Id);
        Assert.Equal(40m, a.OnHand);
        Assert.Equal(40m, a.Blocked);
        Assert.Equal(0m, a.Free);
        Assert.Equal(HttpStatusCode.Conflict, (await TryPost(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 1m))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await TryPost(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 1m, LotId: lotId))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await c.Put($"/api/stock/lots/{lotId}/inspection", new InspectionIn(LotStatus.Rejected, null))).StatusCode);

        var lot = await (await c.Put($"/api/stock/lots/{lotId}/inspection", new InspectionIn(LotStatus.Released, "Laudo OK"))).Read<StockLotOut>();
        Assert.Equal(LotStatus.Released, lot.Status);
        Assert.Equal(ApiFixture.AdminUser, lot.InspectedBy);
        await Post(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 15m));
        Assert.Equal(25m, (await Availability(c, m.Id)).Free);
    }

    [Fact]
    public async Task Transfers_and_third_party_processing_move_stock_between_locations()
    {
        var c = await api.AdminAsync();
        var coil = await Material(c, 2m);
        var slit = await Material(c, 2m);
        var store = await Location(c);
        var line = await Location(c);
        var supplier = await Location(c, StockLocationKind.ThirdParty);
        await Post(c, MovementType.Receipt, Today, new StockLine(coil.Id, null, store.Id, 1000m, UnitCost: 6m));

        await Post(c, MovementType.Transfer, Today, new StockLine(coil.Id, null, line.Id, 200m, FromLocationId: store.Id));
        Assert.Equal(800m, await Balance(c, coil.Id, store.Id));
        Assert.Equal(200m, await Balance(c, coil.Id, line.Id));

        Assert.Equal(HttpStatusCode.BadRequest, (await TryPost(c, MovementType.ThirdPartySend, Today, new StockLine(coil.Id, null, line.Id, 1m, FromLocationId: store.Id))).StatusCode);
        await Post(c, MovementType.ThirdPartySend, Today, new StockLine(coil.Id, null, supplier.Id, 500m, FromLocationId: store.Id));
        var back = await Post(c, MovementType.ThirdPartyReturn, Today,
            new StockLine(slit.Id, null, store.Id, 495.5m, FromLocationId: supplier.Id, SourceMaterialId: coil.Id, SourceQuantity: 500m, UnitCost: 0.35m));
        Assert.Equal(2, back.Movements.Count);
        Assert.Equal(0m, await Balance(c, coil.Id, supplier.Id));
        Assert.Equal(495.5m, await Balance(c, slit.Id, store.Id));

        var a = await Availability(c, coil.Id);
        Assert.Equal(500m, a.OnHand);
        Assert.Equal(0m, a.AtThirdParty);
    }

    [Fact]
    public async Task Reservations_protect_stock_and_are_consumed_by_issues()
    {
        var c = await api.AdminAsync();
        var m = await Material(c, null);
        var loc = await Location(c);
        await Post(c, MovementType.Receipt, Today, new StockLine(m.Id, null, loc.Id, 100m, UnitCost: 3m));

        var r = await (await c.Post("/api/stock/reservations", new ReservationIn(m.Id, null, null, 70m, "OF 500400", null))).Read<ReservationOut>();
        Assert.Equal(30m, (await Availability(c, m.Id)).Free);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post("/api/stock/reservations", new ReservationIn(m.Id, null, null, 31m, "OF 2", null))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await TryPost(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 40m))).StatusCode);

        var issue = await Post(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 40m, ReservationId: r.Id));
        Assert.Equal(r.Id, issue.Movements[0].ReservationId);
        var after = await (await c.GetAsync($"/api/stock/reservations?reference=OF%20500400")).Read<Page<ReservationOut>>();
        Assert.Equal(30m, Assert.Single(after.Items).Remaining);
        Assert.Equal(30m, (await Availability(c, m.Id)).Free);

        await Post(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 30m, ReservationId: r.Id));
        var done = await (await c.GetAsync($"/api/stock/reservations?reference=OF%20500400")).Read<Page<ReservationOut>>();
        Assert.Equal(ReservationStatus.Consumed, done.Items[0].Status);

        var r2 = await (await c.Post("/api/stock/reservations", new ReservationIn(m.Id, null, null, 10m, "OF 3", null))).Read<ReservationOut>();
        Assert.Equal(20m, (await Availability(c, m.Id)).Free);
        await (await c.PostAsync($"/api/stock/reservations/{r2.Id}/release", null)).Read<ReservationOut>();
        Assert.Equal(30m, (await Availability(c, m.Id)).Free);
        Assert.Equal(HttpStatusCode.Conflict, (await c.PostAsync($"/api/stock/reservations/{r2.Id}/release", null)).StatusCode);
    }

    [Fact]
    public async Task Reversal_undoes_a_document_once_and_inventory_count_adjusts()
    {
        var c = await api.AdminAsync();
        var m = await Material(c, null);
        var loc = await Location(c);
        var receipt = await Post(c, MovementType.Receipt, Today, new StockLine(m.Id, null, loc.Id, 60m, UnitCost: 2m, LotCode: "R1"));
        var issue = await Post(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 20m));

        Assert.Equal(HttpStatusCode.Conflict, (await c.PostAsync($"/api/stock/documents/{receipt.Id}/reverse", null)).StatusCode);
        var rev = await (await c.Post($"/api/stock/documents/{issue.Id}/reverse", new ReverseIn("lançado errado"))).Read<StockDocumentOut>();
        Assert.Equal(MovementType.Reversal, rev.Type);
        Assert.Equal(issue.Id, rev.ReversalOfId);
        Assert.Equal(60m, await Balance(c, m.Id, loc.Id));
        Assert.Equal(HttpStatusCode.Conflict, (await c.PostAsync($"/api/stock/documents/{issue.Id}/reverse", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await c.PostAsync($"/api/stock/documents/{rev.Id}/reverse", null)).StatusCode);

        var count = await Post(c, MovementType.InventoryCount, Today, new StockLine(m.Id, null, loc.Id, 57.5m, LotId: receipt.Movements[0].LotId));
        Assert.Equal(-2.5m, Assert.Single(count.Movements).Quantity);
        Assert.Equal(57.5m, await Balance(c, m.Id, loc.Id));
        Assert.Equal(HttpStatusCode.BadRequest, (await TryPost(c, MovementType.InventoryCount, Today, new StockLine(m.Id, null, loc.Id, 57.5m, LotId: receipt.Movements[0].LotId))).StatusCode);
    }

    [Fact]
    public async Task Monthly_close_computes_weighted_average_per_thickness_without_truncating_kg()
    {
        var c = await api.AdminAsync();
        (await c.Put("/api/stock/settings", new StockSettingsIn(false, true, 0.20m, 1.00m, 5m))).EnsureSuccessStatusCode();
        var thickness = 9m + Random.Shared.Next(1, 999) / 1000m;
        var a = await Material(c, thickness);
        var b = await Material(c, thickness);
        var loc = await Location(c);
        var third = await Location(c, StockLocationKind.ThirdParty);

        var jan = new DateOnly(2001, 1, 10);
        var feb = new DateOnly(2001, 2, 5);
        var stock = await api.UserAsync(UserRole.Stock);
        await Post(stock, MovementType.OpeningBalance, new DateOnly(2000, 12, 31), new StockLine(a.Id, null, loc.Id, 200m, UnitCost: 8m));
        await Post(stock, MovementType.Receipt, jan, new StockLine(a.Id, null, loc.Id, 100.6m, UnitCost: 10m, IcmsRate: 12m));
        await Post(stock, MovementType.Receipt, jan, new StockLine(b.Id, null, loc.Id, 50.7m, UnitCost: 12m));
        await Post(stock, MovementType.ThirdPartySend, jan, new StockLine(a.Id, null, third.Id, 30m, FromLocationId: loc.Id));
        await Post(stock, MovementType.ThirdPartyReturn, jan, new StockLine(b.Id, null, loc.Id, 29.9m, FromLocationId: third.Id, SourceMaterialId: a.Id, SourceQuantity: 30m, UnitCost: 1.5m));

        var preview = await (await c.GetAsync("/api/stock/average-costs/preview?period=200101")).Read<List<AverageCostOut>>();
        var row = Assert.Single(preview, r => r.ThicknessMm == thickness);

        var purchaseValue = 100.6m * 10m * 0.88m + 50.7m * 12m;
        var serviceValue = 29.9m * 1.5m + 29.9m * 0.20m;
        var inflow = 100.6m + 50.7m + 29.9m;
        var m = (purchaseValue + serviceValue) / inflow;
        m += 0.05m * (m - 1.00m);
        var expected = Math.Round((8m * 200m + m * inflow) / (200m + inflow), 6);
        Assert.Equal(200m, row.OpeningQuantity);
        Assert.Equal(8m, row.OpeningAverage);
        Assert.Equal(151.3m, row.PurchaseQuantity);
        Assert.Equal(29.9m, row.ServiceQuantity);
        Assert.Equal(expected, row.Average);

        var truncated = (8m * 200m + ((100 * 10m * 0.88m + 50 * 12m + 29 * 1.5m + 29 * 0.2m) / 179m * 1.05m - 0.05m) * 179m) / 379m;
        Assert.NotEqual(Math.Round(truncated, 6), row.Average);

        Assert.Equal(HttpStatusCode.Forbidden, (await (await api.UserAsync(UserRole.Reader)).PostAsync("/api/stock/closings/200101", null)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await c.PostAsync($"/api/stock/closings/{StockService.PeriodOf(Today)}", null)).StatusCode);
        (await stock.PostAsync("/api/stock/closings/200101", null)).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Conflict, (await stock.PostAsync("/api/stock/closings/200101", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await stock.PostAsync("/api/stock/closings/200103", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await TryPost(stock, MovementType.Receipt, jan, new StockLine(a.Id, null, loc.Id, 1m, UnitCost: 1m))).StatusCode);

        var issue = await Post(stock, MovementType.Issue, feb, new StockLine(a.Id, null, loc.Id, 10m));
        Assert.All(issue.Movements, x => Assert.Equal(expected, x.UnitCost));
        Assert.Equal(expected, (await Availability(c, b.Id)).AverageCost);

        await Post(stock, MovementType.Receipt, feb, new StockLine(b.Id, null, loc.Id, 20.5m, UnitCost: 11m));
        (await stock.PostAsync("/api/stock/closings/200102", null)).EnsureSuccessStatusCode();
        var febRow = (await (await c.GetAsync($"/api/stock/average-costs?period=200102&thicknessMm={thickness.ToString(System.Globalization.CultureInfo.InvariantCulture)}")).Read<List<AverageCostOut>>()).Single();
        var openingFeb = 200m + 100.6m + 50.7m + 29.9m - 30m;
        var mFeb = 11m + 0.05m * (11m - 1m);
        Assert.Equal(openingFeb, febRow.OpeningQuantity);
        Assert.Equal(Math.Round((expected * openingFeb + mFeb * 20.5m) / (openingFeb + 20.5m), 6), febRow.Average);

        Assert.Equal(HttpStatusCode.Forbidden, (await stock.DeleteAsync("/api/stock/closings/200102")).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await c.DeleteAsync("/api/stock/closings/200101")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await c.DeleteAsync("/api/stock/closings/200102")).StatusCode);
        Assert.Empty(await (await c.GetAsync($"/api/stock/average-costs?period=200102&thicknessMm={thickness.ToString(System.Globalization.CultureInfo.InvariantCulture)}")).Read<List<AverageCostOut>>());
        await Post(stock, MovementType.Receipt, feb, new StockLine(b.Id, null, loc.Id, 1m, UnitCost: 11m));
        Assert.Equal(HttpStatusCode.NoContent, (await c.DeleteAsync("/api/stock/closings/200101")).StatusCode);
        (await c.Put("/api/stock/settings", new StockSettingsIn(false, true, 0, 0, 0))).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task Concurrent_issues_never_overdraw()
    {
        var c = await api.AdminAsync();
        var m = await Material(c, null);
        var loc = await Location(c);
        await Post(c, MovementType.Receipt, Today, new StockLine(m.Id, null, loc.Id, 10m, UnitCost: 1m));
        var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => TryPost(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 3m))));
        Assert.Equal(3, results.Count(r => r.StatusCode == HttpStatusCode.Created));
        Assert.All(results.Where(r => r.StatusCode != HttpStatusCode.Created), r => Assert.Equal(HttpStatusCode.Conflict, r.StatusCode));
        Assert.Equal(1m, await Balance(c, m.Id, loc.Id));
    }

    [Fact]
    public async Task Stock_document_reversal_honours_if_match()
    {
        var c = await api.AdminAsync();
        var m = await Material(c);
        var loc = await Location(c);
        var doc = await Post(c, MovementType.Receipt, Today, new StockLine(m.Id, null, loc.Id, 5m, UnitCost: 2m));
        var etag = (await c.GetAsync($"/api/stock/documents/{doc.Id}")).Headers.ETag?.ToString();
        Assert.False(string.IsNullOrEmpty(etag));

        var stale = new HttpRequestMessage(HttpMethod.Post, $"/api/stock/documents/{doc.Id}/reverse") { Content = JsonContent.Create(new ReverseIn(null), options: ApiFixture.Json) };
        stale.Headers.TryAddWithoutValidation("If-Match", "\"1\"");
        Assert.Equal(HttpStatusCode.PreconditionFailed, (await c.SendAsync(stale)).StatusCode);

        var fresh = new HttpRequestMessage(HttpMethod.Post, $"/api/stock/documents/{doc.Id}/reverse") { Content = JsonContent.Create(new ReverseIn(null), options: ApiFixture.Json) };
        fresh.Headers.TryAddWithoutValidation("If-Match", etag);
        Assert.Equal(HttpStatusCode.Created, (await c.SendAsync(fresh)).StatusCode);
    }
}
