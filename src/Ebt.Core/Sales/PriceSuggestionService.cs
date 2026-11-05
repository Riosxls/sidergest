using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Sales;

public sealed record PriceWeight(decimal NetKg, decimal GrossKg, decimal LossPercent);
public sealed record PriceSuggestionOut(string Basis, string Confidence, decimal? PricePerKg, decimal? Low, decimal? High, decimal? PricePerPiece, decimal? TotalForQuantity);
public sealed record PriceSimilar(DateOnly Date, string Customer, decimal Diameter, decimal Thickness, decimal Length, string Unit, decimal UnitPrice, decimal PricePerKg, double Distance, string Source, string? Spec);
public sealed record PriceCustomerLast(DateOnly Date, decimal Diameter, decimal Thickness, decimal Length, string Unit, decimal UnitPrice, decimal PricePerKg);
public sealed record PriceSuggestionResult(PriceWeight Weight, PriceSuggestionOut Suggestion, IReadOnlyList<PriceSimilar> Similar, PriceCustomerLast? CustomerLast, int HistoryCount);
public sealed record PriceHistorySummary(int Count, DateOnly? FirstDate, DateOnly? LastDate);

/// <summary>
/// Suggests a price per kg and per piece for a circular tube from what EBT charged before: the imported <c>price_history</c> rows plus the live (non-test) sales order lines of the last 24 months.
/// Weighted k-nearest-neighbours on (diameter, wall, length) in log space; a customer that bought nearly the same tube before simply gets its last price.
/// </summary>
public sealed class PriceSuggestionService(EbtDbContext db)
{
    public const int WindowMonths = 24;
    public const int Neighbours = 7;
    public const int SimilarShown = 10;
    public const double RepeatDistance = 0.25;
    public const double HighConfidenceDistance = 0.1;
    public const double MediumConfidenceDistance = 0.4;

    private sealed record Point(DateOnly Date, string Customer, int? CustomerId, decimal D, decimal T, decimal L, string Unit, decimal UnitPrice, decimal PricePerKg, string Source, string? Spec);

    /// <summary>Added (as a squared term) to the distance when both sides have a known specification class and the classes differ.</summary>
    public const double SpecPenalty = 0.6;

    public static double Distance(decimal hD, decimal hT, decimal hL, decimal d, decimal t, decimal l, string? hSpec = null, string? spec = null) =>
        Math.Sqrt(4 * Sq(Math.Log((double)(hD / d))) + Sq(Math.Log((double)(hT / t))) + 0.1 * Sq(Math.Log((double)(hL / l)))
            + (hSpec is not null && spec is not null && hSpec != spec ? Sq(SpecPenalty) : 0));

    private static double Sq(double x) => x * x;

    public async Task<PriceHistorySummary> SummaryAsync(CancellationToken ct = default) =>
        new(await db.PriceHistory.CountAsync(ct), await db.PriceHistory.MinAsync(h => (DateOnly?)h.Date, ct), await db.PriceHistory.MaxAsync(h => (DateOnly?)h.Date, ct));

    public async Task<PriceSuggestionResult> SuggestAsync(decimal diameter, decimal thickness, decimal length, int? customerId, decimal? quantity, int? productId, string? spec = null, CancellationToken ct = default)
    {
        var wantSpec = PriceSpec.Classify(spec);
        var net = TubeWeight.NetWeightKg(TubeShape.Circular, diameter, null, null, thickness, length) ?? throw SalesException.Invalid("diameter", "Invalid dimensions");
        var loss = TubeWeight.DefaultLossPercent;
        if (productId is { } pid && await db.Products.AsNoTracking().Where(p => p.Id == pid).Select(p => p.LossPercent).FirstOrDefaultAsync(ct) is > 0 and var own) loss = own;
        var weight = new PriceWeight(Math.Round(net, 3), Math.Round(net * (1 + loss / 100m), 3), loss);

        var customerName = customerId is { } cid ? await db.Customers.AsNoTracking().Where(c => c.Id == cid).Select(c => c.Name).FirstOrDefaultAsync(ct) : null;
        var customerKey = customerName is null ? null : NormalizeName(customerName);

        var all = await LoadAsync(ct);
        var since = Clock.Today().AddMonths(-WindowMonths);
        var window = all.Where(p => p.Date >= since).ToList();

        bool Mine(Point p) => customerKey is { Length: > 0 } && (customerId is not null && p.CustomerId == customerId || NamesMatch(customerKey, NormalizeName(p.Customer)));
        var mine = all.Where(Mine).ToList();
        var last = mine.OrderByDescending(p => p.Date).ThenBy(p => Distance(p.D, p.T, p.L, diameter, thickness, length, p.Spec, wantSpec)).FirstOrDefault();
        var customerLast = last is null ? null : new PriceCustomerLast(last.Date, last.D, last.T, last.L, last.Unit, last.UnitPrice, Math.Round(last.PricePerKg, 2));

        var ranked = window.Select(p => (P: p, Dist: Distance(p.D, p.T, p.L, diameter, thickness, length, p.Spec, wantSpec))).OrderBy(x => x.Dist).ThenByDescending(x => x.P.Date).ToList();
        var similar = ranked.Take(SimilarShown).Select(x => new PriceSimilar(x.P.Date, x.P.Customer, x.P.D, x.P.T, x.P.L, x.P.Unit, Math.Round(x.P.UnitPrice, 2), Math.Round(x.P.PricePerKg, 2), Math.Round(x.Dist, 4), x.P.Source, x.P.Spec)).ToList();

        if (ranked.Count == 0)
            return new(weight, new("None", "Low", null, null, null, null, null), similar, customerLast, 0);

        string basis, confidence;
        decimal pricePerKg, low, high;
        var near = ranked.Where(x => x.Dist < RepeatDistance && Mine(x.P)).ToList();
        if (near.Count > 0)
        {
            basis = "CustomerRepeat";
            confidence = "High";
            pricePerKg = near[0].P.PricePerKg;
            low = near.Min(x => x.P.PricePerKg);
            high = near.Max(x => x.P.PricePerKg);
        }
        else
        {
            basis = "Neighbours";
            var k = ranked.Take(Neighbours).ToList();
            double sw = 0, swl = 0;
            foreach (var (p, dist) in k)
            {
                var w = 1 / (0.02 + dist);
                sw += w;
                swl += w * Math.Log((double)p.PricePerKg);
            }
            pricePerKg = (decimal)Math.Exp(swl / sw);
            low = k.Min(x => x.P.PricePerKg);
            high = k.Max(x => x.P.PricePerKg);
            confidence = ranked[0].Dist < HighConfidenceDistance ? "High" : ranked[0].Dist < MediumConfidenceDistance ? "Medium" : "Low";
        }

        var perKg = SalesService.Money(pricePerKg);
        var suggestion = new PriceSuggestionOut(basis, confidence, perKg, SalesService.Money(low), SalesService.Money(high), SalesService.Money(perKg * net),
            quantity is > 0 ? SalesService.Money(perKg * net * quantity.Value) : null);
        return new(weight, suggestion, similar, customerLast, window.Count);
    }

    /// <summary>History rows plus live order lines of circular products, every price converted to R$/kg.</summary>
    private async Task<List<Point>> LoadAsync(CancellationToken ct)
    {
        var points = (await db.PriceHistory.AsNoTracking()
                .Select(h => new { h.Date, h.CustomerName, h.DiameterMm, h.ThicknessMm, h.LengthMm, h.Unit, h.UnitPrice, h.PricePerKg, h.Spec }).ToListAsync(ct))
            .Select(h => new Point(h.Date, h.CustomerName, null, h.DiameterMm, h.ThicknessMm, h.LengthMm, h.Unit, h.UnitPrice, h.PricePerKg, "Histórico", h.Spec)).ToList();

        var lines = await db.SalesOrderLines.AsNoTracking()
            .Where(l => l.Order!.Source != DataSource.Test && l.Order.Status != SalesOrderStatus.Cancelled && l.UnitPrice > 0 && l.Product!.Shape == TubeShape.Circular)
            .Select(l => new
            {
                l.Order!.CreatedAt, l.Order.CustomerId, Customer = l.Order.Customer!.Name, l.UnitPrice, l.SaleUnit, l.Unit, l.Standard,
                D = l.OutsideDiameter ?? l.Product!.DiameterMm, T = l.Thickness ?? l.Product!.ThicknessMm, L = l.Length ?? l.Product!.LengthMm
            }).ToListAsync(ct);
        foreach (var l in lines)
        {
            if (l.D is not > 0 || l.T is not > 0 || l.L is not > 0) continue;
            var weight = TubeWeight.NetWeightKg(TubeShape.Circular, l.D, null, null, l.T, l.L);
            if (weight is not > 0) continue;
            var perKg = string.Equals(l.SaleUnit ?? l.Unit, "KG", StringComparison.OrdinalIgnoreCase) ? l.UnitPrice : l.UnitPrice / weight.Value;
            var unit = string.Equals(l.SaleUnit ?? l.Unit, "KG", StringComparison.OrdinalIgnoreCase) ? "KG" : "PC";
            points.Add(new(DateOnly.FromDateTime(l.CreatedAt.UtcDateTime), l.Customer, l.CustomerId, l.D.Value, l.T.Value, l.L.Value, unit, l.UnitPrice, perKg, "MetaGest", PriceSpec.Classify(l.Standard)));
        }
        return points;
    }

    private static readonly Regex SaSuffix = new(@"(?<![a-z0-9])s\.?\s?/?\s?a\.?(?![a-z0-9])", RegexOptions.Compiled);
    private static readonly HashSet<string> Suffixes = ["ltda", "eireli", "me", "epp"];

    /// <summary>Lower case, no accents or punctuation, without the company-type words (LTDA, S.A., EIRELI, ME).</summary>
    public static string NormalizeName(string name)
    {
        var d = name.Trim().ToLowerInvariant().Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder();
        foreach (var c in d)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        var s = SaSuffix.Replace(sb.ToString(), " ");
        var words = Regex.Split(s, @"[^a-z0-9]+").Where(w => w.Length > 0 && !Suffixes.Contains(w));
        return string.Join(' ', words);
    }

    /// <summary>Best effort: equal after normalizing, or one starts with the other (at least 4 characters, on a word boundary).</summary>
    public static bool NamesMatch(string a, string b)
    {
        if (a.Length == 0 || b.Length == 0) return false;
        if (a == b) return true;
        var (shorter, longer) = a.Length <= b.Length ? (a, b) : (b, a);
        return shorter.Length >= 4 && longer.StartsWith(shorter + " ", StringComparison.Ordinal);
    }
}
