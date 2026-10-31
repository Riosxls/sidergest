using System.Text.Json;
using Ebt.Api.Endpoints;
using Ebt.Core.Entities;

namespace Ebt.Tests;

[Collection("api")]
public class DashboardTests(ApiFixture api)
{
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.Today);

    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();

    private static ProductIn NewProduct(bool blocked = false) =>
        new(Code("D"), "Tubo dash", ProductKind.Part, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, null, null, "73063010", "PC", 50, blocked, null, null);

    [Fact]
    public async Task Product_dashboard_counts_without_listing_the_catalogue()
    {
        var admin = await api.AdminAsync();
        var before = await (await admin.GetAsync("/api/products/dashboard?top=1")).Read<ProductDashboardOut>();
        (await admin.Post("/api/products", NewProduct())).EnsureSuccessStatusCode();
        var blocked = await (await admin.Post("/api/products", NewProduct(blocked: true))).Read<ProductOut>();

        var after = await (await admin.GetAsync("/api/products/dashboard?top=1")).Read<ProductDashboardOut>();
        Assert.Equal(before.Total + 2, after.Total);
        Assert.Equal(before.ByKind.GetValueOrDefault("Part") + 2, after.ByKind["Part"]);
        Assert.Equal(before.OperationBuckets.GetValueOrDefault("0") + 2, after.OperationBuckets["0"]);
        Assert.Equal(before.BlockedTotal + 1, after.BlockedTotal);
        Assert.Equal(before.WithoutRoutingTotal + 2, after.WithoutRoutingTotal);
        Assert.Single(after.WithoutRouting);
        Assert.True(after.Blocked.Count <= 1);

        var full = await (await admin.GetAsync("/api/products/dashboard")).Read<ProductDashboardOut>();
        Assert.Contains(full.Blocked, p => p.Id == blocked.Id);
    }

    [Fact]
    public async Task Production_dashboard_splits_late_orders_into_recent_and_legacy()
    {
        var admin = await api.AdminAsync();
        var before = await (await admin.GetAsync("/api/production/orders/dashboard")).Read<ProductionDashboardOut>();
        var product = await (await admin.Post("/api/products", NewProduct())).Read<ProductOut>();
        var recent = await (await admin.Post("/api/production/orders", new ProductionOrderIn(product.Id, 5m, Today.AddDays(-5)))).Read<ProductionOrderOut>();
        var old = await (await admin.Post("/api/production/orders", new ProductionOrderIn(product.Id, 5m, Today.AddDays(-90)))).Read<ProductionOrderOut>();
        (await admin.Post("/api/production/orders", new ProductionOrderIn(product.Id, 5m, Today.AddDays(30)))).EnsureSuccessStatusCode();

        var after = await (await admin.GetAsync("/api/production/orders/dashboard")).Read<ProductionDashboardOut>();
        Assert.Equal(before.OpenTotal + 3, after.OpenTotal);
        Assert.Equal(before.ByStatus.GetValueOrDefault("Created") + 3, after.ByStatus["Created"]);
        Assert.Equal(before.LateFresh.Total + 1, after.LateFresh.Total);
        Assert.Equal(before.LateLegacy.Total + 1, after.LateLegacy.Total);
        Assert.Contains(after.LateFresh.Items, o => o.Id == recent.Id);
        Assert.DoesNotContain(after.LateFresh.Items, o => o.Id == old.Id);
        Assert.Contains(after.LateLegacy.Items, o => o.Id == old.Id);

        var capped = await (await admin.GetAsync("/api/production/orders/dashboard?top=1&legacyDays=1000")).Read<ProductionDashboardOut>();
        Assert.True(capped.LateFresh.Items.Count <= 1);
        Assert.Equal(0, capped.LateLegacy.Total);
    }

    [Fact]
    public async Task Open_purchase_order_summary_returns_total_and_top_suppliers()
    {
        var admin = await api.AdminAsync();
        var summary = await (await admin.GetAsync("/api/purchase-orders/open-summary?top=3")).Read<OpenOrdersSummaryOut>();
        Assert.True(summary.SupplierIds.Count <= 3);
        var list = await (await admin.GetAsync("/api/purchase-orders?open=true&take=1")).Read<JsonElement>();
        Assert.Equal(list.GetProperty("total").GetInt32(), summary.Total);
    }
}
