using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Production;
using Ebt.Core.Services;
using Ebt.DbfImport;
using Microsoft.EntityFrameworkCore;
using static Ebt.Tests.DbfWriter;

namespace Ebt.Tests;

[Collection("api")]
public class ProductionImportTests(ApiFixture api) : IDisposable
{
    private readonly string dir = Directory.CreateTempSubdirectory("ebt-pcp-").FullName;
    private readonly string suffix = Guid.NewGuid().ToString("N")[..6].ToUpper();

    public void Dispose()
    {
        Directory.Delete(dir, true);
        using var db = api.NewDb();
        db.ProductionSettings.ExecuteUpdate(s => s.SetProperty(x => x.OverrunTolerancePercent, 3m));
    }

    private string P(string file) => Path.Combine(dir, file);
    private static DbfField D(string name) => new(name, 'D', 8);

    private async Task<(Product Product, Product Component, Material Material, Machine Machine)> Seed()
    {
        await using var db = api.NewDb();
        var wc = new WorkCenter { Code = "WC" + suffix, Name = "Corte" };
        var machine = new Machine { Code = "MQ" + suffix, Name = "Serra", WorkCenter = wc };
        var material = new Material { Code = "MP" + suffix, Description = "Bobina", StockUnit = "KG", PurchaseUnit = "KG" };
        var component = new Product { Code = "CP" + suffix, Name = "Luva", Ncm = "73063010", StockUnit = "PC" };
        var product = new Product { Code = "PA" + suffix, Name = "Tubo", Ncm = "73063010", StockUnit = "PC" };
        product.Routing.Add(new RoutingOperation { Sequence = 10, Machine = machine, SetupHours = 1, PiecesPerHour = 100, Items = { new BomItem { Material = material, Quantity = 2m, Unit = "KG" } } });
        product.Routing.Add(new RoutingOperation { Sequence = 20, Machine = machine, Items = { new BomItem { ComponentProduct = component, Quantity = 1m, Unit = "PC" } } });
        db.AddRange(product, component);
        await db.SaveChangesAsync();
        return (product, component, material, machine);
    }

    private void WriteFixtures(string product, string component, string material, string machine)
    {
        Write(P("CACONTR.DBF"), [N("CA_NROP", 6), N("CA_NROPI", 6), N("TOL_APONTA", 3, 1)], [[990500, 990020, 5m]]);
        Write(P("SG290.DBF"), [C("G29IDTURNO", 2), C("G29NMTURNO", 20), C("G29HRINIC", 5), C("G29HRFIM", 5), C("G29HRTRAB", 5)], [["T" + suffix[..1], "Primeiro", "06:00", "14:20", "08:20"]]);
        Write(P("SG280.DBF"), [C("G28IDFUNC", 6), C("G28NMFUNC", 30), C("G28APELIDO", 10), C("G28IDTURNO", 2), C("G28AFASTAD", 1)],
            [["F" + suffix[..5], "Jose da Silva", "ZE", "T" + suffix[..1], "N"], ["G" + suffix[..5], "Maria Souza", null, null, "S"]]);
        Write(P("SG270.DBF"), [C("G27IDOCORR", 3), C("G27DSOCORR", 30), C("G27STATOF", 1)], [["9" + suffix[..2], "Falta de energia", "S"]]);
        Write(P("XY090.DBF"),
            [C("X09CDOP", 6), C("X09CDPECA", 20), N("X09QTDPRO", 10, 3), D("X09DTENTR"), D("X09DTINIPR"), D("X09DTCAD"), C("X09STATUS", 1), C("X09CDOPPAI", 6), C("X09CDOPANT", 6), D("X09DTENCER"), D("X09DTENCUS"), D("X09DTIMPR")],
            [["990401", product, 100m, "20260310", "20260301", "20260225", "3", null, null, null, null, "20260226"],
             ["990402", product, 40m, "20260115", null, "20260105", "5", null, "990401", "20260120", "20260131", "20260106"],
             ["990403", component, 100m, "20260305", null, "20260225", "0", "990401", null, null, null, null],
             ["990404", "NAOEXISTE", 10m, "20260305", null, "20260225", "0", null, null, null, null, null]]);
        Write(P("XY310.DBF"), [N("X31IDOPI", 6), C("X31CDPECA", 20), N("X31QTDPRO", 10, 3), D("X31DTPROD"), N("X31FARDOS", 4), C("X31STATUS", 1), D("X31DTCAD")],
            [[990011, product, 500m, "20260320", 12, "1", "20260301"]]);
        Write(P("XY060.DBF"), [C("X06CDOP", 6), C("X06CDMATER", 20), N("X06NROPER", 3), N("X06QTMATER", 12, 3), C("X06TPMATER", 1)],
            [["990401", material, 10, 210m, "M"], ["990401", component, 20, 100m, "C"]]);
        Write(P("XY280.DBF"), [C("X28CDOP", 6), N("X28NROPER", 3), N("X28QTDLIB", 10, 3), C("X28JUSTIF", 30), C("X28USUARIO", 10), D("X28DATA")],
            [["990401", 10, 4m, "Sobra de bobina", "ANA", "20260302"]]);
        Write(P("XY130.DBF"), [N("X13PK", 8), C("X13CDOP", 6), N("X13NROPER", 3), N("X13QTD", 10, 3), D("X13DTCADAS"), C("X13HRLANC", 5), C("X13IDOCORR", 3), C("X13HRDESCO", 5), N("X13QTOPERA", 4, 1), C("X13USUARIO", 10), N("X13QTD_KG", 12, 3)],
            [[1, "990401", 10, 60m, "20260302", "07:30", "9" + suffix[..2], "00:30", 2m, "PEDRO", 120.5m],
             [2, "990401", 30, 10m, "20260303", null, null, null, null, "PEDRO", null],
             [3, "999999", 10, 1m, "20260303", null, null, null, null, null, null]]);
        Write(P("XY140.DBF"), [N("X14PK", 8), C("X14IDFUNC", 6)], [[1, "F" + suffix[..5]]]);
        Write(P("XY150.DBF"), [N("X15PK", 8), C("X15CDMAQRE", 20)], [[1, machine]]);
        Write(P("SE240.DBF"), [C("E24OF", 6), N("E24NROPER", 3), N("E24REFUGO", 10, 3), C("E24NRDOC", 8), C("E24LOTE", 10)],
            [["990401", 10, 2m, "R1", "L77"], ["990401", 10, 1m, "R1", "L77"]]);
    }

    private async Task<ImportReport> Run(bool dryRun = false)
    {
        await using var db = api.NewDb();
        return await new Importer(db, new ImportOptions { Directory = dir, DryRun = dryRun, Steps = [new ProductionImport()] }).RunAsync();
    }

    [Fact]
    public async Task Imports_legacy_pcp_data_and_is_idempotent()
    {
        var (product, component, material, machine) = await Seed();
        WriteFixtures(product.Code, component.Code, material.Code, machine.Code);

        var dry = await Run(dryRun: true);
        Assert.Equal(3, dry.Tables["production orders"].Inserted);
        await using (var db = api.NewDb()) Assert.False(await db.ProductionOrders.AnyAsync(o => o.Number == 990401));

        var first = await Run();
        Assert.Equal(3, first.Tables["production orders"].Inserted);
        Assert.Equal(1, first.Tables["production orders"].Skipped);
        Assert.Equal(1, first.Tables["internal orders"].Inserted);
        Assert.Equal(2, first.Tables["shop-floor reports"].Inserted);
        Assert.Equal(1, first.Tables["shop-floor reports"].Skipped);
        Assert.Contains(first.Warnings, w => w.Contains("NAOEXISTE"));
        Assert.Contains(first.Warnings, w => w.Contains("OF 990401: operation 30"));

        var second = await Run();
        Assert.Equal(0, second.Tables["production orders"].Inserted);
        Assert.Equal(3, second.Tables["production orders"].Updated);
        Assert.Equal(0, second.Tables["shop-floor reports"].Inserted);
        Assert.Equal(0, second.Tables["scrap"].Inserted);
        Assert.Equal(0, second.Tables["overrun releases"].Inserted);
        Assert.Equal(0, second.Tables["order materials"].Inserted);

        await using var check = api.NewDb();
        var orders = await check.ProductionOrders.Include(o => o.Operations).Include(o => o.Materials).Where(o => o.Number >= 990401 && o.Number <= 990404).ToDictionaryAsync(o => o.Number);
        var open = orders[990401];
        Assert.Equal(ProductionOrderStatus.InProduction, open.Status);
        Assert.Equal("OF 990401", open.Reference);
        Assert.Equal(new DateOnly(2026, 3, 10), open.DueDate);
        Assert.Equal([10, 20, 30], open.Operations.Select(o => o.Sequence).Order());
        Assert.Equal(4m, open.Operations.Single(o => o.Sequence == 10).OverrunReleased);
        Assert.Equal(210m, open.Materials.Single(m => m.MaterialId == material.Id).RequiredQuantity);
        Assert.Equal(2.1m, open.Materials.Single(m => m.MaterialId == material.Id).QuantityPerUnit);
        Assert.Equal(100m, open.Materials.Single(m => m.ComponentProductId == component.Id).RequiredQuantity);
        Assert.Equal(ProductionOrderStatus.Closed, orders[990402].Status);
        Assert.NotNull(orders[990402].CostClosedAt);
        Assert.Equal(open.Id, orders[990402].PreviousOrderId);
        Assert.Equal(open.Id, orders[990403].ParentOrderId);
        Assert.Equal(ProductionOrderStatus.Created, orders[990403].Status);
        Assert.False(orders.ContainsKey(990404));

        var opi = await check.ProductionOrders.SingleAsync(o => o.Kind == ProductionOrderKind.Internal && o.Number == 990011);
        Assert.Equal("OPI 990011", opi.Reference);
        Assert.Equal(12, opi.Bales);
        Assert.Equal(ProductionOrderStatus.Released, opi.Status);

        var report = await check.ProductionReports.Include(r => r.Employee).Include(r => r.DowntimeOccurrence).SingleAsync(r => r.LegacyKey == "X13:1");
        Assert.Equal(60m, report.GoodQuantity);
        Assert.Equal(0.5m, report.DowntimeHours);
        Assert.Equal(machine.Id, report.MachineId);
        Assert.Equal("Jose da Silva", report.Employee!.Name);
        Assert.True(report.DowntimeOccurrence!.StopsOrder);
        Assert.Equal(new TimeOnly(7, 30), report.StartTime);
        var scrap = await check.ProductionReports.SingleAsync(r => r.OrderId == open.Id && r.LegacyKey!.StartsWith("E24:"));
        Assert.Equal(3m, scrap.ScrapQuantity);

        Assert.Equal(5m, (await check.ProductionSettings.SingleAsync()).OverrunTolerancePercent);
        var inactive = "G" + suffix[..5];
        var shiftCode = "T" + suffix[..1];
        Assert.False((await check.Employees.SingleAsync(e => e.Code == inactive)).Active);
        var shift = await check.Shifts.SingleAsync(s => s.Code == shiftCode);
        Assert.Equal(8.33m, shift.Hours);

        var svc = new ProductionService(check, new StockService(check), new BomService(check));
        var progress = await svc.ProgressAsync(open.Id);
        Assert.Equal(60m, progress.Operations.Single(o => o.Sequence == 10).Good);
        Assert.Equal(3m, progress.Operations.Single(o => o.Sequence == 10).Scrap);
        var next = await svc.CreateOrderAsync(new OrderInput(product.Id, 1m, new DateOnly(2026, 12, 1)), "test");
        Assert.True(next.Number > 990500);
        var nextOpi = await svc.CreateOrderAsync(new OrderInput(product.Id, 1m, new DateOnly(2026, 12, 1), ProductionOrderKind.Internal), "test");
        Assert.True(nextOpi.Number > 990020);
    }
}
