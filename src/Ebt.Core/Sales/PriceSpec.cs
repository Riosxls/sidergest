using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Ebt.Core.Sales;

/// <summary>Material specification classes that move the price (NBK costs about 30 R$/kg, BK 22.7, EN 10305 20, SAE 20.3, NBR 19.9).</summary>
public static class PriceSpec
{
    public static readonly string[] Classes = ["EN10305", "NBK", "BK", "GBK", "STKM13A", "NBR", "SAE", "other"];

    private static readonly Regex Stkm13a = new(@"STKM\s*-?\s*13\s*-?\s*A", RegexOptions.Compiled);
    private static readonly Regex GbkWord = new(@"\bGBK\b", RegexOptions.Compiled);
    private static readonly Regex NbkWord = new(@"\bNBK\b", RegexOptions.Compiled);
    private static readonly Regex BkWord = new(@"\bBK\b", RegexOptions.Compiled);

    /// <summary>Class of a raw specification text ("NBK DIN 2393", "EN 10305-2 - BK", "DIN EN 10305-3 E420 + CR2"...) or of an already normalized class; null for empty text.
    /// Order: STKM13A (JIS G3445 steel grade), then the delivery-condition words GBK, NBK, BK (they win over the EN 10305 family: "EN 10305-2 - BK" is a BK tube), then EN 10305, NBR, SAE, else "other".</summary>
    public static string? Classify(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var t = Fold(text).ToUpperInvariant().Trim();
        var known = Classes.FirstOrDefault(c => c.Equals(t, StringComparison.OrdinalIgnoreCase));
        if (known is not null) return known;
        if (Stkm13a.IsMatch(t)) return "STKM13A";   // the steel grade (JIS G3445) drives the price more than a delivery condition written next to it
        if (GbkWord.IsMatch(t)) return "GBK";       // DIN 2393 annealed (geglüht): needs the furnace
        if (NbkWord.IsMatch(t)) return "NBK";
        if (BkWord.IsMatch(t)) return "BK";
        if (Has(t, "E420", "E355", "10305", "CR2")) return "EN10305";
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
