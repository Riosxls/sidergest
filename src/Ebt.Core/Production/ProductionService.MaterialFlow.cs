using static Ebt.Core.Services.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Inventory;
using Ebt.Core.Services;
using Ebt.Core.Production;
using Ebt.Core.Viability;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Production;

/// <summary>Stock flow of a production order: material issue, return and finished-goods receipt.</summary>
public sealed partial class ProductionService
{
    public async Task<StockDocument> IssueAsync(int id, IssueInput i, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var order = await LockAsync(id, ct);
            if (!Running.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}; material can only be issued to released orders");
            var locationId = await LocationAsync(i.LocationId, (await SettingsAsync(ct)).IssueLocationId, DefaultIssueLocationCode, "locationId", ct);
            var states = await MaterialStatesAsync(order, ct);
            var requests = i.Lines is { Count: > 0 } ? i.Lines : states.Where(s => s.Remaining > 0).Select(s => new IssueLineInput(s.Id, s.Remaining)).ToList();
            if (requests.Count == 0) throw ProductionException.Conflict("Nothing left to issue");
            var lines = new List<StockLine>();
            var reservationUse = new Dictionary<int, decimal>();
            foreach (var (r, idx) in requests.Select((r, idx) => (r, idx)))
            {
                if (r.Quantity <= 0) throw ProductionException.Invalid($"lines[{idx}].quantity", "Must be greater than zero");
                var line = order.Materials.FirstOrDefault(m => m.Id == r.MaterialLineId) ?? throw ProductionException.Invalid($"lines[{idx}].materialLineId", "Not a material of this order");
                var state = states.First(s => s.Id == line.Id);
                var fromReservation = 0m;
                if (state.ReservationId is { } rid && state.Reserved > 0)
                {
                    fromReservation = Math.Min(r.Quantity, state.Reserved - reservationUse.GetValueOrDefault(rid));
                    reservationUse[rid] = reservationUse.GetValueOrDefault(rid) + fromReservation;
                }
                if (fromReservation > 0) lines.Add(new StockLine(line.MaterialId, line.ComponentProductId, locationId, fromReservation, LotId: r.LotId, ReservationId: state.ReservationId));
                if (r.Quantity - fromReservation > 0) lines.Add(new StockLine(line.MaterialId, line.ComponentProductId, locationId, r.Quantity - fromReservation, LotId: r.LotId));
            }
            var doc = await stock.PostAsync(new StockPost(MovementType.Issue, i.Date, lines, order.Reference, Notes: $"Requisição {order.Reference}", OrderId: order.Id), user ?? "system", ct);
            if (order.Status == ProductionOrderStatus.Released) order.Status = ProductionOrderStatus.InProduction;
            await db.SaveChangesAsync(ct);
            return doc;
        }, ct);
    }

    public async Task<StockDocument> ReturnMaterialAsync(int id, IssueInput i, string? user, CancellationToken ct = default)
    {
        if (i.Lines is not { Count: > 0 }) throw ProductionException.Invalid("lines", "At least one line");
        return await InTransaction(async () =>
        {
            var order = await LockAsync(id, ct);
            if (order.Status is ProductionOrderStatus.Closed or ProductionOrderStatus.Created) throw ProductionException.Conflict($"Order is {order.Status}");
            var locationId = await LocationAsync(i.LocationId, (await SettingsAsync(ct)).IssueLocationId, DefaultIssueLocationCode, "locationId", ct);
            var consumption = await ConsumptionAsync(order.Id, order.Reference, ct);
            var lines = new List<StockLine>();
            var left = consumption.ToDictionary(c => new StockItem(c.MaterialId, c.ProductId), c => c.Quantity);
            // Net quantity per lot still out on the order (issued minus returned), so a return without a lot goes back to the lot it came from.
            var byLot = (await db.StockMovements.AsNoTracking()
                    .Where(m => (m.Document!.OrderId == order.Id || (m.Document.OrderId == null && m.Document.Reference == order.Reference)) && ConsumptionTypes.Contains(m.Type) && m.LotId != null)
                    .GroupBy(m => new { m.MaterialId, m.ProductId, m.LotId })
                    .Select(g => new { g.Key.MaterialId, g.Key.ProductId, LotId = g.Key.LotId!.Value, Out = -g.Sum(m => m.Quantity) }).ToListAsync(ct))
                .Where(x => x.Out > 0).OrderBy(x => x.LotId)
                .GroupBy(x => new StockItem(x.MaterialId, x.ProductId)).ToDictionary(g => g.Key, g => g.Select(x => (x.LotId, x.Out)).ToList());
            foreach (var (r, idx) in i.Lines.Select((r, idx) => (r, idx)))
            {
                if (r.Quantity <= 0) throw ProductionException.Invalid($"lines[{idx}].quantity", "Must be greater than zero");
                var line = order.Materials.FirstOrDefault(m => m.Id == r.MaterialLineId) ?? throw ProductionException.Invalid($"lines[{idx}].materialLineId", "Not a material of this order");
                var item = new StockItem(line.MaterialId, line.ComponentProductId);
                var issued = left.GetValueOrDefault(item);
                if (r.Quantity > issued) throw ProductionException.Conflict($"Only {issued:0.####} {line.Unit} of this item is issued to {order.Reference}");
                left[item] = issued - r.Quantity;
                var c = consumption.First(x => new StockItem(x.MaterialId, x.ProductId) == item);
                var cost = c.Quantity > 0 ? Math.Round(c.Value / c.Quantity, 6) : 0;
                if (r.LotId is not null || !byLot.TryGetValue(item, out var lots))
                {
                    lines.Add(new StockLine(line.MaterialId, line.ComponentProductId, locationId, r.Quantity, LotId: r.LotId, UnitCost: cost));
                    continue;
                }
                // No lot given: back to the lot(s) it was issued from, oldest lot first; whatever is not traceable to a lot returns without one.
                var rest = r.Quantity;
                for (var k = 0; k < lots.Count && rest > 0; k++)
                {
                    var take = Math.Min(rest, lots[k].Out);
                    if (take <= 0) continue;
                    lines.Add(new StockLine(line.MaterialId, line.ComponentProductId, locationId, take, LotId: lots[k].LotId, UnitCost: cost));
                    lots[k] = (lots[k].LotId, lots[k].Out - take);
                    rest -= take;
                }
                if (rest > 0) lines.Add(new StockLine(line.MaterialId, line.ComponentProductId, locationId, rest, UnitCost: cost));
            }
            return await stock.PostAsync(new StockPost(MovementType.AdjustmentIn, i.Date, lines, order.Reference, Notes: $"Devolução {order.Reference}", OrderId: order.Id), user ?? "system", ct);
        }, ct);
    }

    public async Task<StockDocument> ReceiveAsync(int id, FinishedGoodsInput i, string? user, CancellationToken ct = default)
    {
        if (i.Quantity <= 0) throw ProductionException.Invalid("quantity", "Must be greater than zero");
        return await InTransaction(async () =>
        {
            var order = await LockAsync(id, ct);
            if (!Running.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
            var locationId = await LocationAsync(i.LocationId, (await SettingsAsync(ct)).ReceiptLocationId, DefaultReceiptLocationCode, "locationId", ct);
            var progress = await ProgressAsync(order, ct);
            if (i.Quantity > progress.Receivable)
                throw ProductionException.Conflict(order.Operations.Count > 0
                    ? $"Only {progress.Receivable:0.####} reported as good at the last operation and not yet in stock"
                    : $"Only {progress.Receivable:0.####} left to receive including tolerance");
            var consumption = await ConsumptionAsync(order.Id, order.Reference, ct);
            var service = await db.OutsideShipments.Where(s => s.Operation!.OrderId == id).SumAsync(s => s.ServiceValue, ct);
            var basis = Math.Max(order.Quantity, progress.Received + i.Quantity);
            var unitCost = Math.Round((consumption.Sum(c => c.Value) + service) / basis, 6);
            var doc = await stock.PostAsync(new StockPost(MovementType.ProductionReceipt, i.Date,
                [new StockLine(null, order.ProductId, locationId, i.Quantity, LotCode: Clean(i.LotCode) ?? order.Reference.Replace(" ", ""), UnitCost: Math.Max(0, unitCost))],
                order.Reference, CustomerId: order.CustomerId, Notes: $"Entrada PA {order.Reference}", OrderId: order.Id), user ?? "system", ct);
            if (order.Status == ProductionOrderStatus.Released) order.Status = ProductionOrderStatus.InProduction;
            await db.SaveChangesAsync(ct);
            return doc;
        }, ct);
    }
}
