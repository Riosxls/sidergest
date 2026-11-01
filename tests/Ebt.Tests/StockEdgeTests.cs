using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;

namespace Ebt.Tests;

/// <summary>Validation, conflict and not-found branches of StockService.</summary>
[Collection("api")]
public class StockEdgeTests(ApiFixture api)
{
    private static readonly DateOnly Today = Ebt.Core.Services.Clock.Today();

    private static string Code(string prefix) => $"{prefix}{Guid.NewGuid():N}"[..12].ToUpper();

    private static async Task<MaterialOut> Material(HttpClient c, bool inspection = false) =>
        await (await c.Post("/api/materials", new MaterialIn(Code("M"), "Bobina", null, null, null, "KG", "KG", 1m, 1.5m, 80m, null, null, null, null, null, inspection, true, false))).Read<MaterialOut>();

    private static async Task<ProductOut> Product(HttpClient c) =>
        await (await c.Post("/api/products", new ProductIn(Code("P"), "Tubo", ProductKind.Part, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, null, null, "73063010", "PC", 50, false, null, null))).Read<ProductOut>();

    private static async Task<StockLocationOut> Location(HttpClient c, StockLocationKind kind = StockLocationKind.Internal, bool active = true)
    {
        var l = await (await c.Post("/api/stock-locations", new StockLocationIn(Code("L")[..10], "Local", kind))).Read<StockLocationOut>();
        if (!active) (await c.Put($"/api/stock-locations/{l.Id}", new StockLocationIn(l.Code, l.Name, kind, false))).EnsureSuccessStatusCode();
        return l;
    }

    private static Task<HttpResponseMessage> TryPost(HttpClient c, MovementType type, DateOnly date, params StockLine[] lines) =>
        c.Post("/api/stock/documents", new StockPost(type, date, lines));

    private static async Task<StockDocumentOut> Post(HttpClient c, MovementType type, DateOnly date, params StockLine[] lines) =>
        await (await TryPost(c, type, date, lines)).Read<StockDocumentOut>();

    private static async Task AssertStatus(HttpStatusCode expected, Task<HttpResponseMessage> call) => Assert.Equal(expected, (await call).StatusCode);

    [Fact]
    public async Task Posting_validation_errors()
    {
        var c = await api.AdminAsync();
        var m = await Material(c);
        var p = await Product(c);
        var loc = await Location(c);
        var other = await Location(c);
        var dormant = await Location(c, active: false);

        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.Reversal, Today, new StockLine(m.Id, null, loc.Id, 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(null, null, loc.Id, 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, p.Id, loc.Id, 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, loc.Id, 0m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.InventoryCount, Today, new StockLine(m.Id, null, loc.Id, -1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, loc.Id, 1m, UnitCost: -1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, loc.Id, 1m, IcmsRate: 101m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, loc.Id, 1m, IcmsRate: -1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, loc.Id, 1m, FromLocationId: other.Id)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.Transfer, Today, new StockLine(m.Id, null, loc.Id, 1m, FromLocationId: loc.Id)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, loc.Id, 1m, ReservationId: 1)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, loc.Id, 1m, SourceMaterialId: m.Id)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.ThirdPartyReturn, Today, new StockLine(null, p.Id, loc.Id, 1m, SourceMaterialId: m.Id, UnitCost: 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.Receipt, Today, new StockLine(m.Id, null, loc.Id, 1m)));

        // master data lookups
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, 999_999, 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, dormant.Id, 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.Transfer, Today, new StockLine(m.Id, null, loc.Id, 1m, FromLocationId: 999_999)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(999_999, null, loc.Id, 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(null, 999_999, loc.Id, 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.ThirdPartyReturn, Today, new StockLine(m.Id, null, loc.Id, 1m, SourceMaterialId: 999_999, UnitCost: 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/stock/documents", new StockPost(MovementType.AdjustmentIn, Today, [new StockLine(m.Id, null, loc.Id, 1m)], SupplierId: 999_999)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/stock/documents", new StockPost(MovementType.AdjustmentIn, Today, [new StockLine(m.Id, null, loc.Id, 1m)], CustomerId: 999_999)));

        // nothing was posted by the failures; an inventory count equal to the balance results in zero quantity
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.InventoryCount, Today, new StockLine(m.Id, null, loc.Id, 0m)));
    }

    [Fact]
    public async Task Movement_type_specific_errors()
    {
        var c = await api.AdminAsync();
        var m = await Material(c);
        var loc = await Location(c);
        var other = await Location(c);
        var third = await Location(c, StockLocationKind.ThirdParty);
        await Post(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, loc.Id, 10m, UnitCost: 2m));

        // transfers and third-party movements need a source; shapes of the destination are checked
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.Transfer, Today, new StockLine(m.Id, null, other.Id, 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.ThirdPartySend, Today, new StockLine(m.Id, null, third.Id, 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.ThirdPartySend, Today, new StockLine(m.Id, null, other.Id, 1m, FromLocationId: loc.Id)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.ThirdPartyReturn, Today, new StockLine(m.Id, null, third.Id, 1m, FromLocationId: loc.Id, UnitCost: 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.ThirdPartyReturn, Today, new StockLine(m.Id, null, other.Id, 1m, FromLocationId: loc.Id, UnitCost: 1m)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.ThirdPartyReturn, Today, new StockLine(m.Id, null, other.Id, 1m, FromLocationId: third.Id)));

        // more than on hand: insufficient stock, with and without a pinned lot
        await AssertStatus(HttpStatusCode.Conflict, TryPost(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 11m)));
        await AssertStatus(HttpStatusCode.Conflict, TryPost(c, MovementType.Transfer, Today, new StockLine(m.Id, null, other.Id, 11m, FromLocationId: loc.Id)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 1m, LotId: 999_999)));

        // lots of another item are rejected for inbound and outbound lines
        var m2 = await Material(c);
        var lotDoc = await Post(c, MovementType.Receipt, Today, new StockLine(m2.Id, null, loc.Id, 5m, LotCode: Code("LT"), UnitCost: 3m));
        var foreignLot = lotDoc.Movements[0].LotId!.Value;
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 1m, LotId: foreignLot)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, loc.Id, 1m, LotId: foreignLot)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, loc.Id, 1m, LotId: 999_999)));
        // an existing lot code is reused instead of creating another lot
        var code = lotDoc.Movements[0].LotCode!;
        var again = await Post(c, MovementType.Receipt, Today, new StockLine(m2.Id, null, loc.Id, 2m, LotCode: code, UnitCost: 3m));
        Assert.Equal(foreignLot, again.Movements[0].LotId);

        // a material that needs inspection is quarantined on receipt and cannot be issued until released
        var inspected = await Material(c, inspection: true);
        var q = await Post(c, MovementType.Receipt, Today, new StockLine(inspected.Id, null, loc.Id, 5m, UnitCost: 3m, HeatNumber: " H1 "));
        await AssertStatus(HttpStatusCode.Conflict, TryPost(c, MovementType.Issue, Today, new StockLine(inspected.Id, null, loc.Id, 1m, LotId: q.Movements[0].LotId)));
        await AssertStatus(HttpStatusCode.Conflict, TryPost(c, MovementType.Issue, Today, new StockLine(inspected.Id, null, loc.Id, 1m)));
        // opting out of inspection per line releases the lot at once
        var free = await Post(c, MovementType.Receipt, Today, new StockLine(inspected.Id, null, loc.Id, 5m, UnitCost: 3m, RequiresInspection: false));
        (await TryPost(c, MovementType.Issue, Today, new StockLine(inspected.Id, null, loc.Id, 1m, LotId: free.Movements[0].LotId))).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task Reservation_errors_and_reversal_rules()
    {
        var c = await api.AdminAsync();
        var m = await Material(c);
        var m2 = await Material(c);
        var loc = await Location(c);
        await Post(c, MovementType.AdjustmentIn, Today, new StockLine(m.Id, null, loc.Id, 50m, UnitCost: 2m));
        await Post(c, MovementType.AdjustmentIn, Today, new StockLine(m2.Id, null, loc.Id, 50m, UnitCost: 2m));

        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/stock/reservations", new ReservationIn(m.Id, null, null, 0m, "OF 1", null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/stock/reservations", new ReservationIn(m.Id, null, null, 1m, " ", null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/stock/reservations", new ReservationIn(null, null, null, 1m, "OF 1", null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/stock/reservations", new ReservationIn(999_999, null, null, 1m, "OF 1", null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/stock/reservations", new ReservationIn(null, 999_999, null, 1m, "OF 1", null)));
        await AssertStatus(HttpStatusCode.BadRequest, c.Post("/api/stock/reservations", new ReservationIn(m.Id, null, 999_999, 1m, "OF 1", null)));
        await AssertStatus(HttpStatusCode.NotFound, c.PostAsync("/api/stock/reservations/999999/release", null));

        var r = await (await c.Post("/api/stock/reservations", new ReservationIn(m.Id, null, loc.Id, 10m, " OF 9 ", Today))).Read<ReservationOut>();
        Assert.Equal("OF 9", r.Reference);
        // a reservation for another item cannot be consumed; non-outbound documents cannot reference one
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.Issue, Today, new StockLine(m2.Id, null, loc.Id, 1m, ReservationId: r.Id)));
        await AssertStatus(HttpStatusCode.BadRequest, TryPost(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 1m, ReservationId: 999_999)));
        // the reserved quantity is not free for an unrelated issue
        await AssertStatus(HttpStatusCode.Conflict, TryPost(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 45m)));

        // consuming it fully, then reversing, reopens the reservation
        var issue = await Post(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 10m, ReservationId: r.Id));
        await AssertStatus(HttpStatusCode.Conflict, TryPost(c, MovementType.Issue, Today, new StockLine(m.Id, null, loc.Id, 1m, ReservationId: r.Id)));
        await AssertStatus(HttpStatusCode.Conflict, c.PostAsync($"/api/stock/reservations/{r.Id}/release", null));
        var reversal = await (await c.Post($"/api/stock/documents/{issue.Id}/reverse", new ReverseIn(null))).Read<StockDocumentOut>();
        var reopened = await (await c.GetAsync($"/api/stock/reservations?reference=OF%209")).Read<Page<ReservationOut>>();
        Assert.Equal(ReservationStatus.Open, Assert.Single(reopened.Items).Status);

        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/stock/documents/{reversal.Id}/reverse", new ReverseIn(null)));
        await AssertStatus(HttpStatusCode.Conflict, c.Post($"/api/stock/documents/{issue.Id}/reverse", new ReverseIn(null)));
        await AssertStatus(HttpStatusCode.NotFound, c.Post("/api/stock/documents/999999/reverse", new ReverseIn(null)));
    }
}
