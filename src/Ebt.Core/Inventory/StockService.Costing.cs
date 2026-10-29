using static Ebt.Core.Services.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;


namespace Ebt.Core.Inventory;

public partial class StockService
{
    public async Task<decimal> CurrentAverageAsync(int materialId, DateOnly date, CancellationToken ct = default)
    {
        var material = materials.TryGetValue(materialId, out var m) ? m : await db.Materials.AsNoTracking().FirstAsync(x => x.Id == materialId, ct);
        var period = PeriodOf(date);
        var thickness = Bucket(material);
        var row = await db.AverageCosts.AsNoTracking()
            .Where(a => a.Period < period && (thickness != null ? a.ThicknessMm == thickness : a.MaterialId == materialId))
            .OrderByDescending(a => a.Period).FirstOrDefaultAsync(ct);
        if (row is not null) return row.Average;
        var ids = await BucketMaterialIdsAsync(material, ct);
        var priced = db.StockMovements.Where(x => ids.Contains(x.MaterialId!.Value) && ValuedInbound.Contains(x.Type) && x.Location!.Kind != StockLocationKind.ThirdParty && x.UnitCost > 0);
        var qty = await priced.SumAsync(x => x.Quantity, ct);
        return qty > 0 ? Math.Round(await priced.SumAsync(x => x.Quantity * x.UnitCost, ct) / qty, 6) : 0m;
    }

    public async Task<StockClosing> ClosePeriodAsync(int period, string user, DateOnly today, CancellationToken ct = default)
    {
        if (period % 100 is < 1 or > 12 || period < 190001) throw StockException.Invalid("Use yyyymm", "period");
        if (period >= PeriodOf(today)) throw StockException.Invalid("Only past months can be closed", "period");
        return await InTransaction(async () =>
        {
            await db.Database.ExecuteSqlRawAsync("SELECT pg_advisory_xact_lock({0}, 0)", [GlobalLockClass], ct);
            settings = await SettingsAsync(ct);
            var last = await LastClosedPeriodAsync(ct);
            if (last is { } l && period <= l) throw StockException.Conflict($"Period {period} is already closed (last closed: {l})");
            if (last is { } l2 && period != PeriodOf(StartOf(l2).AddMonths(1))) throw StockException.Conflict($"Close {PeriodOf(StartOf(l2).AddMonths(1))} first");

            await db.AverageCosts.Where(a => a.Period == period).ExecuteDeleteAsync(ct);
            foreach (var row in await ComputeAveragesAsync(period, ct)) db.AverageCosts.Add(row);
            var closing = new StockClosing { Period = period, ClosedBy = user, ClosedAt = DateTimeOffset.UtcNow };
            db.StockClosings.Add(closing);
            await db.SaveChangesAsync(ct);
            return closing;
        }, ct);
    }

    public async Task ReopenPeriodAsync(int period, CancellationToken ct = default)
    {
        await InTransaction(async () =>
        {
            await db.Database.ExecuteSqlRawAsync("SELECT pg_advisory_xact_lock({0}, 0)", [GlobalLockClass], ct);
            var last = await LastClosedPeriodAsync(ct);
            if (last != period) throw StockException.Conflict(last is null ? "No period is closed" : $"Only the last closed period ({last}) can be reopened");
            await db.AverageCosts.Where(a => a.Period == period && !a.Imported).ExecuteDeleteAsync(ct);
            await db.StockClosings.Where(c => c.Period == period).ExecuteDeleteAsync(ct);
            return 0;
        }, ct);
    }

    private readonly record struct BucketKey(decimal? ThicknessMm, int? MaterialId);
    private sealed record BeforeRow(decimal? ThicknessMm, int? MaterialId, decimal Qty, decimal PricedQty, decimal PricedGross, decimal PricedNet);
    private sealed record PeriodRow(decimal? ThicknessMm, int? MaterialId, MovementType Type, decimal Qty, decimal Gross, decimal Net);
    private readonly record struct Sums(decimal Qty, decimal Gross, decimal Net);

    /// <summary>Weighted average cost per bucket (thickness, or single material when it has none). Movements are aggregated in SQL, never loaded row by row.</summary>
    public async Task<List<AverageCost>> ComputeAveragesAsync(int period, CancellationToken ct = default)
    {
        settings ??= await SettingsAsync(ct);
        var start = StartOf(period);
        var end = start.AddMonths(1);
        var deduct = settings.DeductIcmsFromAverage;

        // Moves before the period: total on hand, plus the priced inbound subset used to seed the first average.
        var before = (await db.StockMovements.AsNoTracking()
            .Where(x => x.MaterialId != null && x.Date < start)
            .Select(x => new
            {
                Thickness = x.Material!.ThicknessMm > 0 ? x.Material.ThicknessMm : (decimal?)null,
                Material = x.Material.ThicknessMm > 0 ? (int?)null : x.MaterialId,
                x.Quantity, x.UnitCost, x.IcmsRate,
                Priced = ValuedInbound.Contains(x.Type) && x.Location!.Kind != StockLocationKind.ThirdParty && x.UnitCost > 0
            })
            .GroupBy(x => new { x.Thickness, x.Material })
            .Select(g => new BeforeRow(g.Key.Thickness, g.Key.Material,
                g.Sum(x => x.Quantity),
                g.Sum(x => x.Priced ? x.Quantity : 0m),
                Math.Round(g.Sum(x => x.Priced ? x.Quantity * x.UnitCost : 0m), 10),
                Math.Round(g.Sum(x => x.Priced ? x.Quantity * x.UnitCost * (1 - x.IcmsRate / 100m) : 0m), 10)))
            .ToListAsync(ct)).ToDictionary(r => new BucketKey(r.ThicknessMm, r.MaterialId));

        // Moves inside the period that drive the average, grouped by type.
        var periodTypes = new[] { MovementType.OpeningBalance, MovementType.Receipt, MovementType.ThirdPartyReturn };
        var inPeriod = (await db.StockMovements.AsNoTracking()
            .Where(x => x.MaterialId != null && x.Date >= start && x.Date < end && periodTypes.Contains(x.Type) && x.Location!.Kind != StockLocationKind.ThirdParty)
            .Select(x => new
            {
                Thickness = x.Material!.ThicknessMm > 0 ? x.Material.ThicknessMm : (decimal?)null,
                Material = x.Material.ThicknessMm > 0 ? (int?)null : x.MaterialId,
                x.Type, x.Quantity, x.UnitCost, x.IcmsRate
            })
            .GroupBy(x => new { x.Thickness, x.Material, x.Type })
            .Select(g => new PeriodRow(g.Key.Thickness, g.Key.Material, g.Key.Type,
                g.Sum(x => x.Quantity), Math.Round(g.Sum(x => x.Quantity * x.UnitCost), 10), Math.Round(g.Sum(x => x.Quantity * x.UnitCost * (1 - x.IcmsRate / 100m)), 10)))
            .ToListAsync(ct))
            .GroupBy(r => new BucketKey(r.ThicknessMm, r.MaterialId))
            .ToDictionary(g => g.Key, g => g.ToDictionary(r => r.Type, r => new Sums(r.Qty, r.Gross, deduct ? r.Net : r.Gross)));

        var previous = await db.AverageCosts.AsNoTracking().Where(a => a.Period < period)
            .GroupBy(a => new { a.ThicknessMm, a.MaterialId })
            .Select(g => g.OrderByDescending(a => a.Period).First())
            .ToListAsync(ct);
        var prevByBucket = previous.ToDictionary(a => new BucketKey(a.ThicknessMm, a.MaterialId));

        var buckets = before.Keys.Concat(inPeriod.Keys).Concat(prevByBucket.Keys).Distinct();
        var rows = new List<AverageCost>();
        foreach (var bucket in buckets)
        {
            var b = before.GetValueOrDefault(bucket);
            var p = inPeriod.GetValueOrDefault(bucket);
            Sums At(MovementType t) => p is not null && p.TryGetValue(t, out var s) ? s : default;
            var opening = At(MovementType.OpeningBalance);
            var purchases = At(MovementType.Receipt);
            var services = At(MovementType.ThirdPartyReturn);

            var qtyBefore = b?.Qty ?? 0m;
            decimal openingAvg;
            prevByBucket.TryGetValue(bucket, out var prev);
            if (prev is not null)
            {
                var q = Math.Max(0, qtyBefore);
                openingAvg = q + opening.Qty > 0 ? (prev.Average * q + opening.Gross) / (q + opening.Qty) : prev.Average;
            }
            else
            {
                var pq = (b?.PricedQty ?? 0m) + opening.Qty;
                openingAvg = pq > 0 ? (((deduct ? b?.PricedNet : b?.PricedGross) ?? 0m) + opening.Net) / pq : 0m;
            }
            var openingQty = Math.Max(0, qtyBefore + opening.Qty);

            var cutting = services.Qty > 0 ? services.Qty * settings.CuttingServicePerKg : 0m;
            var serviceNet = services.Net + cutting;
            var serviceGross = services.Gross + cutting;

            var inflow = purchases.Qty + services.Qty;
            decimal monthAvg = 0, avg = openingAvg, avgGross = prev?.AverageGross ?? openingAvg;
            if (inflow > 0)
            {
                monthAvg = WithScrap((purchases.Net + serviceNet) / inflow);
                var monthGross = WithScrap((purchases.Gross + serviceGross) / inflow);
                avg = Blend(openingAvg, openingQty, monthAvg, inflow);
                avgGross = Blend(prev?.AverageGross ?? openingAvg, openingQty, monthGross, inflow);
            }
            if (inflow == 0 && openingQty == 0 && prev is null && openingAvg == 0) continue;

            rows.Add(new AverageCost
            {
                Period = period, ThicknessMm = bucket.ThicknessMm, MaterialId = bucket.MaterialId,
                OpeningQuantity = openingQty, OpeningAverage = Math.Round(openingAvg, 6),
                PurchaseQuantity = purchases.Qty, PurchaseValue = Math.Round(purchases.Net, 4),
                ServiceQuantity = services.Qty, ServiceValue = Math.Round(serviceNet, 4),
                MonthAverage = Math.Round(monthAvg, 6), Average = Math.Round(avg, 6), AverageGross = Math.Round(avgGross, 6)
            });
        }
        return rows;
    }

    private decimal WithScrap(decimal m) => m + settings.ScrapPercent / 100m * (m - settings.ScrapResalePerKg);

    private static decimal Blend(decimal prevAvg, decimal prevQty, decimal monthAvg, decimal monthQty) =>
        prevQty + monthQty > 0 ? (prevAvg * prevQty + monthAvg * monthQty) / (prevQty + monthQty) : monthAvg;

    private static decimal? Bucket(Material m) => m.ThicknessMm is > 0 ? m.ThicknessMm : null;

    private async Task<List<int>> BucketMaterialIdsAsync(Material m, CancellationToken ct) =>
        Bucket(m) is { } t ? await db.Materials.Where(x => x.ThicknessMm == t).Select(x => x.Id).ToListAsync(ct) : [m.Id];
}
