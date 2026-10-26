using Ebt.Core.Data;
using Ebt.DbfImport;
using Microsoft.EntityFrameworkCore;

string? Arg(string name) => args.SkipWhile(a => a != name).Skip(1).FirstOrDefault();

var dir = Arg("--dir");
var conn = Arg("--conn") ?? Environment.GetEnvironmentVariable("ConnectionStrings__Ebt");
if (dir is null || conn is null || args.Contains("--help"))
{
    Console.WriteLine("""
        Usage: Ebt.DbfImport --dir <folder with legacy DBFs> --conn <PostgreSQL connection string>
                             [--codepage 850] [--default-ncm 73063010] [--dry-run] [--migrate]
                             [--opening-date yyyy-mm-dd]

        Imports HDS Engenharia master data (materials, machines, customers, suppliers,
        products, routing and BOM) and Suprimentos data (requisitions, quotations,
        purchase orders, delivery schedules, supplier materials, SGCONTRO settings)
        into the EBT ERP database. Safe to re-run: rows are matched by legacy code or
        number and updated in place.

        Then imports stock: settings (SHCONTR/ESCONTR), monthly average cost per
        thickness (SG280) and opening balances (SALDOEST: SALDO -> ALM, SALDOTER -> TER)
        dated --opening-date (default today). Opening balances are imported once.

        Then PCP/Apontamento: CACONTR settings and OF counters, shifts (G29),
        employees (G28), occurrences (G27), production orders (XY090), OPIs (XY310),
        committed materials (XY060), overrun releases (XY280), shop-floor reports
        (XY130 with XY140 labor and XY150 machine) and scrap (E24).
        """);
    return args.Contains("--help") ? 0 : 2;
}
if (!Directory.Exists(dir))
{
    Console.Error.WriteLine($"Folder not found: {dir}");
    return 2;
}

var options = new ImportOptions
{
    Directory = dir,
    CodePage = int.TryParse(Arg("--codepage"), out var cp) ? cp : 850,
    DefaultNcm = Arg("--default-ncm") ?? "73063010",
    DryRun = args.Contains("--dry-run"),
    Steps = [new PurchasingImport(), new ProductionImport()]
};

await using var db = new EbtDbContext(DesignTimeFactory.Create(conn));
if (args.Contains("--migrate")) await db.Database.MigrateAsync();

var report = await new Importer(db, options).RunAsync();
db.ChangeTracker.Clear();
var stock = await new StockImporter(db, new StockImportOptions
{
    Directory = dir,
    CodePage = options.CodePage,
    DryRun = options.DryRun,
    OpeningDate = DateOnly.TryParse(Arg("--opening-date"), out var od) ? od : DateOnly.FromDateTime(DateTime.Today)
}).RunAsync();
foreach (var (name, t) in stock.Tables) report.Tables[name] = t;
report.Warnings.AddRange(stock.Warnings);

Console.WriteLine(options.DryRun ? "DRY RUN: nothing was saved." : "Import committed.");
Console.WriteLine($"{"Table",-22} {"File",-14} {"Inserted",9} {"Updated",8} {"Skipped",8}");
foreach (var (name, t) in report.Tables)
    Console.WriteLine($"{name,-22} {t.File,-14} {t.Inserted,9} {t.Updated,8} {t.Skipped,8}");
if (report.Warnings.Count > 0)
{
    Console.WriteLine($"\n{report.Warnings.Count} warning(s):");
    foreach (var w in report.Warnings) Console.WriteLine($"  - {w}");
}
return 0;
