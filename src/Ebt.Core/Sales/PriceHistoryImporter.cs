using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Sales;

public sealed record PriceHistoryImportResult(int Read, int Imported, int Duplicates, int Skipped, DateOnly? FirstDate, DateOnly? LastDate, int Updated = 0);

/// <summary>Reads the price history CSV (see scripts/export-price-history.ps1) into <c>price_history</c>. Re-importing the same file adds nothing.</summary>
public sealed class PriceHistoryImporter(EbtDbContext db)
{
    private const int Chunk = 1000;

    private sealed record Row(DateOnly Date, string Customer, decimal D, decimal T, decimal L, string Unit, decimal Price, decimal Weight, decimal PerKg, string Key, string? Spec);

    public static string DecodeText(byte[] bytes)
    {
        try
        {
            var text = new UTF8Encoding(false, true).GetString(bytes);
            return text.TrimStart('﻿');
        }
        catch (DecoderFallbackException)
        {
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            return Encoding.GetEncoding(1252).GetString(bytes);
        }
    }

    public async Task<PriceHistoryImportResult> ImportAsync(byte[] file, CancellationToken ct = default)
    {
        var lines = Records(DecodeText(file)).ToList();
        if (lines.Count == 0) throw SalesException.Invalid("file", "Empty file");
        var cols = MapHeader(lines[0]);
        foreach (var (name, label) in new[] { ("date", "data"), ("customer", "cliente"), ("diameter", "diametro"), ("thickness", "espessura"), ("length", "comprimento"), ("unit", "unid"), ("price", "valor unit") })
            if (!cols.ContainsKey(name)) throw SalesException.Invalid("file", $"Missing column: {name} ({label})");

        int read = 0, skipped = 0, duplicates = 0, updated = 0;
        var rows = new Dictionary<string, Row>();
        foreach (var rec in lines.Skip(1))
        {
            if (rec.All(string.IsNullOrWhiteSpace)) continue;
            read++;
            if (Parse(rec, cols) is not { } row) { skipped++; continue; }
            if (rows.TryGetValue(row.Key, out var seen))
            {
                duplicates++;
                // The same sale repeated (monthly sheets, two sources): keep the latest date and any specification.
                var (later, earlier) = row.Date >= seen.Date ? (row, seen) : (seen, row);
                rows[row.Key] = later with { Spec = later.Spec ?? earlier.Spec };
            }
            else rows[row.Key] = row;
        }

        var existing = new Dictionary<string, PriceHistory>();
        var keys = rows.Keys.ToList();
        for (var i = 0; i < keys.Count; i += Chunk)
        {
            var part = keys.Skip(i).Take(Chunk).ToList();
            foreach (var h in await db.PriceHistory.Where(h => part.Contains(h.ImportKey)).ToListAsync(ct)) existing[h.ImportKey] = h;
        }
        var imported = 0;
        foreach (var r in rows.Values)
        {
            if (existing.TryGetValue(r.Key, out var old))
            {
                // Upsert: a re-import with a later date or a newly known specification refreshes the stored row instead of adding a duplicate.
                var date = r.Date > old.Date ? r.Date : old.Date;
                var spec = r.Date > old.Date ? r.Spec ?? old.Spec : old.Spec ?? r.Spec;
                if (date == old.Date && spec == old.Spec) { duplicates++; continue; }
                old.Date = date;
                old.Spec = spec;
                updated++;
                continue;
            }
            imported++;
            db.PriceHistory.Add(new PriceHistory
            {
                Date = r.Date, CustomerName = r.Customer, DiameterMm = r.D, ThicknessMm = r.T, LengthMm = r.L, Unit = r.Unit, UnitPrice = r.Price,
                WeightKg = r.Weight, PricePerKg = r.PerKg, Spec = r.Spec, ImportKey = r.Key, Source = "Import"
            });
        }
        if (imported + updated > 0) await db.SaveChangesAsync(ct);
        return new(read, imported, duplicates, skipped, rows.Count == 0 ? null : rows.Values.Min(r => r.Date), rows.Count == 0 ? null : rows.Values.Max(r => r.Date), updated);
    }

    /// <summary>First six letters (A-Z, no accents) of the customer name: tolerant to LTDA/S.A. and spelling differences between sources.</summary>
    public static string CustomerKey(string name) =>
        new string(Fold(name).ToLowerInvariant().Where(c => c is >= 'a' and <= 'z').Take(6).ToArray());

    private static Row? Parse(IReadOnlyList<string> rec, Dictionary<string, int> cols)
    {
        string Cell(string name) => cols.TryGetValue(name, out var i) && i < rec.Count ? rec[i].Trim() : "";
        if (ParseDate(Cell("date")) is not { } date) return null;
        var customer = Regex.Replace(Cell("customer"), @"\s+", " ");
        if (customer.Length == 0 || customer.Length > 200) return null;
        var d = ParseNumber(Cell("diameter"));
        var t = ParseNumber(Cell("thickness"));
        var l = ParseNumber(Cell("length"));
        var price = ParseNumber(Cell("price"));
        if (d is not > 0 || t is not > 0 || l is not > 0 || price is not > 0 || t * 2 >= d) return null;
        if (ParseUnit(Cell("unit")) is not { } unit) return null;
        var weight = TubeWeight.NetWeightKg(TubeShape.Circular, d, null, null, t, l);
        if (weight is not > 0) return null;
        var perKg = unit == "KG" ? price.Value : price.Value / weight.Value;
        var key = string.Join('|', CustomerKey(customer), Num(d.Value), Num(t.Value), Num(l.Value), unit, Math.Round(price.Value, 2, MidpointRounding.AwayFromZero).ToString("0.00", CultureInfo.InvariantCulture));
        return new(date, customer, d.Value, t.Value, l.Value, unit, price.Value, weight.Value, Math.Round(perKg, 6), key, PriceSpec.Classify(Cell("spec")));
    }

    private static string Num(decimal v) => v.ToString("0.######", CultureInfo.InvariantCulture);

    public static string? ParseUnit(string? raw)
    {
        var u = Fold(raw ?? "").Replace(".", "").Replace(" ", "").ToUpperInvariant();
        return u switch { "KG" or "KGS" => "KG", "PC" or "PCS" or "PECA" or "PECAS" => "PC", _ => null };
    }

    public static DateOnly? ParseDate(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var s = raw.Trim();
        string[] formats = ["yyyy-MM-dd", "dd/MM/yyyy", "d/M/yyyy", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-ddTHH:mm:ss", "dd/MM/yyyy HH:mm:ss", "dd/MM/yy", "d/M/yy"];
        if (DateTime.TryParseExact(s, formats, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt) && dt.Year is >= 2000 and <= 2100) return DateOnly.FromDateTime(dt);
        if (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var serial) && serial is >= 40000 and <= 48000) return DateOnly.FromDateTime(DateTime.FromOADate(Math.Floor(serial)));
        return null;
    }

    /// <summary>"R$ 1.234,56", "1234,56", "1234.56" and "1,234.56" all read as expected. A lone dot is a decimal point.</summary>
    public static decimal? ParseNumber(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var s = raw.Replace("R$", "", StringComparison.OrdinalIgnoreCase).Replace(" ", "").Replace(" ", "");
        if (s.Length == 0) return null;
        var comma = s.LastIndexOf(',');
        var dot = s.LastIndexOf('.');
        if (comma >= 0 && dot >= 0)
            s = comma > dot ? s.Replace(".", "").Replace(',', '.') : s.Replace(",", "");
        else if (comma >= 0)
            s = s.Replace(',', '.');
        else if (s.Count(c => c == '.') > 1)
            s = s.Replace(".", "");
        return decimal.TryParse(s, NumberStyles.AllowDecimalPoint | NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var v) && Math.Abs(v) < 1_000_000_000m ? v : null;
    }

    private static string Fold(string s)
    {
        var d = s.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder();
        foreach (var c in d)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        return sb.ToString().Normalize(NormalizationForm.FormC);
    }

    private static Dictionary<string, int> MapHeader(IReadOnlyList<string> header)
    {
        var map = new Dictionary<string, int>();
        for (var i = 0; i < header.Count; i++)
        {
            var h = new string(Fold(header[i]).ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());
            string? name = h switch
            {
                "data" or "date" => "date",
                "cliente" or "customer" => "customer",
                "diametro" or "diameter" => "diameter",
                "espessura" or "thickness" => "thickness",
                "unid" or "unidade" or "unit" => "unit",
                "price" or "preco" => "price",
                "spec" or "especificacao" or "especificacaodomaterial" => "spec",
                _ when h.StartsWith("comprim") || h == "length" => "length",
                _ when h.StartsWith("valorunit") || h == "valor" => "price",
                _ when h.StartsWith("quant") || h == "qtd" => "quantity",
                _ => null
            };
            if (name is not null) map.TryAdd(name, i);
        }
        return map;
    }

    /// <summary>Splits CSV text into records (quotes, doubled quotes and line breaks inside quotes); the delimiter (; , or tab) comes from the header line.</summary>
    public static IEnumerable<List<string>> Records(string text)
    {
        var firstLine = text.Split('\n', 2)[0];
        var delim = new[] { ';', ',', '\t' }.OrderByDescending(c => firstLine.Count(x => x == c)).First();
        var fields = new List<string>();
        var sb = new StringBuilder();
        var quoted = false;
        for (var i = 0; i < text.Length; i++)
        {
            var c = text[i];
            if (quoted)
            {
                if (c == '"' && i + 1 < text.Length && text[i + 1] == '"') { sb.Append('"'); i++; }
                else if (c == '"') quoted = false;
                else sb.Append(c);
            }
            else if (c == '"') quoted = true;
            else if (c == delim) { fields.Add(sb.ToString()); sb.Clear(); }
            else if (c == '\n' || c == '\r')
            {
                if (c == '\r' && i + 1 < text.Length && text[i + 1] == '\n') i++;
                fields.Add(sb.ToString());
                sb.Clear();
                yield return fields;
                fields = [];
            }
            else sb.Append(c);
        }
        if (sb.Length > 0 || fields.Count > 0)
        {
            fields.Add(sb.ToString());
            yield return fields;
        }
    }
}
