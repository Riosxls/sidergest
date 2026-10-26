using Ebt.Core.Entities;
using Ebt.DbfImport;
using Microsoft.EntityFrameworkCore;
using static Ebt.Tests.DbfWriter;

namespace Ebt.Tests;

[Collection("api")]
public class StockImportTests(ApiFixture api) : IDisposable
{
    private readonly string dir = Directory.CreateTempSubdirectory("ebt-stock-dbf-").FullName;

    public void Dispose() => Directory.Delete(dir, true);

    private string P(string file) => Path.Combine(dir, file);

    private async Task<ImportReport> Run(DateOnly opening, bool dryRun = false)
    {
        await using var db = api.NewDb();
        return await new StockImporter(db, new StockImportOptions { Directory = dir, DryRun = dryRun, OpeningDate = opening, OwnLocation = "ALMIMP", ThirdPartyLocation = "TERIMP" }).RunAsync();
    }

    [Fact]
    public async Task Imports_settings_average_history_and_opening_balances_once()
    {
        var thin = $"S{Guid.NewGuid():N}"[..10].ToUpper();
        var thick = $"S{Guid.NewGuid():N}"[..10].ToUpper();
        await using (var db = api.NewDb())
        {
            db.Materials.AddRange(
                new Material { Code = thin, Description = "Fita 0,95", StockUnit = "KG", PurchaseUnit = "KG", ThicknessMm = 0.95m },
                new Material { Code = thick, Description = "Fita 4,75", StockUnit = "KG", PurchaseUnit = "KG", ThicknessMm = 4.75m });
            await db.SaveChangesAsync();
        }
        Write(P("SHCONTR.DBF"), [C("USARICMSPM", 1), N("VLSERCORTE", 10, 4), N("VLVENDASUC", 10, 4), N("PERCREFUGO", 6, 2)], [["S", 0.18m, 1.10m, 4.5m]]);
        Write(P("SG280.DBF"),
            [C("G28ANOMES", 6), N("G28ESPESSU", 5), C("G28UNIDADE", 2), N("G28QTD", 12, 2), N("G28PRMEDIO", 12, 4), N("G28PRMEDBR", 12, 4)],
            [["199912", 95, "KG", 1200.5m, 5.4321m, 6.1m], ["200001", 95, "KG", 1300m, 5.5m, 6.2m], ["200001", 0, "KG", 1m, 1m, 1m]]);
        Write(P("SALDOEST.DBF"),
            [C("MATERIAL", 10), C("ESPESSURA", 5), C("UNIDADE", 2), N("SALDO", 9), N("SALDOTER", 9)],
            [[thin, "0.95", "KG", 350, 120], [thick, "4.75", "KG", 80, 0], ["NAOEXISTE", "1.00", "KG", 10, 0]]);

        var dry = await Run(new DateOnly(2000, 2, 1), dryRun: true);
        Assert.Equal(2, dry.Tables["average costs"].Inserted);
        await using (var db = api.NewDb())
            Assert.False(await db.StockDocuments.AnyAsync(d => d.Reference == StockImporter.OpeningReference));

        var first = await Run(new DateOnly(2000, 2, 1));
        Assert.Equal(2, first.Tables["average costs"].Inserted);
        Assert.Equal(1, first.Tables["average costs"].Skipped);
        Assert.Equal(3, first.Tables["opening balances"].Inserted);
        Assert.Contains(first.Warnings, w => w.Contains("NAOEXISTE"));
        Assert.Contains(first.Warnings, w => w.Contains("no average cost"));

        await using (var db = api.NewDb())
        {
            var s = await db.StockSettings.SingleAsync();
            Assert.True(s.DeductIcmsFromAverage);
            Assert.Equal(0.18m, s.CuttingServicePerKg);
            Assert.Equal(1.10m, s.ScrapResalePerKg);
            Assert.Equal(4.5m, s.ScrapPercent);
            var avg = await db.AverageCosts.SingleAsync(a => a.Period == 200001 && a.ThicknessMm == 0.95m);
            Assert.True(avg.Imported);
            Assert.Equal(5.5m, avg.Average);
            Assert.Equal(6.2m, avg.AverageGross);

            var thinId = await db.Materials.Where(m => m.Code == thin).Select(m => m.Id).SingleAsync();
            var moves = await db.StockMovements.Include(m => m.Location).Include(m => m.Lot).Where(m => m.MaterialId == thinId).ToListAsync();
            Assert.Equal(350m, moves.Single(m => m.Location!.Code == "ALMIMP").Quantity);
            Assert.Equal(120m, moves.Single(m => m.Location!.Kind == StockLocationKind.ThirdParty).Quantity);
            Assert.All(moves, m => Assert.Equal(5.5m, m.UnitCost));
            Assert.All(moves, m => Assert.Equal("INICIAL", m.Lot!.Code));
            Assert.Equal(470m, await db.StockBalances.Where(b => b.MaterialId == thinId).SumAsync(b => b.Quantity));

            s.DeductIcmsFromAverage = true; s.CuttingServicePerKg = 0; s.ScrapResalePerKg = 0; s.ScrapPercent = 0;
            await db.SaveChangesAsync();
        }

        Write(P("SG280.DBF"),
            [C("G28ANOMES", 6), N("G28ESPESSU", 5), C("G28UNIDADE", 2), N("G28QTD", 12, 2), N("G28PRMEDIO", 12, 4), N("G28PRMEDBR", 12, 4)],
            [["200001", 95, "KG", 1300m, 5.75m, 6.2m]]);
        File.Delete(P("SHCONTR.DBF"));
        var second = await Run(new DateOnly(2000, 2, 1));
        Assert.Equal(1, second.Tables["average costs"].Updated);
        Assert.Equal(1, second.Tables["opening balances"].Skipped);
        Assert.Contains(second.Warnings, w => w.Contains("already imported"));
        await using var check = api.NewDb();
        Assert.Equal(5.75m, (await check.AverageCosts.SingleAsync(a => a.Period == 200001 && a.ThicknessMm == 0.95m)).Average);
        Assert.Equal(2, await check.StockDocuments.CountAsync(d => d.Reference == StockImporter.OpeningReference));
    }
}
