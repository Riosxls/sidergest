using Ebt.Core.Entities;
using Ebt.Core.Services;
using Ebt.DbfImport;
using Microsoft.EntityFrameworkCore;
using static Ebt.Tests.DbfWriter;

namespace Ebt.Tests;

[Collection("api")]
public class DbfImportTests(ApiFixture api) : IDisposable
{
    private readonly string dir = Directory.CreateTempSubdirectory("ebt-dbf-").FullName;

    public void Dispose() => Directory.Delete(dir, true);

    private string P(string file) => Path.Combine(dir, file);

    private void WriteFixtures(decimal steelQty)
    {
        Write(P("SE090.DBF"), [C("E09CDTPMAT", 3), C("E09DSTPMAT", 30)], [["MP", "Matéria-prima"]]);
        Write(P("SE100.DBF"),
            [C("E10CDMATER", 15), C("E10DSMATER", 40), C("E10CDTPMAT", 3), C("E10UNIDADE", 3), N("E10FATOR", 10, 4), N("E10ESPEC", 8, 3), C("E10NCM", 10), C("E10GERACOM", 1)],
            [["BOB150", "Bobina aço 1,50mm", "MP", "KG", 0m, 1.5m, "7208.39.90", "S"], ["TINTA", "Tinta pó", null, "KG", 1m, 0m, null, "N"]],
            deleted: [["APAGADO", "Linha apagada", null, "KG", 1m, 0m, null, null]]);
        Write(P("SE070.DBF"), [C("E07CDCCUST", 6), C("E07DSCCUST", 30)], [["100", "Corte"], ["200", "Pintura"]]);
        Write(P("MAQUINAS.DBF"), [C("P07CDMAQ", 6), C("P07DSMAQ", 30), C("P07CDCCUST", 6), C("P07CDGPMAQ", 6)], [["SR01", "Serra fita", "100", "SERRA"]]);
        Write(P("NF010.DBF"), [C("F01CDCLIE", 6), C("F01NMCLIE", 40), C("F01NMFANT", 20), C("F01STATUS", 1)], [["000123", "Cliente Exemplo Ltda", "EXEMPLO", "A"]]);
        Write(P("NF020.DBF"),
            [C("F02CDCLIE", 6), C("F02CDENDER", 2), C("F02CGC", 18), C("F02CDESTAD", 2), C("F02IE", 15), C("F02CIDADE", 30), C("F02IDMUNIC", 7), C("F02CEP", 9)],
            [["000123", "1", "12.345.678/0001-90", "SP", "123456789012", "São Paulo", "3550308", "01001-000"], ["999999", "1", "1", "SP", null, null, null, null]]);
        Write(P("NF060.DBF"),
            [C("F06CDPECA", 15), C("F06NMPECA", 40), C("F06TPPECA", 1), C("F06TPTUBO", 1), N("F06DIAMETR", 8, 2), N("F06ESPESSU", 6, 2), N("F06COMPRIM", 8, 1), C("F06NCM", 10)],
            [["TUBO-A", "Tubo 25,4 x 1,5", "P", "C", 25.4m, 1.5m, 1000m, "73063010"], ["COMP-B", "Luva", "C", null, 0m, 0m, 0m, null]]);
        Write(P("NF330.DBF"), [C("F33CDPECA", 15), C("F33CDCLIE", 6), C("F33DSPCCLI", 30), C("F33IDSTATU", 1)], [["TUBO-A", "000123", "PN-778", "A"]]);
        Write(P("XY050.DBF"),
            [C("X05CDPECA", 15), N("X05NROPER", 4), C("X05CDMAQ", 6), C("X05CDSETOR", 6), N("X05HRPRE", 6, 2), N("X05HRMAQ", 8, 2), C("X05DESC1", 30)],
            [["TUBO-A", 10, "SR01", "100", 0.5m, 120m, "Cortar"], ["TUBO-A", 20, "XX99", "200", 0m, 60m, "Pintar"], ["COMP-B", 10, null, "100", 0m, 0m, "Estampar"], ["TUBO-A", 15, null, null, 0m, 0m, "Inválida"]]);
        Write(P("XY040.DBF"),
            [C("X04CDPECA", 15), N("X04NROPER", 4), C("X04CDMAT", 15), N("X04QTMAT", 10, 4), C("X04UNID", 3), N("X04FATOR", 8, 4)],
            [["TUBO-A", 10, "BOB150", steelQty, "KG", 0m], ["TUBO-A", 10, "COMP-B", 2m, "PC", 1m], ["TUBO-A", 20, "TINTA", 0.05m, "KG", 1m], ["COMP-B", 10, "BOB150", 0.1m, "KG", 1m], ["TUBO-A", 10, "NAOEXISTE", 1m, "UN", 1m]]);
    }

    private async Task<ImportReport> Run(bool dryRun = false)
    {
        await using var db = api.NewDb();
        return await new Importer(db, new ImportOptions { Directory = dir, DryRun = dryRun }).RunAsync();
    }

    [Fact]
    public async Task Imports_legacy_engineering_data_and_is_idempotent()
    {
        WriteFixtures(0.9m);

        var dry = await Run(dryRun: true);
        Assert.Equal(2, dry.Tables["materials"].Inserted);
        await using (var db = api.NewDb())
            Assert.False(await db.Products.AnyAsync(p => p.Code == "TUBO-A"));

        var first = await Run();
        Assert.Equal(2, first.Tables["materials"].Inserted);
        Assert.Equal(2, first.Tables["products"].Inserted);
        Assert.Equal(3, first.Tables["routing"].Inserted);
        Assert.Equal(1, first.Tables["routing"].Skipped);
        Assert.Equal(4, first.Tables["bill of materials"].Inserted);
        Assert.Equal(1, first.Tables["bill of materials"].Skipped);
        Assert.Equal(1, first.Tables["customer addresses"].Skipped);
        Assert.Contains(first.Warnings, w => w.Contains("XX99"));
        Assert.Contains(first.Warnings, w => w.Contains("COMP-B") && w.Contains("NCM"));

        WriteFixtures(1.2m);
        var second = await Run();
        Assert.Equal(0, second.Tables["materials"].Inserted);
        Assert.Equal(2, second.Tables["materials"].Updated);
        Assert.Equal(0, second.Tables["products"].Inserted);
        Assert.Equal(0, second.Tables["routing"].Inserted);

        await using var check = api.NewDb();
        var steel = await check.Materials.Include(m => m.Class).SingleAsync(m => m.Code == "BOB150");
        Assert.Equal("Bobina aço 1,50mm", steel.Description);
        Assert.Equal("MP", steel.Class!.Code);
        Assert.Equal(1m, steel.PurchaseFactor);
        Assert.Equal("72083990", steel.Ncm);
        Assert.False(await check.Materials.AnyAsync(m => m.Code == "APAGADO"));
        Assert.False((await check.Materials.SingleAsync(m => m.Code == "TINTA")).GeneratesPurchaseOrder);

        var tube = await check.Products.Include(p => p.Customers).SingleAsync(p => p.Code == "TUBO-A");
        Assert.Equal(TubeShape.Circular, tube.Shape);
        Assert.Equal("PN-778", Assert.Single(tube.Customers).CustomerPartNumber);
        var comp = await check.Products.SingleAsync(p => p.Code == "COMP-B");
        Assert.Equal(ProductKind.Component, comp.Kind);
        Assert.Equal("73063010", comp.Ncm);

        var address = await check.CustomerAddresses.SingleAsync(a => a.Customer!.LegacyCode == "000123");
        Assert.Equal("12345678000190", address.Document);
        Assert.Equal("01001000", address.ZipCode);

        Assert.Equal(4, await check.BomItems.CountAsync(b => b.RoutingOperation!.Product!.Code == "TUBO-A" || b.RoutingOperation!.Product!.Code == "COMP-B"));
        var exp = await new BomService(check).ExplodeAsync(tube.Id, 1m);
        Assert.Equal(1.2m + 2m * 0.1m, exp!.Materials.Single(m => m.Code == "BOB150").TotalQuantity);
    }
}
