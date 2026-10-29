using static Ebt.Core.Services.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Production;

public sealed partial class ProductionService
{
    public async Task<OrderProgress> ProgressAsync(int id, CancellationToken ct = default)
    {
        var order = await db.ProductionOrders.AsNoTracking().Include(o => o.Operations).FirstOrDefaultAsync(o => o.Id == id, ct) ?? throw ProductionException.NotFound("Order");
        return await ProgressAsync(order, ct);
    }

    public async Task<IReadOnlyList<MaterialLineState>> MaterialStatesAsync(int id, CancellationToken ct = default)
    {
        var order = await db.ProductionOrders.AsNoTracking().Include(o => o.Materials).FirstOrDefaultAsync(o => o.Id == id, ct) ?? throw ProductionException.NotFound("Order");
        return await MaterialStatesAsync(order, ct);
    }

    public async Task<Reconciliation> ReconcileAsync(int id, CancellationToken ct = default)
    {
        var order = await db.ProductionOrders.AsNoTracking().Include(o => o.Materials).Include(o => o.Operations).FirstOrDefaultAsync(o => o.Id == id, ct) ?? throw ProductionException.NotFound("Order");
        return await ReconcileAsync(order, ct);
    }

    private async Task<Reconciliation> ReconcileAsync(ProductionOrder order, CancellationToken ct)
    {
        var progress = await ProgressAsync(order, ct);
        var consumption = await ConsumptionAsync(order.Reference, ct);
        var service = await db.OutsideShipments.Where(s => s.Operation!.OrderId == order.Id).SumAsync(s => s.ServiceValue, ct);
        var scrapByOp = progress.Operations.ToDictionary(o => o.Sequence, o => o.Scrap);
        var materialIds = order.Materials.Select(m => m.MaterialId).OfType<int>().Distinct().ToList();
        var prices = await db.SupplierMaterials.AsNoTracking().Where(s => materialIds.Contains(s.MaterialId) && s.LastUnitPrice != null)
            .GroupBy(s => s.MaterialId).Select(g => new { g.Key, Price = g.OrderByDescending(s => s.LastPurchaseDate).Select(s => s.LastUnitPrice!.Value).First() })
            .ToDictionaryAsync(x => x.Key, x => x.Price, ct);
        var codes = await ItemCodesAsync(order.Materials, ct);
        var lines = new List<ReconciliationLine>();
        foreach (var g in order.Materials.GroupBy(m => new StockItem(m.MaterialId, m.ComponentProductId)))
        {
            var perUnit = g.Sum(m => m.QuantityPerUnit);
            var inScrap = Round(g.Sum(m => m.QuantityPerUnit * scrapByOp.Where(s => s.Key >= m.OperationSequence).Sum(s => s.Value)));
            var inFg = Round(perUnit * progress.Received);
            var issued = consumption.FirstOrDefault(c => new StockItem(c.MaterialId, c.ProductId) == g.Key)?.Quantity ?? 0m;
            var price = g.Key.MaterialId is { } mid ? prices.TryGetValue(mid, out var p) ? p : await stock.CurrentAverageAsync(mid, Ebt.Core.Services.Clock.Today(), ct) : 0m;
            var balance = issued - inScrap - inFg;
            lines.Add(new ReconciliationLine(g.Key.MaterialId, g.Key.ProductId, codes[g.Key].Code, g.First().Unit, perUnit, Round(g.Sum(m => m.RequiredQuantity)), issued, inScrap, inFg, balance, price, Math.Round(balance * price, 2)));
        }
        var materialCost = Math.Round(consumption.Sum(c => c.Value), 4);
        var unitCost = progress.Received > 0 ? Math.Round((materialCost + service) / progress.Received, 6) : (decimal?)null;
        return new Reconciliation(order.Id, order.Reference, order.Quantity, progress.Good, progress.Scrap, progress.Received, progress.WorkInProcess, materialCost, service, unitCost, lines);
    }

    private async Task<OrderProgress> ProgressAsync(ProductionOrder order, CancellationToken ct)
    {
        var tolerance = (await SettingsAsync(ct)).OverrunTolerancePercent;
        var reports = await db.ProductionReports.AsNoTracking().Where(r => r.OrderId == order.Id)
            .GroupBy(r => r.OperationId).Select(g => new { g.Key, Good = g.Sum(r => r.GoodQuantity), Scrap = g.Sum(r => r.ScrapQuantity) }).ToDictionaryAsync(x => x.Key, ct);
        var opIds = order.Operations.Select(o => o.Id).ToList();
        var transit = await db.OutsideShipments.AsNoTracking().Where(s => opIds.Contains(s.OperationId))
            .GroupBy(s => s.OperationId).Select(g => new { g.Key, Qty = g.Sum(s => s.Quantity - s.ReturnedQuantity - s.ScrapQuantity) }).ToDictionaryAsync(x => x.Key, x => x.Qty, ct);
        var received = await db.StockMovements.AsNoTracking()
            .Where(m => m.Document!.Reference == order.Reference && m.Type == MovementType.ProductionReceipt && m.ProductId == order.ProductId).SumAsync(m => m.Quantity, ct);
        var withTolerance = Round(order.Quantity * (1 + tolerance / 100m));

        var ops = new List<OperationProgress>();
        decimal? previousGood = null;
        foreach (var op in order.Operations.OrderBy(o => o.Sequence))
        {
            var r = reports.GetValueOrDefault(op.Id);
            var good = r?.Good ?? 0m;
            var scrap = r?.Scrap ?? 0m;
            var inTransit = transit.GetValueOrDefault(op.Id);
            var limit = (previousGood ?? withTolerance) + op.OverrunReleased;
            ops.Add(new OperationProgress(op.Id, op.Sequence, op.External, good, scrap, inTransit, op.OverrunReleased, limit, limit - good - scrap - inTransit));
            previousGood = good;
        }
        var lastGood = ops.Count > 0 ? ops[^1].Good : received;
        var receivable = ops.Count > 0 ? lastGood - received : withTolerance - received;
        var totalScrap = ops.Sum(o => o.Scrap);
        var wip = ops.Count > 0 ? ops[0].Good + ops[0].Scrap + ops[0].InTransit - totalScrap - received : 0m;
        return new OrderProgress(ops, lastGood, totalScrap, received, Math.Max(0, receivable), Math.Max(0, wip));
    }

    private async Task<List<MaterialLineState>> MaterialStatesAsync(ProductionOrder order, CancellationToken ct)
    {
        var consumption = (await ConsumptionAsync(order.Reference, ct)).ToDictionary(c => new StockItem(c.MaterialId, c.ProductId), c => c.Quantity);
        var reservationIds = order.Materials.Select(m => m.ReservationId).OfType<int>().ToList();
        var reservations = await db.StockReservations.AsNoTracking().Where(r => reservationIds.Contains(r.Id))
            .ToDictionaryAsync(r => r.Id, r => r.Status == ReservationStatus.Open ? r.Quantity - r.Consumed : 0m, ct);
        var codes = await ItemCodesAsync(order.Materials, ct);
        var result = new List<MaterialLineState>();
        foreach (var g in order.Materials.GroupBy(m => new StockItem(m.MaterialId, m.ComponentProductId)))
        {
            var issued = consumption.GetValueOrDefault(g.Key);
            var ordered = g.OrderBy(m => m.OperationSequence).ThenBy(m => m.Id).ToList();
            foreach (var (m, idx) in ordered.Select((m, idx) => (m, idx)))
            {
                var share = idx == ordered.Count - 1 ? issued : Math.Min(Math.Max(issued, 0), m.RequiredQuantity);
                issued -= share;
                var reserved = m.ReservationId is { } rid ? reservations.GetValueOrDefault(rid) : 0m;
                var (code, description) = codes[g.Key];
                result.Add(new MaterialLineState(m.Id, m.OperationSequence, m.MaterialId, m.ComponentProductId, code, description, m.Unit, m.QuantityPerUnit, m.RequiredQuantity, share,
                    Math.Max(0, m.RequiredQuantity - share), m.ReservationId, reserved));
            }
        }
        return result.OrderBy(r => r.OperationSequence).ThenBy(r => r.Id).ToList();
    }

    public async Task<List<ItemConsumption>> ConsumptionAsync(string reference, CancellationToken ct) =>
        await db.StockMovements.AsNoTracking()
            .Where(m => m.Document!.Reference == reference && ConsumptionTypes.Contains(m.Type))
            .GroupBy(m => new { m.MaterialId, m.ProductId })
            .Select(g => new ItemConsumption(g.Key.MaterialId, g.Key.ProductId, -g.Sum(m => m.Quantity), -g.Sum(m => m.Quantity * m.UnitCost)))
            .ToListAsync(ct);

    private async Task<Dictionary<StockItem, (string Code, string Description)>> ItemCodesAsync(IEnumerable<ProductionOrderMaterial> lines, CancellationToken ct)
    {
        var list = lines.ToList();
        var mids = list.Select(l => l.MaterialId).OfType<int>().Distinct().ToList();
        var pids = list.Select(l => l.ComponentProductId).OfType<int>().Distinct().ToList();
        var result = new Dictionary<StockItem, (string, string)>();
        foreach (var m in await db.Materials.AsNoTracking().Where(m => mids.Contains(m.Id)).Select(m => new { m.Id, m.Code, m.Description }).ToListAsync(ct))
            result[new StockItem(m.Id, null)] = (m.Code, m.Description);
        foreach (var p in await db.Products.AsNoTracking().Where(p => pids.Contains(p.Id)).Select(p => new { p.Id, p.Code, p.Name }).ToListAsync(ct))
            result[new StockItem(null, p.Id)] = (p.Code, p.Name);
        return result;
    }

    private async Task<Dictionary<int, decimal>> OnOrderAsync(List<int> materialIds, CancellationToken ct) =>
        await db.PurchaseOrderLines.AsNoTracking()
            .Where(l => l.MaterialId != null && materialIds.Contains(l.MaterialId.Value) && !l.Closed && l.ReceivedQuantity < l.Quantity
                        && (l.PurchaseOrder!.Status == PurchaseOrderStatus.Open || l.PurchaseOrder.Status == PurchaseOrderStatus.PartiallyReceived))
            .GroupBy(l => l.MaterialId!.Value)
            .Select(g => new { g.Key, Qty = g.Sum(l => l.Quantity - l.ReceivedQuantity) })
            .ToDictionaryAsync(x => x.Key, x => x.Qty, ct);
}
