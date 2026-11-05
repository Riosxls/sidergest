using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace Ebt.Core.Sales;

public sealed record PriceWeight(decimal NetKg, decimal GrossKg, decimal LossPercent);
/// <summary><see cref="UsedCount"/> rows were averaged (the customer's near rows for a repeat); <see cref="NewestDate"/>/<see cref="OldestDate"/> are the dates of those rows.</summary>
public sealed record PriceSuggestionOut(string Basis, string Confidence, decimal? PricePerKg, decimal? Low, decimal? High, decimal? PricePerPiece, decimal? TotalForQuantity,
    int UsedCount = 0, DateOnly? NewestDate = null, DateOnly? OldestDate = null);
public sealed record PriceSimilar(DateOnly Date, string Customer, decimal Diameter, decimal Thickness, decimal Length, string Unit, decimal UnitPrice, decimal PricePerKg, double Distance, string Source, string? Spec);
public sealed record PriceCustomerLast(DateOnly Date, decimal Diameter, decimal Thickness, decimal Length, string Unit, decimal UnitPrice, decimal PricePerKg);
/// <summary>The row a "CustomerRepeat" price came from.</summary>
public sealed record PriceRepeat(DateOnly Date, string Customer, decimal Diameter, decimal Thickness, decimal Length, string Unit, decimal UnitPrice, decimal PricePerKg);
/// <summary>A past sale of nearly the same tube to the chosen customer (<see cref="Quantity"/> is not stored: always null).</summary>
public sealed record PriceCustomerSale(DateOnly Date, string Unit, decimal UnitPrice, decimal PricePerKg, decimal? Quantity);
/// <summary>Median R$/kg of the five nearest rows of a specification class, by dimensions only.</summary>
public sealed record PriceBySpec(string Spec, int Count, decimal MedianPerKg, double NearestDistance);
/// <summary>Median R$/kg of one month (<c>yyyy-MM</c>).</summary>
public sealed record PriceTrendPoint(string Month, decimal PricePerKg, int Count);
/// <summary>Informational only, never applied to the suggestion: 0.92 means this customer pays 8% below the market for similar tubes.</summary>
public sealed record PriceCustomerFactor(decimal Ratio, int SampleSize);
/// <summary>How the dimensions were read: "Round", or "Oblong"/"Rectangular" with the round tube of the same outside perimeter the price was compared with.</summary>
public sealed record PriceProfile(string Shape, decimal EquivalentDiameter);
public sealed record PriceSuggestionResult(PriceWeight Weight, PriceSuggestionOut Suggestion, IReadOnlyList<PriceSimilar> Similar, PriceCustomerLast? CustomerLast, int HistoryCount, PriceProfile? Profile = null,
    PriceRepeat? Repeat = null, IReadOnlyList<PriceCustomerSale>? CustomerHistory = null, IReadOnlyList<PriceBySpec>? BySpec = null,
    IReadOnlyList<PriceTrendPoint>? Trend = null, IReadOnlyList<PriceTrendPoint>? CustomerTrend = null, PriceCustomerFactor? CustomerFactor = null);
public sealed record PriceHistorySummary(int Count, DateOnly? FirstDate, DateOnly? LastDate);

/// <summary>One sale the suggestion can learn from (imported history or live order line), every price already converted to R$/kg.</summary>
internal sealed record PricePoint(DateOnly Date, string Customer, string NameKey, int? CustomerId, decimal D, decimal T, decimal L, string Unit, decimal UnitPrice, decimal PricePerKg, string Source, string? Spec);

/// <summary>Short-lived cache of the loaded price points (history + live lines): the table is read-mostly and a suggestion would otherwise read it all on every keystroke.
/// The import invalidates it; other writers (new orders) show up after the time to live. 0 seconds turns it off.</summary>
public sealed class PriceDataCache(IMemoryCache cache, int seconds = 60)
{
    private const string Key = "price-points";
    private int version;

    internal async Task<List<PricePoint>> GetAsync(Func<Task<List<PricePoint>>> load)
    {
        if (seconds <= 0) return await load();
        if (cache.TryGetValue(Key, out List<PricePoint>? hit) && hit is not null) return hit;
        var seen = Volatile.Read(ref version);
        var points = await load();
        // Only keep the result when no import finished while it was loading.
        if (seen == Volatile.Read(ref version)) cache.Set(Key, points, TimeSpan.FromSeconds(seconds));
        return points;
    }

    public void Invalidate()
    {
        Interlocked.Increment(ref version);
        cache.Remove(Key);
    }
}

/// <summary>
/// Suggests a price per kg and per piece for a tube of given dimensions from what EBT charged before: the imported <c>price_history</c> rows plus the live (non-test) sales order lines of the last 24 months.
/// Weighted k-nearest-neighbours on (diameter, wall, length) in log space, newer sales counting more; a customer that bought nearly the same tube before simply gets its latest price.
/// </summary>
public sealed class PriceSuggestionService(EbtDbContext db, PriceDataCache? cache = null)
{
    public const int WindowMonths = 24;
    public const int TrendMonths = 60;
    public const int Neighbours = 7;
    public const int SimilarShown = 10;
    public const double RepeatDistance = 0.25;
    public const double HighConfidenceDistance = 0.1;
    public const double MediumConfidenceDistance = 0.4;
    public const double TrendDistance = 0.6;
    /// <summary>A neighbour loses half of its weight every this many months of age.</summary>
    public const double RecencyHalfLifeMonths = 6;

    /// <summary>Added (as a squared term) to the distance when both sides have a known specification class and the classes differ.</summary>
    public const double SpecPenalty = 0.6;

    /// <summary>The "other" class means "not recognised", so it counts like an unknown specification: no penalty.</summary>
    public static double Distance(decimal hD, decimal hT, decimal hL, decimal d, decimal t, decimal l, string? hSpec = null, string? spec = null) =>
        Math.Sqrt(4 * Sq(Math.Log((double)(hD / d))) + Sq(Math.Log((double)(hT / t))) + 0.1 * Sq(Math.Log((double)(hL / l)))
            + (hSpec is not null && spec is not null && hSpec != spec && hSpec != "other" && spec != "other" ? Sq(SpecPenalty) : 0));

    /// <summary>0.5 per <see cref="RecencyHalfLifeMonths"/> months between the row date and today (a row from the future counts as today).</summary>
    public static double RecencyFactor(DateOnly date, DateOnly today) =>
        Math.Pow(0.5, Math.Max(0, today.DayNumber - date.DayNumber) / 30.4375 / RecencyHalfLifeMonths);

    private static double Sq(double x) => x * x;

    public async Task<PriceHistorySummary> SummaryAsync(CancellationToken ct = default) =>
        new(await db.PriceHistory.CountAsync(ct), await db.PriceHistory.MinAsync(h => (DateOnly?)h.Date, ct), await db.PriceHistory.MaxAsync(h => (DateOnly?)h.Date, ct));

    public Task<PriceSuggestionResult> SuggestAsync(decimal diameter, decimal thickness, decimal length, int? customerId, decimal? quantity, int? productId, string? spec = null, CancellationToken ct = default) =>
        SuggestCoreAsync(diameter, thickness, length, null, null, customerId, quantity, productId, spec, ct);

    /// <summary>Oblong tube: the weight is the real one of the oblong section; the price is looked up for the round tube with the same outside perimeter and wall
    /// (the history holds round tubes only), so it is the price of the round tube without anything for the forming of the shape.</summary>
    public Task<PriceSuggestionResult> SuggestOblongAsync(decimal width, decimal height, decimal thickness, decimal length, int? customerId, decimal? quantity, int? productId, string? spec = null, CancellationToken ct = default)
    {
        var net = TubeWeight.OblongNetWeightKg(width, height, thickness, length) ?? throw SalesException.Invalid("thickness", "Invalid dimensions");
        return SuggestCoreAsync(TubeWeight.OblongEquivalentDiameterMm(width, height), thickness, length, net, new PriceProfile("Oblong", TubeWeight.OblongEquivalentDiameterMm(width, height)), customerId, quantity, productId, spec, ct);
    }

    /// <summary>Rectangular or square tube (outer sides in either order): real weight of the section; priced like the round tube with the same outside perimeter and wall, like the oblong one.</summary>
    public Task<PriceSuggestionResult> SuggestRectangularAsync(decimal width, decimal height, decimal thickness, decimal length, int? customerId, decimal? quantity, int? productId, string? spec = null, CancellationToken ct = default)
    {
        var net = TubeWeight.NetWeightKg(TubeShape.Rectangular, null, width, height, thickness, length) ?? throw SalesException.Invalid("thickness", "Invalid dimensions");
        var equivalent = TubeWeight.RectEquivalentDiameterMm(width, height);
        return SuggestCoreAsync(equivalent, thickness, length, net, new PriceProfile("Rectangular", equivalent), customerId, quantity, productId, spec, ct);
    }

    private async Task<PriceSuggestionResult> SuggestCoreAsync(decimal diameter, decimal thickness, decimal length, decimal? netOverride, PriceProfile? profile, int? customerId, decimal? quantity, int? productId, string? spec, CancellationToken ct)
    {
        var wantSpec = PriceSpec.Classify(spec);
        var net = netOverride ?? TubeWeight.NetWeightKg(TubeShape.Circular, diameter, null, null, thickness, length) ?? throw SalesException.Invalid("diameter", "Invalid dimensions");
        var loss = TubeWeight.DefaultLossPercent;
        if (productId is { } pid && await db.Products.AsNoTracking().Where(p => p.Id == pid).Select(p => p.LossPercent).FirstOrDefaultAsync(ct) is > 0 and var own) loss = own;
        var weight = new PriceWeight(Math.Round(net, 3), Math.Round(net * (1 + loss / 100m), 3), loss);

        var customerName = customerId is { } cid ? await db.Customers.AsNoTracking().Where(c => c.Id == cid).Select(c => c.Name).FirstOrDefaultAsync(ct) : null;
        var customerKey = customerName is null ? null : NormalizeName(customerName);

        var all = await LoadAsync(ct);
        var today = Clock.Today();
        var since = today.AddMonths(-WindowMonths);
        var window = all.Where(p => p.Date >= since).ToList();

        double Dist(PricePoint p) => Distance(p.D, p.T, p.L, diameter, thickness, length, p.Spec, wantSpec);
        bool Mine(PricePoint p) => customerKey is { Length: > 0 } && (customerId is not null && p.CustomerId == customerId || NamesMatch(customerKey, p.NameKey));
        var mine = all.Where(Mine).ToList();
        var last = mine.OrderByDescending(p => p.Date).ThenBy(Dist).FirstOrDefault();
        var customerLast = last is null ? null : new PriceCustomerLast(last.Date, last.D, last.T, last.L, last.Unit, last.UnitPrice, Math.Round(last.PricePerKg, 2));

        var ranked = window.Select(p => (P: p, Dist: Dist(p))).OrderBy(x => x.Dist).ThenByDescending(x => x.P.Date).ToList();
        var similar = ranked.Take(SimilarShown).Select(x => new PriceSimilar(x.P.Date, x.P.Customer, x.P.D, x.P.T, x.P.L, x.P.Unit, Math.Round(x.P.UnitPrice, 2), Math.Round(x.P.PricePerKg, 2), Math.Round(x.Dist, 4), x.P.Source, x.P.Spec)).ToList();

        // The customer's near rows come from the whole history (not only the window): a repeat order of a tube bought three years ago is still a repeat.
        var mineRanked = mine.Select(p => (P: p, Dist: Dist(p))).ToList();
        var nearMine = mineRanked.Where(x => x.Dist < RepeatDistance).ToList();
        var customerHistory = mineRanked.Where(x => x.Dist < HighConfidenceDistance).OrderByDescending(x => x.P.Date).ThenBy(x => x.Dist).Take(5)
            .Select(x => new PriceCustomerSale(x.P.Date, x.P.Unit, Math.Round(x.P.UnitPrice, 2), Math.Round(x.P.PricePerKg, 2), null)).ToList();

        var bySpec = window.Where(p => p.Spec is not null).GroupBy(p => p.Spec!).Select(g =>
        {
            var nearest = g.Select(p => (P: p, Dist: Distance(p.D, p.T, p.L, diameter, thickness, length))).OrderBy(x => x.Dist).ThenByDescending(x => x.P.Date).Take(5).ToList();
            return new PriceBySpec(g.Key, nearest.Count, Math.Round(Median(nearest.Select(x => x.P.PricePerKg)), 2), Math.Round(nearest[0].Dist, 4));
        }).Where(x => x.NearestDistance < 1.0).OrderBy(x => x.NearestDistance).ThenBy(x => x.Spec, StringComparer.Ordinal).ToList();

        var trendSince = today.AddMonths(-TrendMonths);
        List<PriceTrendPoint> Trend(IEnumerable<PricePoint> source) => source.Where(p => p.Date >= trendSince && Dist(p) < TrendDistance)
            .GroupBy(p => p.Date.ToString("yyyy-MM", CultureInfo.InvariantCulture)).OrderBy(g => g.Key, StringComparer.Ordinal)
            .Select(g => new PriceTrendPoint(g.Key, Math.Round(Median(g.Select(p => p.PricePerKg)), 2), g.Count())).ToList();
        var trend = Trend(all);
        var customerTrend = mine.Count == 0 ? new List<PriceTrendPoint>() : Trend(mine);
        var factor = CustomerFactor(all, mine);

        PriceSuggestionResult Result(PriceSuggestionOut suggestion, PriceRepeat? repeat, int historyCount) =>
            new(weight, suggestion, similar, customerLast, historyCount, profile, repeat, customerHistory, bySpec, trend, customerTrend, factor);

        if (ranked.Count == 0 && nearMine.Count == 0)
            return Result(new("None", "Low", null, null, null, null, null), null, 0);

        string basis;
        decimal pricePerKg, low, high;
        List<(PricePoint P, double Dist)> used;
        PriceRepeat? repeat = null;
        if (nearMine.Count > 0)
        {
            basis = "CustomerRepeat";
            used = nearMine;
            // The latest sale of the customer wins (ties: the nearest tube), whatever its age.
            var source = nearMine.OrderByDescending(x => x.P.Date).ThenBy(x => x.Dist).First().P;
            pricePerKg = source.PricePerKg;
            low = nearMine.Min(x => x.P.PricePerKg);
            high = nearMine.Max(x => x.P.PricePerKg);
            repeat = new PriceRepeat(source.Date, source.Customer, source.D, source.T, source.L, source.Unit, Math.Round(source.UnitPrice, 2), Math.Round(source.PricePerKg, 2));
        }
        else
        {
            basis = "Neighbours";
            used = ranked.Take(Neighbours).ToList();
            double sw = 0, swl = 0;
            foreach (var (p, dist) in used)
            {
                var w = 1 / (0.02 + dist) * RecencyFactor(p.Date, today);
                sw += w;
                swl += w * Math.Log((double)p.PricePerKg);
            }
            pricePerKg = (decimal)Math.Exp(swl / sw);
            low = used.Min(x => x.P.PricePerKg);
            high = used.Max(x => x.P.PricePerKg);
        }

        var newest = used.Max(x => x.P.Date);
        var oldest = used.Min(x => x.P.Date);
        var nearest = used.Min(x => x.Dist);
        string confidence;
        if (nearest < HighConfidenceDistance && used.Count >= 3 && newest >= today.AddMonths(-12) || basis == "CustomerRepeat" && newest >= today.AddMonths(-24)) confidence = "High";
        else if (nearest >= MediumConfidenceDistance || used.Count < 2) confidence = "Low";
        else confidence = "Medium";

        var perKg = SalesService.Money(pricePerKg);
        var suggestion = new PriceSuggestionOut(basis, confidence, perKg, SalesService.Money(low), SalesService.Money(high), SalesService.Money(perKg * net),
            quantity is > 0 ? SalesService.Money(perKg * net * quantity.Value) : null, used.Count, newest, oldest);
        return Result(suggestion, repeat, window.Count);
    }

    /// <summary>
    /// How this customer's prices compare with the market for similar tubes: the median, over the customer's last 10 sales, of its R$/kg divided by the weighted
    /// nearest-neighbour price of everybody else's sales (same window before that sale). Needs three usable sales. INFORMATIONAL ONLY: it is never applied to the suggestion;
    /// walk-forward tests on real data showed that applying it made the predictions for new dimensions worse (median error 7.2% against 6.3%).
    /// </summary>
    private static PriceCustomerFactor? CustomerFactor(List<PricePoint> all, List<PricePoint> mine)
    {
        if (mine.Count < 3) return null;
        var mineSet = new HashSet<PricePoint>(mine, ReferenceEqualityComparer.Instance);
        var others = all.Where(p => !mineSet.Contains(p)).ToList();
        var ratios = new List<double>();
        foreach (var r in mine.OrderByDescending(p => p.Date).Take(10))
        {
            var from = r.Date.AddMonths(-WindowMonths);
            var k = others.Where(p => p.Date <= r.Date && p.Date >= from)
                .Select(p => (P: p, Dist: Distance(p.D, p.T, p.L, r.D, r.T, r.L, p.Spec, r.Spec))).OrderBy(x => x.Dist).Take(Neighbours).ToList();
            if (k.Count < 3 || k[0].Dist >= TrendDistance) continue;
            double sw = 0, swl = 0;
            foreach (var (p, dist) in k)
            {
                var w = 1 / (0.02 + dist);
                sw += w;
                swl += w * Math.Log((double)p.PricePerKg);
            }
            ratios.Add((double)r.PricePerKg / Math.Exp(swl / sw));
        }
        if (ratios.Count < 3) return null;
        ratios.Sort();
        var mid = ratios.Count / 2;
        var median = ratios.Count % 2 == 1 ? ratios[mid] : (ratios[mid - 1] + ratios[mid]) / 2;
        return new PriceCustomerFactor(Math.Round((decimal)median, 3), ratios.Count);
    }

    private static decimal Median(IEnumerable<decimal> values)
    {
        var s = values.OrderBy(v => v).ToList();
        var mid = s.Count / 2;
        return s.Count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
    }

    private Task<List<PricePoint>> LoadAsync(CancellationToken ct) => cache is null ? LoadCoreAsync(ct) : cache.GetAsync(() => LoadCoreAsync(ct));

    /// <summary>History rows plus live order lines of circular products, every price converted to R$/kg. A history row that the live line of the same sale already
    /// covers (same customer key, measures, price within 0.5% and date within 60 days) is dropped: the live line wins.</summary>
    private async Task<List<PricePoint>> LoadCoreAsync(CancellationToken ct)
    {
        var history = (await db.PriceHistory.AsNoTracking()
                .Select(h => new { h.Date, h.CustomerName, h.DiameterMm, h.ThicknessMm, h.LengthMm, h.Unit, h.UnitPrice, h.PricePerKg, h.Spec }).ToListAsync(ct))
            .Select(h => new PricePoint(h.Date, h.CustomerName, NormalizeName(h.CustomerName), null, h.DiameterMm, h.ThicknessMm, h.LengthMm, h.Unit, h.UnitPrice, h.PricePerKg, "Histórico", h.Spec)).ToList();

        var lines = await db.SalesOrderLines.AsNoTracking()
            .Where(l => l.Order!.Source != DataSource.Test && l.Order.Status != SalesOrderStatus.Cancelled && l.UnitPrice > 0 && l.Product!.Shape == TubeShape.Circular)
            .Select(l => new
            {
                l.Order!.CreatedAt, l.Order.CustomerId, Customer = l.Order.Customer!.Name, l.UnitPrice, l.SaleUnit, l.Unit, l.Standard,
                Decided = l.Order.QuoteId == null ? null : l.Order.Quote!.DecidedAt,
                D = l.OutsideDiameter ?? l.Product!.DiameterMm, T = l.Thickness ?? l.Product!.ThicknessMm, L = l.Length ?? l.Product!.LengthMm
            }).ToListAsync(ct);
        var live = new List<PricePoint>();
        foreach (var l in lines)
        {
            if (l.D is not > 0 || l.T is not > 0 || l.L is not > 0) continue;
            var weight = TubeWeight.NetWeightKg(TubeShape.Circular, l.D, null, null, l.T, l.L);
            if (weight is not > 0) continue;
            var perKg = string.Equals(l.SaleUnit ?? l.Unit, "KG", StringComparison.OrdinalIgnoreCase) ? l.UnitPrice : l.UnitPrice / weight.Value;
            var unit = string.Equals(l.SaleUnit ?? l.Unit, "KG", StringComparison.OrdinalIgnoreCase) ? "KG" : "PC";
            // The sale happened when the customer approved the quote; an order typed in directly dates from its creation (business-zone calendar day).
            var date = Clock.DateOf(l.Decided ?? l.CreatedAt);
            live.Add(new(date, l.Customer, NormalizeName(l.Customer), l.CustomerId, l.D.Value, l.T.Value, l.L.Value, unit, l.UnitPrice, perKg, "MetaGest", PriceSpec.Classify(l.Standard)));
        }

        var liveByCustomer = live.GroupBy(p => PriceHistoryImporter.CustomerKey(p.Customer)).ToDictionary(g => g.Key, g => g.ToList());
        var points = history.Where(h => !(liveByCustomer.TryGetValue(PriceHistoryImporter.CustomerKey(h.Customer), out var twins) && twins.Any(l => SameSale(h, l)))).ToList();
        points.AddRange(live);
        return points;
    }

    private static bool SameSale(PricePoint history, PricePoint live) =>
        Math.Abs(history.D - live.D) <= 0.01m && Math.Abs(history.T - live.T) <= 0.001m && Math.Abs(history.L - live.L) <= 1m
        && Math.Abs(history.Date.DayNumber - live.Date.DayNumber) <= 60
        && live.PricePerKg > 0 && Math.Abs(history.PricePerKg - live.PricePerKg) / live.PricePerKg <= 0.005m;

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
