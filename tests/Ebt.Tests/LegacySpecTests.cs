using Ebt.Api.Endpoints;
using Ebt.Core.Certificates;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

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

    [Fact]
    public void Excel_style_product_code_and_description_follow_the_dimensions()
    {
        Product Tube(string name, decimal d, decimal t, decimal? l) => new() { Code = "X", Ncm = "73063010", StockUnit = "PC", Name = name, DiameterMm = d, ThicknessMm = t, LengthMm = l };
        Assert.Equal("T120016006000", CertificateService.ExcelProductCode(Tube("TUBO-C 12,00 X 1,60 X 6000MM", 12m, 1.6m, 6000m)));
        Assert.Equal("Tubo 12,00 X 1,60 X 6000", CertificateService.ExcelDescription(Tube("TUBO-C 12,00 X 1,60 X 6000MM", 12m, 1.6m, 6000m)));
        Assert.Equal("T080009003000", CertificateService.ExcelProductCode(Tube("TUBO-C 8,00 X 0,90 X 3000MM", 8m, 0.9m, 3000m)));
        Assert.Equal("Tubo 08,00 X 0,90 X 3000", CertificateService.ExcelDescription(Tube("TUBO-C 8,00 X 0,90 X 3000MM", 8m, 0.9m, 3000m)));
        Assert.Equal("T100010000", CertificateService.ExcelProductCode(Tube("TUBO-C 10,00 X 1,00 X ROLO", 10m, 1m, null)));
        Assert.Equal("Tubo 10,00 X 1,00 X ROLO", CertificateService.ExcelDescription(Tube("TUBO-C 10,00 X 1,00 X ROLO", 10m, 1m, null)));
        Assert.Null(CertificateService.ExcelProductCode(null));
    }

    [Fact]
    public async Task Import_replaces_the_legacy_customer_reference_and_fills_code_lot_and_origin_note()
    {
        var admin = await api.AdminAsync();
        // Formigari, tubo 12 x 1,60 x 6000: Excel certificate 2139-26 prints code 20MF02-0116, lot 700263 and the origin note.
        var customer = await (await admin.Post("/api/customers", new CustomerIn("METALURGICA FORMIGARI LTDA.", null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var product = await (await admin.Post("/api/products", new ProductIn("F" + Guid.NewGuid().ToString("N")[..10].ToUpper(), "TUBO-C 12,00 X 1,60 X 6000MM", ProductKind.Part, TubeShape.Circular, 12m, null, null, 1.6m, 6000m, null, null, "73063010", "PC", 50, false, null, null))).Read<ProductOut>();
        using (var scope = api.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<EbtDbContext>();
            const string junk = "TUB12,00X1,60X6000MM20MF020082";
            db.ProductCustomers.Add(new ProductCustomer { ProductId = product.Id, CustomerId = customer.Id, CustomerPartNumber = junk, CustomerDescription = junk, Active = true });
            await db.SaveChangesAsync();
        }

        var result = await (await admin.Post("/api/sales/certificates/templates/import-legacy", new { })).Read<LegacySpecImportResult>();
        Assert.True(result.PartNumbersFixed >= 1);

        using var check = api.CreateScope();
        var cdb = check.ServiceProvider.GetRequiredService<EbtDbContext>();
        var link = await cdb.ProductCustomers.AsNoTracking().SingleAsync(x => x.ProductId == product.Id && x.CustomerId == customer.Id);
        Assert.Equal("20MF02-0116", link.CustomerPartNumber);
        Assert.Equal("Tubo Trefilado R/R DIN EM 10305-2 E195+A", link.CustomerDescription);
        var t = await cdb.CertificateTemplates.AsNoTracking().SingleAsync(x => x.ProductId == product.Id && x.CustomerId == customer.Id);
        Assert.Equal("T120016006000", t.ProductCode);
        Assert.Equal("Tubo 12,00 X 1,60 X 6000", t.Description);
        Assert.Equal("700263", t.RawMaterialLot);
        Assert.Contains("origem do material", t.Notes);
    }
}
