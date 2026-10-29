using System.Globalization;
using System.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Production;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;

namespace Ebt.DbfImport;

public sealed class ProductionImport : IImportStep
{
    public static readonly (string Prefix, string Preferred, string Name)[] Sources =
    [
        ("G29", "", "shifts"),
        ("G28", "", "employees"),
        ("G27", "", "occurrences"),
        ("X09", "XY090", "production orders"),
        ("X31", "XY310", "internal orders"),
        ("X06", "XY060", "order materials"),
        ("X28", "XY280", "overrun releases"),
        ("X13", "XY130", "shop-floor reports"),
        ("X14", "XY140", "labor reports"),
        ("X15", "XY150", "machine reports"),
        ("E24", "", "scrap")
    ];

    private EbtDbContext db = null!;
    private ImportReport report = null!;
    private ProductionService service = null!;
    private Dictionary<string, int> products = new();
    private Dictionary<string, Material> materials = new();
    private readonly Dictionary<(ProductionOrderKind, int), ProductionOrder> orders = new();
    private readonly Dictionary<string, ProductionReport> reports = new();

    public async Task RunAsync(EbtDbContext context, ImportOptions options, Encoding encoding, ImportReport importReport, CancellationToken ct)
    {
        db = context;
        report = importReport;
        service = new ProductionService(db, new StockService(db), new BomService(db));
        var (tables, control) = Discover(options.Directory);
        products = await db.Products.AsNoTracking().ToDictionaryAsync(p => p.Code, p => p.Id, ct);
        materials = await db.Materials.AsNoTracking().ToDictionaryAsync(m => m.Code, ct);

        List<LegacyRow> Rows(string prefix)
        {
            var name = Sources.First(s => s.Prefix == prefix).Name;
            if (!tables.TryGetValue(prefix, out var path))
            {
                report.Warnings.Add($"No DBF found for {name} ({prefix}*); skipped.");
                return [];
            }
            report.For(name).File = Path.GetFileName(path);
            return LegacyDbf.Read(path, encoding).ToList();
        }

        var counters = control is not null ? await ImportSettings(LegacyDbf.Read(control, encoding).FirstOrDefault(), Path.GetFileName(control), ct) : new Dictionary<string, int>();
        if (control is null) report.Warnings.Add("No CACONTR.DBF found; production settings and order counters left as they are.");

        await ImportShifts(Rows("G29"), ct);
        await ImportEmployees(Rows("G28"), ct);
        await ImportOccurrences(Rows("G27"), ct);
        await LoadOrders(ct);
        await ImportOrders(Rows("X09"), ProductionOrderKind.Standard, ct);
        await ImportOrders(Rows("X31"), ProductionOrderKind.Internal, ct);
        LinkOrders(Rows("X09"));
        await db.SaveChangesAsync(ct);
        await ImportMaterials(Rows("X06"), ct);
        await ImportOverruns(Rows("X28"), ct);
        await ImportReports(Rows("X13"), Rows("X14"), Rows("X15"), ct);
        await ImportScrap(Rows("E24"), ct);
        await db.SaveChangesAsync(ct);

        if (orders.Values.Any(o => o.Status is ProductionOrderStatus.Released or ProductionOrderStatus.InProduction or ProductionOrderStatus.Stopped))
            report.Warnings.Add("Open legacy orders were imported without stock reservations; issue their material with the production issue endpoint.");
        if (!options.DryRun)
        {
            await Advance(EbtDbContext.ProductionOrderNumbers, ProductionOrderKind.Standard, counters.GetValueOrDefault("CA_NROP"), ct);
            await Advance(EbtDbContext.InternalOrderNumbers, ProductionOrderKind.Internal, counters.GetValueOrDefault("CA_NROPI"), ct);
        }
    }

    private (Dictionary<string, string> Tables, string? Control) Discover(string dir)
    {
        var found = new Dictionary<string, List<string>>();
        string? control = null;
        foreach (var path in Directory.EnumerateFiles(dir, "*", SearchOption.TopDirectoryOnly).Where(p => p.EndsWith(".dbf", StringComparison.OrdinalIgnoreCase)))
        {
            if (Path.GetFileNameWithoutExtension(path).Equals("CACONTR", StringComparison.OrdinalIgnoreCase)) { control = path; continue; }
            LegacyTable? table;
            try { table = LegacyDbf.Describe(path); }
            catch (Exception) { continue; }
            if (table is null) continue;
            if (!found.TryGetValue(table.Prefix, out var list)) found[table.Prefix] = list = new();
            list.Add(path);
        }
        var result = new Dictionary<string, string>();
        foreach (var (prefix, preferred, name) in Sources)
        {
            if (!found.TryGetValue(prefix, out var candidates)) continue;
            var pick = candidates.FirstOrDefault(p => Path.GetFileNameWithoutExtension(p).Equals(preferred, StringComparison.OrdinalIgnoreCase));
            if (pick is null && candidates.Count > 1)
            {
                report.Warnings.Add($"Several files look like {name} ({string.Join(", ", candidates.Select(Path.GetFileName))}); skipped. Remove the extra copies.");
                continue;
            }
            result[prefix] = pick ?? candidates[0];
        }
        return (result, control);
    }

    private async Task<Dictionary<string, int>> ImportSettings(LegacyRow? row, string file, CancellationToken ct)
    {
        var counters = new Dictionary<string, int>();
        if (row is null) return counters;
        report.For("production settings").File = file;
        var settings = await db.ProductionSettings.FirstOrDefaultAsync(ct);
        var inserted = settings is null;
        settings ??= db.ProductionSettings.Add(new ProductionSettings { Id = 1 }).Entity;
        if (row.Dec("TOL_APONTA") is >= 0 and <= 100 and var tol) settings.OverrunTolerancePercent = tol;
        await db.SaveChangesAsync(ct);
        Count("production settings", inserted);
        foreach (var f in new[] { "CA_NROP", "CA_NROPI" })
            if (row.Int(f) is > 0 and var v) counters[f] = v;
        return counters;
    }

    private async Task ImportShifts(List<LegacyRow> rows, CancellationToken ct)
    {
        const string table = "shifts";
        var existing = await db.Shifts.ToDictionaryAsync(s => s.Code, ct);
        foreach (var r in rows)
        {
            if (Code(r.Str("G29IDTURNO"), 10) is not { } code) { Skip(table, "row without code"); continue; }
            var inserted = !existing.TryGetValue(code, out var s);
            if (inserted) db.Shifts.Add(existing[code] = s = new Shift { Code = code, Name = code });
            s!.Name = r.Str("G29NMTURNO") ?? s.Name;
            s.StartsAt = Time(r.Str("G29HRINIC")) ?? s.StartsAt;
            s.EndsAt = Time(r.Str("G29HRFIM")) ?? s.EndsAt;
            s.Hours = Hours(r.Str("G29HRTRAB")) ?? s.Hours;
            Count(table, inserted);
        }
        await db.SaveChangesAsync(ct);
    }

    private async Task ImportEmployees(List<LegacyRow> rows, CancellationToken ct)
    {
        const string table = "employees";
        var existing = await db.Employees.ToDictionaryAsync(e => e.Code, ct);
        var shifts = await db.Shifts.AsNoTracking().ToDictionaryAsync(s => s.Code, s => s.Id, ct);
        var centers = await db.WorkCenters.AsNoTracking().ToDictionaryAsync(w => w.Code, w => w.Id, ct);
        foreach (var r in rows)
        {
            if (Code(r.Str("G28IDFUNC"), 10) is not { } code) { Skip(table, "row without code"); continue; }
            var inserted = !existing.TryGetValue(code, out var e);
            if (inserted) db.Employees.Add(existing[code] = e = new Employee { Code = code, Name = code });
            e!.Name = Text(r.Str("G28NMFUNC") ?? e.Name, 80);
            e.Nickname = r.Str("G28APELIDO") ?? e.Nickname;
            e.Function = r.Str("G28FUNCAO") ?? e.Function;
            if (r.Str("G28IDTURNO") is { } t && shifts.TryGetValue(t.ToUpperInvariant(), out var sid)) e.ShiftId = sid;
            if (r.Str("G28IDSETOR") is { } w && centers.TryGetValue(w, out var wid)) e.WorkCenterId = wid;
            e.Active = !r.Flag("G28AFASTAD");
            Count(table, inserted);
        }
        await db.SaveChangesAsync(ct);
    }

    private async Task ImportOccurrences(List<LegacyRow> rows, CancellationToken ct)
    {
        const string table = "occurrences";
        var existing = await db.ProductionOccurrences.ToDictionaryAsync(o => o.Code, ct);
        foreach (var r in rows)
        {
            if (Code(r.Str("G27IDOCORR"), 10) is not { } code) { Skip(table, "row without code"); continue; }
            var inserted = !existing.TryGetValue(code, out var o);
            if (inserted) db.ProductionOccurrences.Add(existing[code] = o = new ProductionOccurrence { Code = code, Description = code, Kind = OccurrenceKind.Downtime });
            o!.Description = r.Str("G27DSOCORR") ?? o.Description;
            o.StopsOrder = r.Flag("G27STATOF", o.StopsOrder);
            Count(table, inserted);
        }
        await db.SaveChangesAsync(ct);
    }

    private async Task LoadOrders(CancellationToken ct)
    {
        foreach (var o in await db.ProductionOrders.Include(o => o.Operations).Include(o => o.Materials).ToListAsync(ct)) orders[(o.Kind, o.Number)] = o;
        foreach (var r in await db.ProductionReports.Where(r => r.LegacyKey != null).ToListAsync(ct)) reports[r.LegacyKey!] = r;
    }

    private async Task ImportOrders(List<LegacyRow> rows, ProductionOrderKind kind, CancellationToken ct)
    {
        var p = kind == ProductionOrderKind.Internal ? "X31" : "X09";
        var table = kind == ProductionOrderKind.Internal ? "internal orders" : "production orders";
        foreach (var r in rows)
        {
            if (Number(r.Str(kind == ProductionOrderKind.Internal ? "X31IDOPI" : "X09CDOP")) is not { } number) { Skip(table, "row without number"); continue; }
            var code = r.Str($"{p}CDPECA");
            if (code is null || !products.TryGetValue(code, out var productId)) { Skip(table, $"{ProductionService.ReferenceFor(kind, number)}: unknown product {code}"); continue; }
            var qty = r.Dec($"{p}QTDPRO") ?? 0m;
            if (qty <= 0) { Skip(table, $"{ProductionService.ReferenceFor(kind, number)}: quantity is zero"); continue; }
            var created = r.Date($"{p}DTCAD");
            var due = r.Date(kind == ProductionOrderKind.Internal ? "X31DTPROD" : "X09DTENTR") ?? created ?? DateOnly.FromDateTime(DateTime.Today);
            var inserted = !orders.TryGetValue((kind, number), out var o);
            if (inserted)
            {
                o = new ProductionOrder
                {
                    Kind = kind, Number = number, Reference = ProductionService.ReferenceFor(kind, number), ProductId = productId, Quantity = qty, DueDate = due,
                    CreatedBy = r.Str($"{p}USUARIO") ?? "import", CreatedAt = Stamp(created) ?? DateTimeOffset.UtcNow
                };
                await service.SnapshotStructureAsync(o, ct);
                db.ProductionOrders.Add(o);
                orders[(kind, number)] = o;
            }
            else if (o!.ProductId != productId)
            {
                Skip(table, $"{o.Reference}: product changed from the previous import; left as it was");
                continue;
            }
            o!.Quantity = qty;
            o.DueDate = due;
            if (kind == ProductionOrderKind.Standard) o.PlannedStart = r.Date("X09DTINIPR") ?? o.PlannedStart;
            else o.Bales = r.Int("X31FARDOS") ?? o.Bales;
            o.ReleasedAt = Stamp(r.Date($"{p}DTIMPR")) ?? o.ReleasedAt;
            o.Status = Status(r.Str($"{p}STATUS"), o.Status);
            if (kind == ProductionOrderKind.Standard && r.Date("X09DTENCER") is { } closed)
            {
                o.Status = ProductionOrderStatus.Closed;
                o.ClosedAt = Stamp(closed);
                o.ClosedBy ??= "import";
                o.FinishedAt ??= o.ClosedAt;
            }
            if (kind == ProductionOrderKind.Standard) o.CostClosedAt = Stamp(r.Date("X09DTENCUS")) ?? o.CostClosedAt;
            if (o.Status == ProductionOrderStatus.Finished) o.FinishedAt ??= o.ReleasedAt ?? o.CreatedAt;
            foreach (var m in o.Materials) m.RequiredQuantity = Math.Round(m.QuantityPerUnit * o.Quantity, 4);
            Count(table, inserted);
        }
    }

    private void LinkOrders(List<LegacyRow> rows)
    {
        foreach (var r in rows)
        {
            if (Number(r.Str("X09CDOP")) is not { } n || !orders.TryGetValue((ProductionOrderKind.Standard, n), out var o)) continue;
            if (Number(r.Str("X09CDOPPAI")) is { } parent && parent != n)
            {
                if (orders.TryGetValue((ProductionOrderKind.Standard, parent), out var p)) o.ParentOrder = p;
                else report.Warnings.Add($"production orders: {o.Reference} refers to unknown parent OF {parent}");
            }
            if (Number(r.Str("X09CDOPANT") ?? r.Str("X09NROPANT")) is { } previous && previous != n && orders.TryGetValue((ProductionOrderKind.Standard, previous), out var prev)) o.PreviousOrder = prev;
        }
    }

    private async Task ImportMaterials(List<LegacyRow> rows, CancellationToken ct)
    {
        const string table = "order materials";
        var groups = rows.Select(r => (Row: r, Number: Number(r.Str("X06CDOP")))).Where(x => x.Number is not null).GroupBy(x => x.Number!.Value);
        foreach (var g in groups)
        {
            if (!orders.TryGetValue((ProductionOrderKind.Standard, g.Key), out var o)) { foreach (var _ in g) Skip(table, $"unknown OF {g.Key}"); continue; }
            if (o.Materials.Any(m => m.ReservationId is not null)) { foreach (var _ in g) Skip(table, $"{o.Reference} already has reservations; left as it was"); continue; }
            var lines = new List<ProductionOrderMaterial>();
            foreach (var (r, _) in g)
            {
                var code = r.Str("X06CDMATER");
                var seq = r.Int("X06NROPER") ?? o.Operations.Select(op => (int?)op.Sequence).Min() ?? 10;
                var qty = r.Dec("X06QTMATER") ?? 0m;
                if (code is null || qty <= 0) { Skip(table, $"{o.Reference}: row without material or quantity"); continue; }
                var isProduct = (r.Str("X06TPMATER") ?? "M").ToUpperInvariant().StartsWith('C');
                int? mid = null, pid = null;
                string unit;
                if (!isProduct && materials.TryGetValue(code, out var m)) { mid = m.Id; unit = m.StockUnit; }
                else if (products.TryGetValue(code, out var p)) { pid = p; unit = (await db.Products.AsNoTracking().Where(x => x.Id == p).Select(x => x.StockUnit).FirstAsync(ct)); }
                else { Skip(table, $"{o.Reference}: unknown item {code}"); continue; }
                lines.Add(new ProductionOrderMaterial { OperationSequence = seq, MaterialId = mid, ComponentProductId = pid, QuantityPerUnit = Math.Round(qty / o.Quantity, 6), RequiredQuantity = qty, Unit = Text(unit, 3) });
            }
            if (lines.Count == 0) continue;
            static string Signature(IEnumerable<ProductionOrderMaterial> l) => string.Join("|", l.Select(x => $"{x.OperationSequence}:{x.MaterialId}:{x.ComponentProductId}:{x.RequiredQuantity:0.####}").Order());
            var same = Signature(o.Materials) == Signature(lines);
            foreach (var _ in lines) Count(table, !same);
            if (same) continue;
            db.ProductionOrderMaterials.RemoveRange(o.Materials);
            o.Materials.Clear();
            o.Materials.AddRange(lines);
        }
        await db.SaveChangesAsync(ct);
    }

    private async Task ImportOverruns(List<LegacyRow> rows, CancellationToken ct)
    {
        const string table = "overrun releases";
        var existing = await db.OverrunReleases.AsNoTracking().Select(r => new { r.OperationId, r.Quantity, r.Justification }).ToListAsync(ct);
        foreach (var r in rows)
        {
            if (Order(r.Str("X28CDOP"), table) is not { } o) continue;
            var qty = r.Dec("X28QTDLIB") ?? 0m;
            if (qty <= 0) { Skip(table, $"{o.Reference}: quantity is zero"); continue; }
            var op = await Operation(o, r.Int("X28NROPER"), ct);
            var justification = r.Str("X28JUSTIF") ?? "Liberação importada";
            if (existing.Any(x => x.OperationId == op.Id && x.Quantity == qty && x.Justification == justification)) { report.For(table).Updated++; continue; }
            db.OverrunReleases.Add(new OverrunRelease { OperationId = op.Id, Quantity = qty, Justification = justification, ReleasedBy = r.Str("X28USUARIO"), ReleasedAt = Stamp(r.Date("X28DATA")) ?? DateTimeOffset.UtcNow });
            op.OverrunReleased += qty;
            Count(table, true);
        }
        await db.SaveChangesAsync(ct);
    }

    private async Task ImportReports(List<LegacyRow> x13, List<LegacyRow> x14, List<LegacyRow> x15, CancellationToken ct)
    {
        const string table = "shop-floor reports";
        var employees = await db.Employees.AsNoTracking().ToDictionaryAsync(e => e.Code, e => e.Id, ct);
        var machines = await db.Machines.AsNoTracking().ToDictionaryAsync(m => m.Code, m => m.Id, ct);
        var occurrences = await db.ProductionOccurrences.AsNoTracking().ToDictionaryAsync(o => o.Code, o => o.Id, ct);
        var labor = x14.Where(r => r.Str("X14PK") is not null).GroupBy(r => r.Str("X14PK")!).ToDictionary(g => g.Key, g => g.First());
        var machine = x15.Where(r => r.Str("X15PK") is not null).GroupBy(r => r.Str("X15PK")!).ToDictionary(g => g.Key, g => g.First());
        foreach (var r in x13)
        {
            if (r.Str("X13PK") is not { } pk) { Skip(table, "row without X13PK"); continue; }
            if (Order(r.Str("X13CDOP"), table) is not { } o) continue;
            var op = await Operation(o, r.Int("X13NROPER"), ct);
            var key = $"X13:{pk}";
            var inserted = !reports.TryGetValue(key, out var rep);
            if (inserted)
            {
                rep = new ProductionReport { Order = o, Operation = op, LegacyKey = key, ReportedAt = DateTimeOffset.UtcNow };
                db.ProductionReports.Add(reports[key] = rep);
            }
            rep!.Date = r.Date("X13DTCADAS") ?? DateOnly.FromDateTime(DateTime.Today);
            rep.GoodQuantity = Math.Max(0, r.Dec("X13QTD") ?? 0m);
            rep.Operators = r.Dec("X13QTOPERA") is > 0 and var ops ? ops : rep.Operators;
            rep.WeightKg = r.Dec("X13QTD_KG") is > 0 and var kg ? kg : rep.WeightKg;
            rep.DowntimeHours = Hours(r.Str("X13HRDESCO")) is > 0 and var dh ? dh : rep.DowntimeHours;
            if (r.Str("X13IDOCORR") is { } oc && occurrences.TryGetValue(oc.ToUpperInvariant(), out var oid)) rep.DowntimeOccurrenceId = oid;
            rep.StartTime = Time(r.Str("X13HRLANC")) ?? rep.StartTime;
            rep.ReportedBy = r.Str("X13USUARIO") ?? rep.ReportedBy ?? "import";
            if (labor.TryGetValue(pk, out var l) && l.Str("X14IDFUNC") is { } f && employees.TryGetValue(f.ToUpperInvariant(), out var eid)) rep.EmployeeId = eid;
            if (machine.TryGetValue(pk, out var mrow) && (mrow.Str("X15CDMAQRE") ?? mrow.Str("X15CDMAQPD")) is { } mc && machines.TryGetValue(mc, out var mid)) rep.MachineId = mid;
            rep.MachineId ??= op.MachineId;
            Count(table, inserted);
        }
        await db.SaveChangesAsync(ct);
    }

    private async Task ImportScrap(List<LegacyRow> rows, CancellationToken ct)
    {
        const string table = "scrap";
        foreach (var g in rows.GroupBy(r => (Of: r.Str("E24OF"), Op: r.Int("E24NROPER"), Doc: r.Str("E24NRDOC"))))
        {
            var first = g.First();
            if (Order(g.Key.Of, table) is not { } o) continue;
            var qty = g.Sum(r => r.Dec("E24REFUGO") ?? 0m);
            if (qty <= 0) { Skip(table, $"{o.Reference}: scrap quantity is zero"); continue; }
            var op = await Operation(o, g.Key.Op, ct);
            var key = Text($"E24:{o.Number}:{op.Sequence}:{g.Key.Doc ?? "-"}", 30);
            var inserted = !reports.TryGetValue(key, out var rep);
            if (inserted)
            {
                rep = new ProductionReport { Order = o, Operation = op, LegacyKey = key, ReportedBy = "import", ReportedAt = DateTimeOffset.UtcNow, Date = DateOnly.FromDateTime(DateTime.Today) };
                db.ProductionReports.Add(reports[key] = rep);
            }
            rep!.ScrapQuantity = qty;
            rep.Notes = first.Str("E24LOTE") is { } lot ? $"Lote {lot}" : rep.Notes;
            Count(table, inserted);
        }
        await db.SaveChangesAsync(ct);
    }

    private ProductionOrder? Order(string? number, string table)
    {
        if (Number(number) is not { } n) { Skip(table, "row without OF"); return null; }
        if (orders.TryGetValue((ProductionOrderKind.Standard, n), out var o)) return o;
        Skip(table, $"unknown OF {n}");
        return null;
    }

    private async Task<ProductionOrderOperation> Operation(ProductionOrder o, int? sequence, CancellationToken ct)
    {
        var seq = sequence is > 0 ? sequence.Value : o.Operations.Select(x => (int?)x.Sequence).Min() ?? 10;
        if (o.Operations.FirstOrDefault(x => x.Sequence == seq) is { } op) return op;
        op = new ProductionOrderOperation { Sequence = seq, Description = "Importada" };
        o.Operations.Add(op);
        report.Warnings.Add($"{o.Reference}: operation {seq} is not in the current routing; created from legacy data.");
        await db.SaveChangesAsync(ct);
        return op;
    }

    private async Task Advance(string sequence, ProductionOrderKind kind, int counter, CancellationToken ct)
    {
        var max = await db.ProductionOrders.Where(o => o.Kind == kind).MaxAsync(o => (int?)o.Number, ct) ?? 0;
        var last = Math.Max(max, counter);
        if (last > 0) await db.Database.ExecuteSqlRawAsync("SELECT setval('" + SqlIdentifier.Safe(sequence) + "', GREATEST(" + last + ", (SELECT last_value FROM " + SqlIdentifier.Safe(sequence) + ")))", ct);
    }

    private static ProductionOrderStatus Status(string? s, ProductionOrderStatus fallback) => s?.Trim() switch
    {
        "0" => ProductionOrderStatus.Created,
        "1" => ProductionOrderStatus.Released,
        "2" => ProductionOrderStatus.Stopped,
        "3" => ProductionOrderStatus.InProduction,
        "4" => ProductionOrderStatus.Cancelled,
        "5" => ProductionOrderStatus.Finished,
        _ => fallback
    };

    private static TimeOnly? Time(string? s) =>
        s is not null && TimeOnly.TryParseExact(s.Trim(), ["HH:mm", "HH:mm:ss", "H:mm", "HHmm"], CultureInfo.InvariantCulture, DateTimeStyles.None, out var t) ? t : null;

    private static decimal? Hours(string? s)
    {
        if (s is null) return null;
        if (Time(s) is { } t) return Math.Round((decimal)t.ToTimeSpan().TotalHours, 4);
        return decimal.TryParse(s.Replace(',', '.'), NumberStyles.Number, CultureInfo.InvariantCulture, out var d) ? d : null;
    }

    private static int? Number(string? s) => s is not null && int.TryParse(new string(s.Where(char.IsDigit).ToArray()), NumberStyles.None, CultureInfo.InvariantCulture, out var n) && n > 0 ? n : null;
    private static string? Code(string? s, int max) => s is null ? null : Text(s.Trim().ToUpperInvariant(), max);
    private static string Text(string s, int max) => s.Length <= max ? s : s[..max];
    private static DateTimeOffset? Stamp(DateOnly? d) => d is { } x ? new DateTimeOffset(x.ToDateTime(new TimeOnly(12, 0)), TimeSpan.Zero) : null;

    private void Skip(string table, string reason)
    {
        report.For(table).Skipped++;
        report.Warnings.Add($"{table}: {reason}");
    }

    private void Count(string table, bool inserted)
    {
        if (inserted) report.For(table).Inserted++;
        else report.For(table).Updated++;
    }
}
