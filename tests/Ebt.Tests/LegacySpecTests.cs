using Ebt.Api.Endpoints;
using Ebt.Core.Certificates;
using Ebt.Core.Entities;

namespace Ebt.Tests;

[Collection("api")]
public class LegacySpecTests(ApiFixture api)
{
    [Fact]
    public void Embedded_specs_cover_the_three_tables_of_every_template()
    {
        var specs = LegacySpecImporter.Load();
        Assert.True(specs.Count > 50);
        Assert.All(specs, s =>
        {
            Assert.Equal(["C", "Mn", "P", "S", "Si"], s.Chemical.Take(5).Select(r => r.Name));
            Assert.True(s.Dimensional.Count >= 2);
        });
    }

    [Fact]
    public async Task Import_creates_templates_for_known_customers_and_products_and_keeps_existing_ones()
    {
        var admin = await api.AdminAsync();
        // HSA, tubo 10 x 1,60 x 5935: its certificates of 2025-26 carry "Máx. 0,120" for carbon.
        var customer = await (await admin.Post("/api/customers", new CustomerIn("HSA AUTOMOTIVE SYSTEMS LTDA.", null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var product = await (await admin.Post("/api/products", new ProductIn("H" + Guid.NewGuid().ToString("N")[..10].ToUpper(), "TUBO-C 10,00 X 1,60 X 5935 MM", ProductKind.Part, TubeShape.Circular, 10m, null, null, 1.6m, 5935m, null, null, "73063010", "PC", 50, false, null, null))).Read<ProductOut>();

        var first = await (await admin.Post("/api/sales/certificates/templates/import-legacy", new { })).Read<LegacySpecImportResult>();
        Assert.True(first.Created >= 1);
        var templates = await (await admin.GetAsync($"/api/sales/certificates/templates?customerId={customer.Id}")).Read<List<CertificateTemplateOut>>();
        var t = Assert.Single(templates);
        Assert.Equal(product.Id, t.ProductId);
        Assert.Contains(t.Measures, m => m.Kind == CertificateMeasureKind.Chemical && m.Name == "C" && m.Specified == "Máx. 0,120");
        Assert.Contains(t.Measures, m => m.Kind == CertificateMeasureKind.Dimensional && m.Name == "Espessura" && m.Specified!.StartsWith("1,60"));
        Assert.Contains(t.Measures, m => m.Kind == CertificateMeasureKind.Mechanical && m.Name == "LR" && m.Specified is not null);

        var second = await (await admin.Post("/api/sales/certificates/templates/import-legacy", new { })).Read<LegacySpecImportResult>();
        Assert.Equal(0, second.Created);
        Assert.Single(await (await admin.GetAsync($"/api/sales/certificates/templates?customerId={customer.Id}")).Read<List<CertificateTemplateOut>>());
    }
}
