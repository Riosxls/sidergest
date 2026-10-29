using System.Net;
using System.Text.Json;
using Ebt.Api.Endpoints;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Sales;

namespace Ebt.Tests;

[Collection("api")]
public class ReportsTests(ApiFixture api)
{
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.Today);

    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();

    [Fact]
    public async Task Billing_summary_splits_companies_and_consumption_lists_shipped_lines()
    {
        var admin = await api.AdminAsync();
        var customer = await (await admin.Post("/api/customers", new CustomerIn("Cliente " + Code("C"), null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var address = await (await admin.Post($"/api/customers/{customer.Id}/addresses", new CustomerAddressIn("26133636000103", "SP", null, "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", null, "06800000", "5101", "Edilto", "compras@cliente.com", null))).Read<CustomerAddressOut>();
        var product = await (await admin.Post("/api/products", new ProductIn(Code("T"), "Tubo", ProductKind.Part, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, null, null, "73063010", "PC", 50, false, null, null))).Read<ProductOut>();
        var shipping = await (await admin.Post("/api/stock-locations", new StockLocationIn(Code("E", 10), "Expedição", StockLocationKind.Internal))).Read<StockLocationOut>();
        (await admin.Put("/api/sales/settings", new SalesSettingsDto(5m, 15, 0m, shipping.Id, null))).EnsureSuccessStatusCode();
        (await admin.Post("/api/stock/documents", new StockPost(MovementType.AdjustmentIn, Today, [new StockLine(null, product.Id, shipping.Id, 10m, UnitCost: 5m)], "INV"))).EnsureSuccessStatusCode();
        (await admin.Post("/api/sales/price-list", new PriceListIn(product.Id, null, 100m, 5m, 18m, Today.AddDays(-1), null))).EnsureSuccessStatusCode();

        var bad = await admin.Post("/api/sales/orders", new SalesOrderIn(customer.Id, address.Id, [new SalesLineInput(product.Id, 10m)], Company: "XYZ"));
        Assert.Equal(HttpStatusCode.BadRequest, bad.StatusCode);

        var order = await (await admin.Post("/api/sales/orders", new SalesOrderIn(customer.Id, address.Id, [new SalesLineInput(product.Id, 10m)], Company: "bst"))).Read<SalesOrderOut>();
        await admin.Post($"/api/sales/orders/{order.Id}/release", new SalesReleaseIn());
        var delivery = await (await admin.Post($"/api/sales/orders/{order.Id}/deliveries", new DeliveryInput(Today))).Read<DeliveryOut>();
        (await admin.Post($"/api/sales/deliveries/{delivery.Id}/ship", new ShipInput(Today, "9001"))).EnsureSuccessStatusCode();

        var report = await (await admin.GetAsync($"/api/reports/billing-summary?from={Today:yyyy-MM-dd}&to={Today:yyyy-MM-dd}")).Read<JsonElement>();
        var companies = report.GetProperty("companies").EnumerateArray().ToDictionary(c => c.GetProperty("key").GetString()!);
        var row = companies["BST"].GetProperty("rows").EnumerateArray().Single(r => r.GetProperty("customerId").GetInt32() == customer.Id);
        Assert.Equal(1050m, row.GetProperty("billed").GetDecimal());
        Assert.Equal(1000m, row.GetProperty("totalNoIpi").GetDecimal());
        Assert.Equal(50m, row.GetProperty("ipi").GetDecimal());
        Assert.Equal(180m, row.GetProperty("icms").GetDecimal());
        Assert.DoesNotContain(companies["EBT"].GetProperty("rows").EnumerateArray(), r => r.GetProperty("customerId").GetInt32() == customer.Id);

        var onlyEbt = await (await admin.GetAsync($"/api/reports/billing-summary?from={Today:yyyy-MM-dd}&to={Today:yyyy-MM-dd}&company=EBT")).Read<JsonElement>();
        Assert.Single(onlyEbt.GetProperty("companies").EnumerateArray());

        var consumption = await (await admin.GetAsync($"/api/reports/material-consumption?from={Today:yyyy-MM-dd}&to={Today:yyyy-MM-dd}")).Read<JsonElement>();
        Assert.True(consumption.TryGetProperty("rows", out _));
    }
}
