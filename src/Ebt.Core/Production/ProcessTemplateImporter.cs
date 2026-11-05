using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Sales;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Production;

/// <param name="Read">Data rows read (one row per operation).</param>
/// <param name="Templates">New templates created.</param>
/// <param name="Updated">Existing templates whose process was replaced by a newer (or equal date, different) one.</param>
/// <param name="Operations">Operations written (of the new and the updated templates).</param>
/// <param name="SkippedReasons">Skipped rows by reason: <c>medidas</c> (no customer or no usable diameter/thickness), <c>operação</c> (row without description), <c>data</c> (missing, unreadable or more than 30 days ahead). Always all three keys.</param>
public sealed record ProcessTemplateImportResult(int Read, int Templates, int Updated, int Operations, int Skipped, IReadOnlyDictionary<string, int> SkippedReasons, DateOnly? FirstDate, DateOnly? LastDate);

public sealed record ProcessTemplateSummary(int Templates, int Operations, int Customers, DateOnly? FirstDate, DateOnly? LastDate);

/// <summary>Reads the legacy process CSV (see scripts/export-process-templates.ps1) into <c>process_templates</c>. One template per customer and tube; the latest OF wins. Re-importing the same file changes nothing.</summary>
public sealed class ProcessTemplateImporter(EbtDbContext db)
{
    private const string ReasonMeasures = "medidas", ReasonOperation = "operação", ReasonDate = "data";

    private sealed record Op(int Sequence, string Description, string? Tolerance, string? Start, string? End, string? Resource);
    private sealed record Candidate(string? Key, string Customer, decimal D, decimal? T, decimal? L, string? Spec, string Ref, DateOnly Date, List<Op> Ops);

    /// <summary>Imports the file. Two imports racing on the same new templates hit the unique key: the loser starts over once and, if that fails too, answers 409.</summary>
    public async Task<ProcessTemplateImportResult> ImportAsync(byte[] file, CancellationToken ct = default)
    {
        try
        {
            try { return await ImportCoreAsync(file, ct); }
            catch (DbUpdateException e) when (IsUniqueViolation(e))
            {
                db.ChangeTracker.Clear();
                return await ImportCoreAsync(file, ct);
            }
        }
        catch (DbUpdateException e) when (IsUniqueViolation(e))
        {
            throw ProductionException.Conflict("Outra importação está em andamento. Tente de novo em instantes.");
        }
    }

    private static bool IsUniqueViolation(DbUpdateException e) => e.InnerException is Npgsql.PostgresException { SqlState: Npgsql.PostgresErrorCodes.UniqueViolation };

    public async Task<ProcessTemplateSummary> SummaryAsync(CancellationToken ct = default) =>
        new(await db.ProcessTemplates.CountAsync(ct), await db.ProcessTemplateOperations.CountAsync(ct),
            await db.ProcessTemplates.Where(t => t.CustomerKey != null).Select(t => t.CustomerKey).Distinct().CountAsync(ct),
            await db.ProcessTemplates.MinAsync(t => t.SourceDate, ct), await db.ProcessTemplates.MaxAsync(t => t.SourceDate, ct));

    private async Task<ProcessTemplateImportResult> ImportCoreAsync(byte[] file, CancellationToken ct)
    {
        var lines = PriceHistoryImporter.Records(PriceHistoryImporter.DecodeText(file)).ToList();
        if (lines.Count == 0) throw ProductionException.Invalid("file", "Empty file");
        var cols = MapHeader(lines[0]);
        foreach (var name in new[] { "date", "customer", "diameter", "description" })
            if (!cols.ContainsKey(name)) throw ProductionException.Invalid("file", $"Missing column: {name}");

        var reasons = new Dictionary<string, int> { [ReasonMeasures] = 0, [ReasonOperation] = 0, [ReasonDate] = 0 };
        var today = Clock.Today();
        var read = 0;
        var groups = new List<(List<IReadOnlyList<string>> Rows, string Of)>();
        var byOf = new Dictionary<string, int>();
        foreach (var rec in lines.Skip(1))
        {
            if (rec.All(string.IsNullOrWhiteSpace)) continue;
            read++;
            var of = Cell(rec, cols, "of");
            var key = of.Length > 0 ? of : string.Join('|', Cell(rec, cols, "date"), Cell(rec, cols, "customer"), Cell(rec, cols, "diameter"), Cell(rec, cols, "thickness"), Cell(rec, cols, "length"));
            if (!byOf.TryGetValue(key, out var gi)) { gi = groups.Count; byOf[key] = gi; groups.Add(([], of.Length > 0 ? of : key)); }
            groups[gi].Rows.Add(rec);
        }

        DateOnly? firstDate = null, lastDate = null;
        var candidates = new Dictionary<(string?, decimal, decimal?, decimal?), Candidate>();
        foreach (var (rows, of) in groups)
        {
            var first = rows[0];
            if (PriceHistoryImporter.ParseDate(Cell(first, cols, "date")) is not { } date || date > today.AddDays(PriceHistoryImporter.MaxFutureDays)) { reasons[ReasonDate] += rows.Count; continue; }
            var customer = System.Text.RegularExpressions.Regex.Replace(Cell(first, cols, "customer"), @"\s+", " ");
            var d = PriceHistoryImporter.ParseNumber(Cell(first, cols, "diameter"));
            var tText = Cell(first, cols, "thickness");
            var lText = Cell(first, cols, "length");
            var t = PriceHistoryImporter.ParseNumber(tText);
            var l = PriceHistoryImporter.ParseNumber(lText);
            if (customer.Length is 0 or > 200 || d is not > 0 || d >= 100000
                || (tText.Length > 0 && (t is not > 0 || t * 2 >= d)) || (lText.Length > 0 && l is not > 0))
            { reasons[ReasonMeasures] += rows.Count; continue; }
            var ops = new List<Op>();
            var seq = 0;
            foreach (var r in rows)
            {
                var description = System.Text.RegularExpressions.Regex.Replace(Cell(r, cols, "description"), @"\s+", " ");
                if (description.Length == 0 || description.Length > 200) { reasons[ReasonOperation]++; continue; }
                seq++;
                var number = PriceHistoryImporter.ParseNumber(Cell(r, cols, "seq"));
                ops.Add(new Op(number is { } n && n == Math.Floor(n) && n is > 0 and < 100000 ? (int)n : seq * 10, description, Opt(r, cols, "tolerance", 60), Opt(r, cols, "start", 60), Opt(r, cols, "end", 60), Opt(r, cols, "resource", 100)));
            }
            if (ops.Count == 0) continue;
            if (firstDate is null || date < firstDate) firstDate = date;
            if (lastDate is null || date > lastDate) lastDate = date;
            var spec = Opt(first, cols, "spec", 100);
            var ckey = PriceHistoryImporter.CustomerKey(customer).ToUpperInvariant();
            var cand = new Candidate(ckey.Length == 0 ? null : ckey, customer, Math.Round(d.Value, 4), t is null ? null : Math.Round(t.Value, 4), l is null ? null : Math.Round(l.Value, 4), spec, of.Length > 0 ? of : "?", date,
                ops.Select((o, i) => (o, i)).OrderBy(x => x.o.Sequence).ThenBy(x => x.i).Select(x => x.o).ToList());
            var k = (cand.Key, cand.D, cand.T, cand.L);
            if (!candidates.TryGetValue(k, out var seen) || cand.Date >= seen.Date) candidates[k] = cand;
        }

        int created = 0, updated = 0, written = 0;
        var existing = (await db.ProcessTemplates.Include(t => t.Operations).ToListAsync(ct)).ToDictionary(t => (t.CustomerKey, t.DiameterMm, t.ThicknessMm, t.LengthMm));
        var now = DateTimeOffset.UtcNow;
        foreach (var (k, c) in candidates)
        {
            var newOps = c.Ops.Select((o, i) => new ProcessTemplateOperation { Sequence = o.Sequence, Description = o.Description, Tolerance = o.Tolerance, MeasureStart = o.Start, MeasureEnd = o.End, Resource = o.Resource }).ToList();
            if (existing.TryGetValue(k, out var old))
            {
                if (old.SourceDate is { } od && od > c.Date) continue;
                if (old.SourceDate == c.Date && old.SourceRef == c.Ref && old.CustomerName == c.Customer && old.Spec == c.Spec && Same(old.Operations, newOps)) continue;
                db.ProcessTemplateOperations.RemoveRange(old.Operations);
                old.Operations = newOps;
                old.CustomerName = c.Customer;
                old.Spec = c.Spec;
                old.SourceRef = c.Ref;
                old.SourceDate = c.Date;
                old.UpdatedAt = now;
                updated++;
            }
            else
            {
                db.ProcessTemplates.Add(new ProcessTemplate
                {
                    CustomerKey = c.Key, CustomerName = c.Customer, DiameterMm = c.D, ThicknessMm = c.T, LengthMm = c.L, Spec = c.Spec, SourceRef = c.Ref, SourceDate = c.Date, UpdatedAt = now, Operations = newOps
                });
                created++;
            }
            written += newOps.Count;
        }
        if (created + updated > 0) await db.SaveChangesAsync(ct);
        var skipped = reasons.Values.Sum();
        return new(read, created, updated, written, skipped, reasons, firstDate, lastDate);
    }

    private static bool Same(IEnumerable<ProcessTemplateOperation> a, IEnumerable<ProcessTemplateOperation> b)
    {
        string S(ProcessTemplateOperation o) => $"{o.Sequence}|{o.Description}|{o.Tolerance}|{o.MeasureStart}|{o.MeasureEnd}|{o.Resource}";
        return a.OrderBy(o => o.Sequence).ThenBy(o => o.Description).Select(S).SequenceEqual(b.OrderBy(o => o.Sequence).ThenBy(o => o.Description).Select(S));
    }

    private static string Cell(IReadOnlyList<string> rec, Dictionary<string, int> cols, string name) =>
        cols.TryGetValue(name, out var i) && i < rec.Count ? rec[i].Trim() : "";

    private static string? Opt(IReadOnlyList<string> rec, Dictionary<string, int> cols, string name, int max)
    {
        var v = System.Text.RegularExpressions.Regex.Replace(Cell(rec, cols, name), @"\s+", " ");
        return v.Length == 0 ? null : v.Length > max ? v[..max] : v;
    }

    private static Dictionary<string, int> MapHeader(IReadOnlyList<string> header)
    {
        var map = new Dictionary<string, int>();
        for (var i = 0; i < header.Count; i++)
        {
            var h = new string(PriceHistoryImporter.Fold(header[i]).ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());
            string? name = h switch
            {
                "of" or "op" or "ordem" or "ordemdefabricacao" => "of",
                "data" or "date" => "date",
                "cliente" or "customer" => "customer",
                "diametro" or "diameter" => "diameter",
                "espessura" or "thickness" => "thickness",
                "spec" or "especificacao" or "especificacaodomaterial" => "spec",
                "seq" or "sequencia" or "num" or "numero" or "n" => "seq",
                "description" or "descricao" or "operacao" or "processo" => "description",
                "tolerance" or "tolerancia" or "requisitos" or "requisitostolerancia" => "tolerance",
                "start" or "inicio" or "medidainicio" => "start",
                "end" or "fim" or "medidafim" => "end",
                "resource" or "recurso" or "maquina" or "maqferramenta" or "maquinaferramenta" => "resource",
                _ when h.StartsWith("comprim") || h == "length" => "length",
                _ => null
            };
            if (name is not null) map.TryAdd(name, i);
        }
        return map;
    }
}
