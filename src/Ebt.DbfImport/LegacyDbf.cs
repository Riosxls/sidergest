using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using DbfDataReader;

namespace Ebt.DbfImport;

public sealed class LegacyRow(IReadOnlyDictionary<string, object?> values)
{
    public string? Str(string field)
    {
        if (!values.TryGetValue(field, out var v) || v is null) return null;
        var s = Convert.ToString(v, CultureInfo.InvariantCulture)?.Trim();
        return string.IsNullOrEmpty(s) ? null : s;
    }

    public decimal? Dec(string field)
    {
        if (!values.TryGetValue(field, out var v) || v is null) return null;
        return v switch
        {
            decimal d => d,
            int i => i,
            long l => l,
            double d => (decimal)d,
            float f => (decimal)f,
            string s when decimal.TryParse(s.Trim().Replace(',', '.'), NumberStyles.Number, CultureInfo.InvariantCulture, out var d) => d,
            _ => null
        };
    }

    public int? Int(string field) => Dec(field) is { } d ? (int)Math.Round(d) : null;

    public bool Flag(string field, bool fallback = false) => Str(field)?.ToUpperInvariant() switch
    {
        "S" or "Y" or "T" or "1" => true,
        "N" or "F" or "0" => false,
        _ => fallback
    };

    public string? Digits(string field) => Str(field) is { } s && Regex.Replace(s, @"\D", "") is { Length: > 0 } d ? d : null;
}

public sealed record LegacyTable(string Path, string Prefix, IReadOnlyList<string> Columns);

public static partial class LegacyDbf
{
    static LegacyDbf() => Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);

    [GeneratedRegex(@"^([A-Z])(\d\d)[A-Z_]")]
    private static partial Regex PrefixPattern();

    public static Encoding GetEncoding(int codePage) => Encoding.GetEncoding(codePage);

    public static LegacyTable? Describe(string path)
    {
        using var table = new DbfTable(path, Encoding.Latin1);
        var columns = table.Columns.Select(c => c.ColumnName.ToUpperInvariant()).ToList();
        var prefixes = columns.Select(c => PrefixPattern().Match(c)).Where(m => m.Success).Select(m => m.Groups[1].Value + m.Groups[2].Value).ToList();
        if (prefixes.Count == 0) return null;
        var prefix = prefixes.GroupBy(p => p).OrderByDescending(g => g.Count()).First().Key;
        return prefixes.Count(p => p == prefix) * 2 >= columns.Count ? new LegacyTable(path, prefix, columns) : null;
    }

    public static IEnumerable<LegacyRow> Read(string path, Encoding encoding)
    {
        using var table = new DbfTable(path, encoding);
        var names = table.Columns.Select(c => c.ColumnName.ToUpperInvariant()).ToList();
        var record = new DbfRecord(table);
        while (table.Read(record))
        {
            if (record.IsDeleted) continue;
            var values = new Dictionary<string, object?>(names.Count);
            for (var i = 0; i < names.Count; i++)
            {
                object? value;
                try { value = record.Values[i].GetValue(); }
                catch (FormatException) { value = null; }
                values[names[i]] = value;
            }
            yield return new LegacyRow(values);
        }
    }
}
