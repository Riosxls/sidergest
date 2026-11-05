using System.Globalization;
using System.Text;

namespace Ebt.Core.Sales;

/// <summary>Material specification classes that move the price (NBK costs about 30 R$/kg, BK 22.7, EN 10305 20, SAE 20.3, NBR 19.9).</summary>
public static class PriceSpec
{
    public static readonly string[] Classes = ["EN10305", "NBK", "BK", "NBR", "SAE", "other"];

    /// <summary>Class of a raw specification text ("NBK DIN 2393", "DIN EN 10305-3 E420 + CR2"...) or of an already normalized class; null for empty text.</summary>
    public static string? Classify(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var t = Fold(text).ToUpperInvariant().Trim();
        var known = Classes.FirstOrDefault(c => c.Equals(t, StringComparison.OrdinalIgnoreCase));
        if (known is not null) return known;
        if (Has(t, "E420", "E355", "10305", "CR2")) return "EN10305";
        if (Has(t, "NBK")) return "NBK";
        if (Has(t, "BK")) return "BK";
        if (Has(t, "5599", "NBR")) return "NBR";
        if (Has(t, "SAE", "1010", "1008", "1020")) return "SAE";
        return "other";
    }

    private static bool Has(string t, params string[] words) => words.Any(w => t.Contains(w, StringComparison.Ordinal));

    private static string Fold(string s)
    {
        var sb = new StringBuilder();
        foreach (var c in s.Normalize(NormalizationForm.FormD))
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        return sb.ToString();
    }
}
