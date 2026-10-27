using System.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Microsoft.EntityFrameworkCore;

namespace Ebt.DbfImport;

public sealed class StockImportOptions
{
    public required string Directory { get; init; }
    public int CodePage { get; init; } = 850;
    public bool DryRun { get; init; }
    public DateOnly OpeningDate { get; init; } = DateOnly.FromDateTime(DateTime.Today);
    public string OwnLocation { get; init; } = "ALM";
    public string ThirdPartyLocation { get; init; } = "TER";
    public string User { get; init; } = "dbf-import";
}

public sealed class StockImporter(EbtDbContext db, StockImportOptions options)
{
    public const string OpeningReference = "DBF SALDOEST";
    private const string AverageTable = "average costs";
    private const string SettingsTable = "stock settings";
    private const string BalanceTable = "opening balances";

    private readonly ImportReport report = new();
    private Encoding encoding = Encoding.Latin1;

    public async Task<ImportReport> RunAsync(CancellationToken ct = default)
    {
        encoding = LegacyDbf.GetEncoding(options.CodePage);
        var files = Discover();
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        if (files.Settings is { } s) await ImportSettings(s, ct);
        else report.Warnings.Add("No SHCONTR/ESCONTR found; stock settings left unchanged.");
        if (files.Averages is { } a) await ImportAverages(a, ct);
        else report.Warnings.Add("No SG280 (G28ESPESSU/G28PRMEDIO) found; average-cost history not imported.");
        if (files.Balances is { } b) await ImportBalances(b, ct);
        else report.Warnings.Add("No SALDOEST (MATERIAL/SALDO) found; opening balances not imported.");

        if (options.DryRun) await tx.RollbackAsync(ct);
        else await tx.CommitAsync(ct);
        return report;
    }

    private (string? Settings, string? Averages, string? Balances) Discover()
    {
        string? settings = null, averages = null, balances = null;
        foreach (var path in System.IO.Directory.EnumerateFiles(options.Directory, "*", SearchOption.TopDirectoryOnly)
                     .Where(p => p.EndsWith(".dbf", StringComparison.OrdinalIgnoreCase)).Order())
        {
            HashSet<string> cols;
            try { cols = Columns(path); }
            catch (Exception ex) { report.Warnings.Add($"Could not read {Path.GetFileName(path)}: {ex.Message}"); continue; }
            if (cols.Contains("G28ESPESSU") && cols.Contains("G28PRMEDIO")) averages ??= path;
            else if (cols.Contains("MATERIAL") && cols.Contains("SALDO")) balances ??= path;
            else if (cols.Contains("VLSERCORTE")) settings = path;
            else if (cols.Contains("USARICMSPM")) settings ??= path;
        }
        return (settings, averages, balances);
    }

    private static HashSet<string> Columns(string path)
    {
        using var table = new DbfDataReader.DbfTable(path, Encoding.Latin1);
        return table.Columns.Select(c => c.ColumnName.ToUpperInvariant()).ToHashSet();
    }

    private async Task ImportSettings(string path, CancellationToken ct)
    {
        report.For(SettingsTable).File = Path.GetFileName(path);
        var row = LegacyDbf.Read(path, encoding).FirstOrDefault();
        if (row is null) { report.For(SettingsTable).Skipped++; return; }
        var s = await db.StockSettings.FirstAsync(ct);
        if (row.Str("USARICMSPM") is not null) s.DeductIcmsFromAverage = row.Flag("USARICMSPM");
        if (row.Dec("VLSERCORTE") is { } c) s.CuttingServicePerKg = c;
        if (row.Dec("VLVENDASUC") is { } v) s.ScrapResalePerKg = v;
        if (row.Dec("PERCREFUGO") is { } p) s.ScrapPercent = p;
        await db.SaveChangesAsync(ct);
        report.For(SettingsTable).Updated++;
    }

    private async Task ImportAverages(string path, CancellationToken ct)
    {
        var t = report.For(AverageTable);
        t.File = Path.GetFileName(path);
        var closed = (await db.StockClosings.Select(c => c.Period).ToListAsync(ct)).ToHashSet();
        var existing = await db.AverageCosts.Where(a => a.ThicknessMm != null).ToDictionaryAsync(a => (a.Period, a.ThicknessMm!.Value), ct);
        foreach (var r in LegacyDbf.Read(path, encoding))
        {
            var period = r.Int("G28ANOMES");
            var raw = r.Dec("G28ESPESSU");
            if (period is null || period % 100 is < 1 or > 12 || raw is not > 0) { Skip(AverageTable, $"invalid row (anomes={r.Str("G28ANOMES")}, espessura={r.Str("G28ESPESSU")})"); continue; }
            var thickness = raw.Value >= 10m ? raw.Value / 100m : raw.Value;
            if (closed.Contains(period.Value)) { Skip(AverageTable, $"{period} is closed in the new system; legacy row for {thickness} mm ignored"); continue; }
            var inserted = !existing.TryGetValue((period.Value, thickness), out var a);
            if (!inserted && !a!.Imported) { Skip(AverageTable, $"{period}/{thickness} mm was computed by the new system; kept"); continue; }
            a ??= new AverageCost { Period = period.Value, ThicknessMm = thickness, Imported = true };
            a.OpeningQuantity = r.Dec("G28QTD") ?? 0m;
            a.Average = r.Dec("G28PRMEDIO") ?? 0m;
            a.AverageGross = r.Dec("G28PRMEDBR") ?? a.Average;
            a.OpeningAverage = a.Average;
            if (inserted) { db.AverageCosts.Add(a); existing[(period.Value, thickness)] = a; t.Inserted++; }
            else t.Updated++;
        }
        await db.SaveChangesAsync(ct);
    }

    private async Task ImportBalances(string path, CancellationToken ct)
    {
        var t = report.For(BalanceTable);
        t.File = Path.GetFileName(path);
        if (await db.StockDocuments.AnyAsync(d => d.Type == MovementType.OpeningBalance && d.Reference == OpeningReference && !d.Reversed, ct))
        {
            report.Warnings.Add($"Opening balances were already imported ({OpeningReference}); reverse that document to import again.");
            t.Skipped++;
            return;
        }
        var own = await Location(options.OwnLocation, "Almoxarifado", StockLocationKind.Internal, ct);
        var third = await Location(options.ThirdPartyLocation, "Em poder de terceiros", StockLocationKind.ThirdParty, ct);
        var materials = await db.Materials.AsNoTracking().ToDictionaryAsync(m => m.Code, m => m.Id, ct);

        var ownLines = new List<StockLine>();
        var thirdLines = new List<StockLine>();
        foreach (var r in LegacyDbf.Read(path, encoding))
        {
            var code = r.Str("MATERIAL");
            if (code is null) { Skip(BalanceTable, "row without material"); continue; }
            if (!materials.TryGetValue(code, out var id)) { Skip(BalanceTable, $"material {code} not found; import materials first"); continue; }
            if (r.Dec("SALDO") is > 0 and var q) ownLines.Add(new StockLine(id, null, own.Id, q, LotCode: "INICIAL"));
            else if (r.Dec("SALDO") is < 0) report.Warnings.Add($"{BalanceTable}: {code} has negative balance {r.Dec("SALDO")}; ignored");
            if (r.Dec("SALDOTER") is > 0 and var tq) thirdLines.Add(new StockLine(id, null, third.Id, tq, LotCode: "INICIAL"));
        }

        var svc = new StockService(db);
        foreach (var lines in new[] { ownLines, thirdLines }.Where(l => l.Count > 0))
        {
            await svc.PostAsync(new StockPost(MovementType.OpeningBalance, options.OpeningDate, lines, OpeningReference, Notes: "Saldo inicial importado do HDS"), options.User, ct);
            t.Inserted += lines.Count;
        }
        var zeroCost = await db.StockMovements.CountAsync(m => m.Document!.Reference == OpeningReference && m.UnitCost == 0, ct);
        if (zeroCost > 0) report.Warnings.Add($"{BalanceTable}: {zeroCost} line(s) have no average cost (no SG280 row for the thickness before {options.OpeningDate:yyyy-MM}).");
    }

    private async Task<StockLocation> Location(string code, string name, StockLocationKind kind, CancellationToken ct)
    {
        var l = await db.StockLocations.FirstOrDefaultAsync(x => x.Code == code, ct);
        if (l is not null) return l;
        l = new StockLocation { Code = code, Name = name, Kind = kind };
        db.StockLocations.Add(l);
        await db.SaveChangesAsync(ct);
        return l;
    }

    private void Skip(string table, string reason)
    {
        report.For(table).Skipped++;
        report.Warnings.Add($"{table}: {reason}");
    }
}
