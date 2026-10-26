using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Core.Entities;
using Ebt.Core.Services;

namespace Ebt.Tests;

[Collection("api")]
public class EngineeringTests(ApiFixture api)
{
    private static string Code(string prefix) => $"{prefix}{Guid.NewGuid():N}"[..14].ToUpper();

    private static ProductIn Tube(string code, ProductKind kind = ProductKind.Part) =>
        new(code, "Tubo " + code, kind, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, null, 2m, "73063010", "PC", null, false, "A", "1");

    private static MaterialIn Steel(string code) =>
        new(code, "Bobina " + code, null, null, null, "KG", "KG", 1m, 1.5m, 80m, "72083990", null, null, null, null, false, true, false);

    private static async Task<ProductOut> CreateProduct(HttpClient c, string code, ProductKind kind = ProductKind.Part) =>
        await (await c.Post("/api/products", Tube(code, kind))).Read<ProductOut>();

    private static async Task<RoutingOperationOut> AddOperation(HttpClient c, int productId, int seq) =>
        await (await c.Post($"/api/products/{productId}/routing", new RoutingOperationIn(seq, null, null, null, null, 0.5m, 120m, 1m, "Corte", null, null))).Read<RoutingOperationOut>();

    [Fact]
    public async Task Product_crud_and_computed_weight()
    {
        var c = await api.AdminAsync();
        var code = Code("P");
        var created = await (await c.Post("/api/products", Tube(code))).Read<ProductOut>();
        Assert.NotNull(created.NetWeightKg);
        Assert.Equal(TubeWeight.NetWeightKg(TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m), created.NetWeightKg);

        var fetched = await (await c.GetAsync($"/api/products/{created.Id}")).Read<ProductOut>();
        Assert.Equal(code, fetched.Code);

        var updated = await (await c.Put($"/api/products/{created.Id}", Tube(code) with { Name = "Renamed", NetWeightKg = 9m })).Read<ProductOut>();
        Assert.Equal("Renamed", updated.Name);
        Assert.Equal(9m, updated.NetWeightKg);

        var page = await (await c.GetAsync($"/api/products?q={code}")).Read<Ebt.Api.Infrastructure.Page<ProductOut>>();
        Assert.Single(page.Items);

        Assert.Equal(HttpStatusCode.NoContent, (await c.DeleteAsync($"/api/products/{created.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await c.GetAsync($"/api/products/{created.Id}")).StatusCode);
    }

    [Fact]
    public async Task Duplicate_product_code_is_conflict()
    {
        var c = await api.AdminAsync();
        var code = Code("D");
        await CreateProduct(c, code);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post("/api/products", Tube(code))).StatusCode);
    }

    [Fact]
    public async Task Invalid_product_is_bad_request()
    {
        var c = await api.AdminAsync();
        var res = await c.Post("/api/products", Tube(Code("B")) with { Ncm = "123", ThicknessMm = 20m });
        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
    }

    [Fact]
    public async Task Routing_sequence_rules()
    {
        var c = await api.AdminAsync();
        var p = await CreateProduct(c, Code("R"));
        await AddOperation(c, p.Id, 10);
        var bad = await c.Post($"/api/products/{p.Id}/routing", new RoutingOperationIn(15, null, null, null, null, null, null, null, null, null, null));
        Assert.Equal(HttpStatusCode.BadRequest, bad.StatusCode);
        var dup = await c.Post($"/api/products/{p.Id}/routing", new RoutingOperationIn(10, null, null, null, null, null, null, null, null, null, null));
        Assert.Equal(HttpStatusCode.Conflict, dup.StatusCode);
    }

    [Fact]
    public async Task Multi_level_bom_explosion_cycles_and_where_used()
    {
        var c = await api.AdminAsync();
        var steel = await (await c.Post("/api/materials", Steel(Code("M")))).Read<MaterialOut>();
        var paint = await (await c.Post("/api/materials", Steel(Code("T")) with { StockUnit = "L", PurchaseUnit = "L" })).Read<MaterialOut>();

        var component = await CreateProduct(c, Code("C"), ProductKind.Component);
        var compOp = await AddOperation(c, component.Id, 10);
        await (await c.Post($"/api/routing-operations/{compOp.Id}/items", new BomItemIn(steel.Id, null, 0.5m, "KG", 1.1m))).Read<BomItemOut>();

        var part = await CreateProduct(c, Code("A"));
        var op10 = await AddOperation(c, part.Id, 10);
        var op20 = await AddOperation(c, part.Id, 20);
        await (await c.Post($"/api/routing-operations/{op10.Id}/items", new BomItemIn(null, component.Id, 2m, "PC"))).Read<BomItemOut>();
        await (await c.Post($"/api/routing-operations/{op10.Id}/items", new BomItemIn(steel.Id, null, 0.25m, "KG"))).Read<BomItemOut>();
        await (await c.Post($"/api/routing-operations/{op20.Id}/items", new BomItemIn(paint.Id, null, 0.1m, "L"))).Read<BomItemOut>();

        var exp = await (await c.GetAsync($"/api/products/{part.Id}/bom/explode?quantity=10")).Read<BomExplosion>();
        Assert.Equal(4, exp.Lines.Count);
        Assert.Equal(10m * (2m * 0.5m * 1.1m + 0.25m), exp.Materials.Single(m => m.MaterialId == steel.Id).TotalQuantity);
        Assert.Equal(1m, exp.Materials.Single(m => m.MaterialId == paint.Id).TotalQuantity);
        Assert.Contains(exp.Lines, l => l.Level == 2 && l.MaterialId == steel.Id && l.TotalQuantity == 11m);

        var cycle = await c.Post($"/api/routing-operations/{compOp.Id}/items", new BomItemIn(null, part.Id, 1m, "PC"));
        Assert.Equal(HttpStatusCode.Conflict, cycle.StatusCode);
        var self = await c.Post($"/api/routing-operations/{op20.Id}/items", new BomItemIn(null, part.Id, 1m, "PC"));
        Assert.Equal(HttpStatusCode.Conflict, self.StatusCode);
        var both = await c.Post($"/api/routing-operations/{op20.Id}/items", new BomItemIn(steel.Id, component.Id, 1m, "PC"));
        Assert.Equal(HttpStatusCode.BadRequest, both.StatusCode);

        var usedSteel = await (await c.GetAsync($"/api/materials/{steel.Id}/where-used")).Read<List<WhereUsedEntry>>();
        Assert.Equal(new[] { component.Id, part.Id }.Order(), usedSteel.Select(u => u.ProductId).Order());
        var usedComp = await (await c.GetAsync($"/api/products/{component.Id}/where-used")).Read<List<WhereUsedEntry>>();
        Assert.Equal(part.Id, Assert.Single(usedComp).ProductId);

        Assert.Equal(HttpStatusCode.Conflict, (await c.DeleteAsync($"/api/materials/{steel.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await c.DeleteAsync($"/api/products/{component.Id}")).StatusCode);
    }

    [Fact]
    public async Task Customer_address_validation()
    {
        var c = await api.AdminAsync();
        var customer = await (await c.Post("/api/customers", new CustomerIn("ACME Ltda", "ACME", Code("L")[..10], ConsumerType.Normal))).Read<CustomerOut>();
        var ok = new CustomerAddressIn("12.345.678/0001-90", "SP", "1", "123456789012", true, "Rua A", "10", null, "Centro", "São Paulo", "3550308", "01001-000", "5101", null, null, null);
        var saved = await (await c.Post($"/api/customers/{customer.Id}/addresses", ok)).Read<CustomerAddressOut>();
        Assert.Equal("12345678000190", saved.Document);
        Assert.Equal("01001000", saved.ZipCode);
        var bad = ok with { Document = "123", LegacyCode = "2" };
        Assert.Equal(HttpStatusCode.BadRequest, (await c.Post($"/api/customers/{customer.Id}/addresses", bad)).StatusCode);
        var noIe = ok with { StateRegistration = null, LegacyCode = "3" };
        Assert.Equal(HttpStatusCode.BadRequest, (await c.Post($"/api/customers/{customer.Id}/addresses", noIe)).StatusCode);
    }

    [Fact]
    public async Task Too_long_value_is_bad_request()
    {
        var c = await api.AdminAsync();
        var res = await c.Post("/api/customers", new CustomerIn("X", null, new string('9', 40), ConsumerType.Normal));
        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
    }
}
