using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Inventory;

public record StockLine(
    int? MaterialId,
    int? ProductId,
    int LocationId,
    decimal Quantity,
    int? FromLocationId = null,
    int? LotId = null,
    string? LotCode = null,
    string? HeatNumber = null,
    decimal? UnitCost = null,
    decimal? IcmsRate = null,
    int? ReservationId = null,
    int? SourceMaterialId = null,
    decimal? SourceQuantity = null,
    bool? RequiresInspection = null);

public record StockPost(
    MovementType Type,
    DateOnly Date,
    IReadOnlyList<StockLine> Lines,
    string? Reference = null,
    int? SupplierId = null,
    int? CustomerId = null,
    string? Notes = null);

public readonly record struct StockItem(int? MaterialId, int? ProductId)
{
    public long LockKey => MaterialId is { } m ? m : -(long)ProductId!.Value;
}

public class StockService(EbtDbContext db)
{
    public static readonly MovementType[] Inbound = [MovementType.OpeningBalance, MovementType.Receipt, MovementType.ProductionReceipt, MovementType.CustomerReturn, MovementType.AdjustmentIn];
    public static readonly MovementType[] Outbound = [MovementType.Issue, MovementType.IndirectIssue, MovementType.Shipment, MovementType.ReturnToSupplier, MovementType.AdjustmentOut];
    public static readonly MovementType[] Paired = [MovementType.Transfer, MovementType.ThirdPartySend, MovementType.ThirdPartyReturn];
    private static readonly MovementType[] ConsumesFree = [MovementType.Issue, MovementType.IndirectIssue, MovementType.Shipment, MovementType.ThirdPartySend];
    private static readonly MovementType[] NewLotTypes = [MovementType.OpeningBalance, MovementType.Receipt, MovementType.ThirdPartyReturn];
    private static readonly MovementType[] ValuedInbound = [MovementType.OpeningBalance, MovementType.Receipt, MovementType.ThirdPartyReturn];

    private const int GlobalLockClass = 0;
    private const int ItemLockClass = 1;

    private readonly Dictionary<int, Material> materials = new();
    private readonly Dictionary<int, StockLocation> locations = new();
    private readonly Dictionary<(int? M, int? P, int L, int? Lot), StockBalance> balances = new();
    private StockSettings settings = null!;

    public static int PeriodOf(DateOnly d) => d.Year * 100 + d.Month;
    public static DateOnly StartOf(int period) => new(period / 100, period % 100, 1);

    public async Task<StockSettings> SettingsAsync(CancellationToken ct = default) =>
        await db.StockSettings.FirstOrDefaultAsync(ct) ?? throw new InvalidOperationException("stock_settings row missing");

    public async Task<int?> LastClosedPeriodAsync(CancellationToken ct = default) =>
        await db.StockClosings.MaxAsync(c => (int?)c.Period, ct);

    public async Task<StockDocument> PostAsync(StockPost post, string user, CancellationToken ct = default)
    {
        Validate(post);
        return await InTransaction(async () =>
        {
            settings = await SettingsAsync(ct);
            var items = post.Lines.SelectMany(l => l.SourceMaterialId is { } s ? new[] { Item(l), new StockItem(s, null) } : [Item(l)]);
            await LockAsync(items, ct);
            await EnsureOpenPeriod(post.Date, ct);
            await LoadMastersAsync(post, ct);

            var doc = new StockDocument
            {
                Type = post.Type, Date = post.Date, Reference = Clean(post.Reference), SupplierId = post.SupplierId, CustomerId = post.CustomerId,
                Notes = Clean(post.Notes), CreatedBy = user, CreatedAt = DateTimeOffset.UtcNow
            };
            db.StockDocuments.Add(doc);

            foreach (var (line, i) in post.Lines.Select((l, i) => (l, i)))
                await ApplyLineAsync(doc, line, $"lines[{i}]", ct);

            if (doc.Movements.Count == 0) throw StockException.Invalid("Nothing to post: all lines result in zero quantity", "lines");
            await CheckFreeStockAsync(doc, ct);
            await db.SaveChangesAsync(ct);
            return doc;
        }, ct);
    }

    public async Task<StockDocument> ReverseAsync(int documentId, string user, string? notes, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            settings = await SettingsAsync(ct);
            var original = await db.StockDocuments.Include(d => d.Movements).FirstOrDefaultAsync(d => d.Id == documentId, ct)
                ?? throw StockException.NotFound($"Document {documentId} not found");
            await LockAsync(original.Movements.Select(m => new StockItem(m.MaterialId, m.ProductId)), ct);
            await db.Entry(original).ReloadAsync(ct);
            if (original.Type == MovementType.Reversal) throw StockException.Conflict("A reversal cannot be reversed");
            if (original.Reversed) throw StockException.Conflict("Document is already reversed");
            await EnsureOpenPeriod(original.Date, ct);

            var doc = new StockDocument
            {
                Type = MovementType.Reversal, Date = original.Date, Reference = original.Reference, SupplierId = original.SupplierId,
                CustomerId = original.CustomerId, ReversalOfId = original.Id, Notes = Clean(notes), CreatedBy = user, CreatedAt = DateTimeOffset.UtcNow
            };
            original.Reversed = true;
            db.StockDocuments.Add(doc);
            foreach (var m in original.Movements.OrderByDescending(m => m.Id))
            {
                var item = new StockItem(m.MaterialId, m.ProductId);
                var balance = await BalanceAsync(item, m.LocationId, m.LotId, ct);
                Change(doc, m.Type, item, balance, -m.Quantity, m.UnitCost, m.IcmsRate, m.ReservationId);
                if (m.ReservationId is { } rid)
                {
                    var r = await db.StockReservations.FirstAsync(x => x.Id == rid, ct);
                    r.Consumed = Math.Max(0, r.Consumed + m.Quantity);
                    if (r.Status == ReservationStatus.Consumed && r.Consumed < r.Quantity) r.Status = ReservationStatus.Open;
                }
            }
            await db.SaveChangesAsync(ct);
            return doc;
        }, ct);
    }

    public async Task<StockReservation> ReserveAsync(StockItem item, int? locationId, decimal quantity, string reference, DateOnly? neededOn, string user, CancellationToken ct = default)
    {
        if (quantity <= 0) throw StockException.Invalid("Must be greater than zero", "quantity");
        if (string.IsNullOrWhiteSpace(reference)) throw StockException.Invalid("Required", "reference");
        return await InTransaction(async () =>
        {
            settings = await SettingsAsync(ct);
            await LockAsync([item], ct);
            await EnsureItemExists(item, ct);
            if (locationId is { } lid && !await db.StockLocations.AnyAsync(l => l.Id == lid, ct)) throw StockException.Invalid("Location not found", "locationId");
            var r = new StockReservation
            {
                MaterialId = item.MaterialId, ProductId = item.ProductId, LocationId = locationId, Quantity = quantity, Reference = reference.Trim(),
                NeededOn = neededOn, CreatedBy = user, CreatedAt = DateTimeOffset.UtcNow
            };
            db.StockReservations.Add(r);
            if (!settings.AllowNegativeStock)
            {
                var free = await FreeQuantityAsync(item, null, ct);
                if (free < quantity) throw StockException.Conflict($"Only {free:0.####} available to reserve");
            }
            await db.SaveChangesAsync(ct);
            return r;
        }, ct);
    }

    public async Task<StockReservation> ReleaseAsync(int reservationId, CancellationToken ct = default)
    {
        var r = await db.StockReservations.FirstOrDefaultAsync(x => x.Id == reservationId, ct) ?? throw StockException.NotFound("Reservation not found");
        if (r.Status != ReservationStatus.Open) throw StockException.Conflict("Reservation is not open");
        r.Status = ReservationStatus.Released;
        await db.SaveChangesAsync(ct);
        return r;
    }

    public async Task<decimal> FreeQuantityAsync(StockItem item, int? excludeReservationId, CancellationToken ct = default)
    {
        var onHand = await db.StockBalances
            .Where(b => b.MaterialId == item.MaterialId && b.ProductId == item.ProductId)
            .Where(b => b.Location!.Kind == StockLocationKind.Internal || b.Location!.Kind == StockLocationKind.Shipping)
            .Where(b => b.LotId == null || b.Lot!.Status == LotStatus.Released)
            .SumAsync(b => b.Quantity, ct);
        var reserved = await db.StockReservations
            .Where(r => r.MaterialId == item.MaterialId && r.ProductId == item.ProductId && r.Status == ReservationStatus.Open && r.Id != excludeReservationId)
            .SumAsync(r => r.Quantity - r.Consumed, ct);
        return onHand - reserved;
    }

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

    public async Task<List<AverageCost>> ComputeAveragesAsync(int period, CancellationToken ct = default)
    {
        settings ??= await SettingsAsync(ct);
        var start = StartOf(period);
        var end = start.AddMonths(1);
        var mats = await db.Materials.AsNoTracking().Select(m => new { m.Id, m.ThicknessMm }).ToListAsync(ct);
        var bucketOf = mats.ToDictionary(m => m.Id, m => m.ThicknessMm is > 0 ? (m.ThicknessMm, (int?)null) : ((decimal?)null, (int?)m.Id));

        var moves = await db.StockMovements.AsNoTracking()
            .Where(x => x.MaterialId != null && x.Date < end)
            .Select(x => new { MaterialId = x.MaterialId!.Value, x.Type, x.Date, x.Quantity, x.UnitCost, x.IcmsRate, ThirdParty = x.Location!.Kind == StockLocationKind.ThirdParty })
            .ToListAsync(ct);
        var previous = await db.AverageCosts.AsNoTracking().Where(a => a.Period < period)
            .GroupBy(a => new { a.ThicknessMm, a.MaterialId })
            .Select(g => g.OrderByDescending(a => a.Period).First())
            .ToListAsync(ct);
        var prevByBucket = previous.ToDictionary(a => (a.ThicknessMm, a.MaterialId));

        var buckets = moves.Select(x => bucketOf[x.MaterialId]).Concat(prevByBucket.Keys).Distinct();
        decimal Net(decimal cost, decimal icms) => settings.DeductIcmsFromAverage ? cost * (1 - icms / 100m) : cost;
        var rows = new List<AverageCost>();
        foreach (var bucket in buckets)
        {
            var mv = moves.Where(x => bucketOf[x.MaterialId] == bucket).ToList();
            var before = mv.Where(x => x.Date < start).ToList();
            var inPeriod = mv.Where(x => x.Date >= start).ToList();
            var opening = inPeriod.Where(x => x.Type == MovementType.OpeningBalance && !x.ThirdParty).ToList();
            var purchases = inPeriod.Where(x => x.Type == MovementType.Receipt && !x.ThirdParty).ToList();
            var services = inPeriod.Where(x => x.Type == MovementType.ThirdPartyReturn && !x.ThirdParty).ToList();

            var qtyBefore = before.Sum(x => x.Quantity);
            decimal openingAvg;
            if (prevByBucket.TryGetValue(bucket, out var prev))
            {
                var q = Math.Max(0, qtyBefore);
                var oq = opening.Sum(x => x.Quantity);
                openingAvg = q + oq > 0 ? (prev.Average * q + opening.Sum(x => x.Quantity * x.UnitCost)) / (q + oq) : prev.Average;
            }
            else
            {
                var priced = before.Where(x => ValuedInbound.Contains(x.Type) && !x.ThirdParty && x.UnitCost > 0).Concat(opening).ToList();
                var pq = priced.Sum(x => x.Quantity);
                openingAvg = pq > 0 ? priced.Sum(x => x.Quantity * Net(x.UnitCost, x.IcmsRate)) / pq : 0m;
            }
            var openingQty = Math.Max(0, qtyBefore + opening.Sum(x => x.Quantity));

            var purchaseQty = purchases.Sum(x => x.Quantity);
            var purchaseNet = purchases.Sum(x => x.Quantity * Net(x.UnitCost, x.IcmsRate));
            var purchaseGross = purchases.Sum(x => x.Quantity * x.UnitCost);
            var serviceQty = services.Sum(x => x.Quantity);
            var cutting = serviceQty > 0 ? serviceQty * settings.CuttingServicePerKg : 0m;
            var serviceNet = services.Sum(x => x.Quantity * Net(x.UnitCost, x.IcmsRate)) + cutting;
            var serviceGross = services.Sum(x => x.Quantity * x.UnitCost) + cutting;

            var inflow = purchaseQty + serviceQty;
            decimal monthAvg = 0, avg = openingAvg, avgGross = prev?.AverageGross ?? openingAvg;
            if (inflow > 0)
            {
                monthAvg = WithScrap((purchaseNet + serviceNet) / inflow);
                var monthGross = WithScrap((purchaseGross + serviceGross) / inflow);
                avg = Blend(openingAvg, openingQty, monthAvg, inflow);
                avgGross = Blend(prev?.AverageGross ?? openingAvg, openingQty, monthGross, inflow);
            }
            if (inflow == 0 && openingQty == 0 && prev is null && openingAvg == 0) continue;

            rows.Add(new AverageCost
            {
                Period = period, ThicknessMm = bucket.Item1, MaterialId = bucket.Item2,
                OpeningQuantity = openingQty, OpeningAverage = Math.Round(openingAvg, 6),
                PurchaseQuantity = purchaseQty, PurchaseValue = Math.Round(purchaseNet, 4),
                ServiceQuantity = serviceQty, ServiceValue = Math.Round(serviceNet, 4),
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

    private async Task ApplyLineAsync(StockDocument doc, StockLine line, string field, CancellationToken ct)
    {
        var item = Item(line);
        var type = doc.Type;
        var location = locations[line.LocationId];

        if (type == MovementType.InventoryCount)
        {
            var b = await BalanceAsync(item, line.LocationId, line.LotId, ct);
            var diff = line.Quantity - b.Quantity;
            if (diff != 0) Change(doc, type, item, b, diff, await CostAsync(item, line, doc.Date, ct), 0, null);
            return;
        }

        if (Inbound.Contains(type))
        {
            var lotId = await ResolveInboundLotAsync(doc, item, line, field, ct);
            var b = await BalanceAsync(item, line.LocationId, lotId, ct);
            Change(doc, type, item, b, line.Quantity, await CostAsync(item, line, doc.Date, ct), line.IcmsRate ?? 0, null);
            return;
        }

        if (Outbound.Contains(type))
        {
            StockReservation? reservation = null;
            if (line.ReservationId is { } rid)
            {
                reservation = await db.StockReservations.FirstOrDefaultAsync(r => r.Id == rid, ct) ?? throw StockException.Invalid("Reservation not found", $"{field}.reservationId");
                if (reservation.Status != ReservationStatus.Open) throw StockException.Conflict($"Reservation {rid} is not open");
                if (reservation.MaterialId != item.MaterialId || reservation.ProductId != item.ProductId) throw StockException.Invalid("Reservation is for another item", $"{field}.reservationId");
                reservation.Consumed += line.Quantity;
                if (reservation.Consumed >= reservation.Quantity) reservation.Status = ReservationStatus.Consumed;
            }
            var cost = await CostAsync(item, line, doc.Date, ct);
            foreach (var (lotId, qty) in await AllocateAsync(item, location, line.LotId, line.Quantity, type, field, ct))
                Change(doc, type, item, await BalanceAsync(item, line.LocationId, lotId, ct), -qty, cost, 0, reservation?.Id);
            return;
        }

        var from = line.FromLocationId is { } f ? locations[f] : null;
        if (type == MovementType.Transfer && from is null) throw StockException.Invalid("Required for transfers", $"{field}.fromLocationId");
        if (type == MovementType.ThirdPartySend)
        {
            if (from is null) throw StockException.Invalid("Required", $"{field}.fromLocationId");
            if (location.Kind != StockLocationKind.ThirdParty) throw StockException.Invalid("Destination must be a third-party location", $"{field}.locationId");
        }
        if (type == MovementType.ThirdPartyReturn)
        {
            if (location.Kind == StockLocationKind.ThirdParty) throw StockException.Invalid("Destination must be an own location", $"{field}.locationId");
            if (from is not null && from.Kind != StockLocationKind.ThirdParty) throw StockException.Invalid("Source must be a third-party location", $"{field}.fromLocationId");
            if (line.UnitCost is null) throw StockException.Invalid("Service price per unit is required", $"{field}.unitCost");
            if (from is not null)
            {
                var source = line.SourceMaterialId is { } sm ? new StockItem(sm, null) : item;
                var sourceCost = await CostAsync(source, line with { UnitCost = null }, doc.Date, ct);
                foreach (var (lotId, qty) in await AllocateAsync(source, from, line.SourceMaterialId is null ? line.LotId : null, line.SourceQuantity ?? line.Quantity, type, field, ct))
                    Change(doc, type, source, await BalanceAsync(source, from.Id, lotId, ct), -qty, sourceCost, 0, null);
            }
            var lot = await ResolveInboundLotAsync(doc, item, line, field, ct);
            Change(doc, type, item, await BalanceAsync(item, line.LocationId, lot, ct), line.Quantity, line.UnitCost.Value, line.IcmsRate ?? 0, null);
            return;
        }

        var transferCost = await CostAsync(item, line, doc.Date, ct);
        foreach (var (lotId, qty) in await AllocateAsync(item, from!, line.LotId, line.Quantity, type, field, ct))
        {
            Change(doc, type, item, await BalanceAsync(item, from!.Id, lotId, ct), -qty, transferCost, 0, null);
            Change(doc, type, item, await BalanceAsync(item, line.LocationId, lotId, ct), qty, transferCost, 0, null);
        }
    }

    private async Task<List<(int? LotId, decimal Qty)>> AllocateAsync(StockItem item, StockLocation location, int? lotId, decimal quantity, MovementType type, string field, CancellationToken ct)
    {
        var requireReleased = ConsumesFree.Contains(type);
        if (lotId is { } id)
        {
            var lot = await db.StockLots.FirstOrDefaultAsync(l => l.Id == id, ct) ?? throw StockException.Invalid("Lot not found", $"{field}.lotId");
            if (lot.MaterialId != item.MaterialId || lot.ProductId != item.ProductId) throw StockException.Invalid("Lot belongs to another item", $"{field}.lotId");
            if (requireReleased && lot.Status != LotStatus.Released) throw StockException.Conflict($"Lot {lot.Code} is {lot.Status}");
            return [(id, quantity)];
        }

        var candidates = await db.StockBalances
            .Where(b => b.MaterialId == item.MaterialId && b.ProductId == item.ProductId && b.LocationId == location.Id && b.Quantity > 0)
            .Where(b => !requireReleased || b.LotId == null || b.Lot!.Status == LotStatus.Released)
            .OrderBy(b => b.LotId == null ? 1 : 0).ThenBy(b => b.Lot!.ReceivedOn).ThenBy(b => b.LotId)
            .Select(b => new { b.LotId, b.Quantity })
            .ToListAsync(ct);
        var result = new List<(int?, decimal)>();
        var left = quantity;
        foreach (var c in candidates)
        {
            var pending = balances.TryGetValue(Key(item, location.Id, c.LotId), out var tracked) ? tracked.Quantity : c.Quantity;
            if (pending <= 0) continue;
            var take = Math.Min(pending, left);
            result.Add((c.LotId, take));
            left -= take;
            if (left == 0) return result;
        }
        if (!settings.AllowNegativeStock)
            throw StockException.Conflict($"Insufficient stock of {await DescribeAsync(item, ct)} at {location.Code}: missing {left:0.####}");
        result.Add((result.Count > 0 ? result[^1].Item1 : null, left));
        return result;
    }

    private void Change(StockDocument doc, MovementType type, StockItem item, StockBalance balance, decimal qty, decimal unitCost, decimal icms, int? reservationId)
    {
        balance.Quantity += qty;
        if (balance.Quantity < 0 && !settings.AllowNegativeStock)
            throw StockException.Conflict($"Balance would go negative ({balance.Quantity:0.####}) at location {locations.GetValueOrDefault(balance.LocationId)?.Code ?? balance.LocationId.ToString()}");
        doc.Movements.Add(new StockMovement
        {
            Type = type, Date = doc.Date, MaterialId = item.MaterialId, ProductId = item.ProductId, LocationId = balance.LocationId, LotId = balance.LotId,
            Quantity = qty, UnitCost = Math.Round(unitCost, 6), IcmsRate = icms, ReservationId = reservationId
        });
    }

    private async Task<StockBalance> BalanceAsync(StockItem item, int locationId, int? lotId, CancellationToken ct)
    {
        var key = Key(item, locationId, lotId);
        if (balances.TryGetValue(key, out var b)) return b;
        b = await db.StockBalances.FirstOrDefaultAsync(x => x.MaterialId == item.MaterialId && x.ProductId == item.ProductId && x.LocationId == locationId && x.LotId == lotId, ct);
        if (b is null)
        {
            b = new StockBalance { MaterialId = item.MaterialId, ProductId = item.ProductId, LocationId = locationId, LotId = lotId };
            db.StockBalances.Add(b);
        }
        return balances[key] = b;
    }

    private async Task<int?> ResolveInboundLotAsync(StockDocument doc, StockItem item, StockLine line, string field, CancellationToken ct)
    {
        if (line.LotId is { } id)
        {
            var lot = await db.StockLots.FirstOrDefaultAsync(l => l.Id == id, ct) ?? throw StockException.Invalid("Lot not found", $"{field}.lotId");
            if (lot.MaterialId != item.MaterialId || lot.ProductId != item.ProductId) throw StockException.Invalid("Lot belongs to another item", $"{field}.lotId");
            return id;
        }
        var code = Clean(line.LotCode);
        if (code is null && !(item.MaterialId is not null && NewLotTypes.Contains(doc.Type))) return null;
        if (code is not null)
        {
            var existing = await db.StockLots.FirstOrDefaultAsync(l => l.MaterialId == item.MaterialId && l.ProductId == item.ProductId && l.Code == code, ct);
            if (existing is not null) return existing.Id;
        }
        code ??= (await db.Database.SqlQuery<long>($"SELECT nextval('stock_lot_numbers') AS \"Value\"").SingleAsync(ct)).ToString("D6");
        var inspect = line.RequiresInspection ?? (item.MaterialId is { } m && materials[m].RequiresInspection && doc.Type is MovementType.Receipt or MovementType.ThirdPartyReturn);
        var newLot = new StockLot
        {
            MaterialId = item.MaterialId, ProductId = item.ProductId, Code = code, Status = inspect ? LotStatus.Quarantine : LotStatus.Released,
            SupplierId = doc.SupplierId, InvoiceNumber = doc.Reference, HeatNumber = Clean(line.HeatNumber), ReceivedOn = doc.Date
        };
        db.StockLots.Add(newLot);
        await db.SaveChangesAsync(ct);
        return newLot.Id;
    }

    private async Task<decimal> CostAsync(StockItem item, StockLine line, DateOnly date, CancellationToken ct)
    {
        if (line.UnitCost is { } c) return c;
        return item.MaterialId is { } m ? await CurrentAverageAsync(m, date, ct) : 0m;
    }

    private async Task CheckFreeStockAsync(StockDocument doc, CancellationToken ct)
    {
        if (settings.AllowNegativeStock || !ConsumesFree.Contains(doc.Type)) return;
        await db.SaveChangesAsync(ct);
        foreach (var g in doc.Movements.Where(m => m.Quantity < 0).GroupBy(m => new StockItem(m.MaterialId, m.ProductId)))
        {
            var reservations = g.Select(m => m.ReservationId).Distinct().ToList();
            if (reservations.All(r => r is not null)) continue;
            var free = await FreeQuantityAsync(g.Key, null, ct);
            if (free < 0) throw StockException.Conflict($"{await DescribeAsync(g.Key, ct)}: quantity is reserved for other orders (short by {-free:0.####})");
        }
    }

    private async Task LoadMastersAsync(StockPost post, CancellationToken ct)
    {
        var locIds = post.Lines.SelectMany(l => l.FromLocationId is { } f ? new[] { l.LocationId, f } : [l.LocationId]).Distinct().ToList();
        foreach (var l in await db.StockLocations.Where(l => locIds.Contains(l.Id)).ToListAsync(ct)) locations[l.Id] = l;
        var matIds = post.Lines.SelectMany(l => new[] { l.MaterialId, l.SourceMaterialId }).OfType<int>().Distinct().ToList();
        foreach (var m in await db.Materials.Where(m => matIds.Contains(m.Id)).ToListAsync(ct)) materials[m.Id] = m;
        var prodIds = post.Lines.Select(l => l.ProductId).OfType<int>().Distinct().ToList();
        var foundProducts = await db.Products.Where(p => prodIds.Contains(p.Id)).Select(p => p.Id).ToListAsync(ct);

        foreach (var (l, i) in post.Lines.Select((l, i) => (l, i)))
        {
            if (!locations.TryGetValue(l.LocationId, out var loc)) throw StockException.Invalid("Location not found", $"lines[{i}].locationId");
            if (!loc.Active) throw StockException.Invalid($"Location {loc.Code} is inactive", $"lines[{i}].locationId");
            if (l.FromLocationId is { } f && !locations.ContainsKey(f)) throw StockException.Invalid("Location not found", $"lines[{i}].fromLocationId");
            if (l.MaterialId is { } m && !materials.ContainsKey(m)) throw StockException.Invalid("Material not found", $"lines[{i}].materialId");
            if (l.SourceMaterialId is { } s && !materials.ContainsKey(s)) throw StockException.Invalid("Material not found", $"lines[{i}].sourceMaterialId");
            if (l.ProductId is { } p && !foundProducts.Contains(p)) throw StockException.Invalid("Product not found", $"lines[{i}].productId");
        }
        if (post.SupplierId is { } sid && !await db.Suppliers.AnyAsync(s => s.Id == sid, ct)) throw StockException.Invalid("Supplier not found", "supplierId");
        if (post.CustomerId is { } cid && !await db.Customers.AnyAsync(c => c.Id == cid, ct)) throw StockException.Invalid("Customer not found", "customerId");
    }

    private static void Validate(StockPost post)
    {
        if (post.Type == MovementType.Reversal) throw StockException.Invalid("Use the reverse endpoint", "type");
        if (post.Lines is null || post.Lines.Count == 0) throw StockException.Invalid("At least one line", "lines");
        foreach (var (l, i) in post.Lines.Select((l, i) => (l, i)))
        {
            var f = $"lines[{i}]";
            if ((l.MaterialId is null) == (l.ProductId is null)) throw StockException.Invalid("Give either materialId or productId", f);
            if (post.Type == MovementType.InventoryCount ? l.Quantity < 0 : l.Quantity <= 0) throw StockException.Invalid("Must be greater than zero", $"{f}.quantity");
            if (l.UnitCost < 0) throw StockException.Invalid("Cannot be negative", $"{f}.unitCost");
            if (l.IcmsRate is < 0 or > 100) throw StockException.Invalid("Between 0 and 100", $"{f}.icmsRate");
            if (l.FromLocationId is not null && !Paired.Contains(post.Type)) throw StockException.Invalid("Only for transfers and third-party movements", $"{f}.fromLocationId");
            if (l.FromLocationId == l.LocationId && l.FromLocationId is not null) throw StockException.Invalid("Source and destination are the same", $"{f}.fromLocationId");
            if (l.ReservationId is not null && !Outbound.Contains(post.Type)) throw StockException.Invalid("Only for issues and shipments", $"{f}.reservationId");
            if (l.SourceMaterialId is not null && post.Type != MovementType.ThirdPartyReturn) throw StockException.Invalid("Only for third-party returns", $"{f}.sourceMaterialId");
            if (l.ProductId is not null && l.SourceMaterialId is not null) throw StockException.Invalid("Products cannot have a source material", $"{f}.sourceMaterialId");
            if (post.Type == MovementType.Receipt && l.UnitCost is null) throw StockException.Invalid("Required for receipts", $"{f}.unitCost");
        }
    }

    private async Task EnsureOpenPeriod(DateOnly date, CancellationToken ct)
    {
        if (await LastClosedPeriodAsync(ct) is { } last && PeriodOf(date) <= last)
            throw StockException.Conflict($"Period {PeriodOf(date)} is closed (last closed: {last})");
    }

    private async Task EnsureItemExists(StockItem item, CancellationToken ct)
    {
        if ((item.MaterialId is null) == (item.ProductId is null)) throw StockException.Invalid("Give either materialId or productId");
        var ok = item.MaterialId is { } m ? await db.Materials.AnyAsync(x => x.Id == m, ct) : await db.Products.AnyAsync(x => x.Id == item.ProductId, ct);
        if (!ok) throw StockException.Invalid("Item not found");
    }

    private async Task LockAsync(IEnumerable<StockItem> items, CancellationToken ct)
    {
        await db.Database.ExecuteSqlRawAsync("SELECT pg_advisory_xact_lock_shared({0}, 0)", [GlobalLockClass], ct);
        foreach (var key in items.Select(i => i.LockKey).Distinct().Order())
            await db.Database.ExecuteSqlRawAsync("SELECT pg_advisory_xact_lock({0}, {1})", [ItemLockClass, (int)key], ct);
    }

    private async Task<T> InTransaction<T>(Func<Task<T>> work, CancellationToken ct)
    {
        if (db.Database.CurrentTransaction is not null) return await work();
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        try
        {
            var result = await work();
            await tx.CommitAsync(ct);
            return result;
        }
        catch
        {
            await tx.RollbackAsync(CancellationToken.None);
            db.ChangeTracker.Clear();
            throw;
        }
    }

    private async Task<string> DescribeAsync(StockItem item, CancellationToken ct) => item.MaterialId is { } m
        ? "material " + (materials.TryGetValue(m, out var mat) ? mat.Code : await db.Materials.Where(x => x.Id == m).Select(x => x.Code).FirstAsync(ct))
        : "product " + await db.Products.Where(x => x.Id == item.ProductId).Select(x => x.Code).FirstAsync(ct);

    private static StockItem Item(StockLine l) => new(l.MaterialId, l.ProductId);
    private static (int?, int?, int, int?) Key(StockItem i, int loc, int? lot) => (i.MaterialId, i.ProductId, loc, lot);
    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}
