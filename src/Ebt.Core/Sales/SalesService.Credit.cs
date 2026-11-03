using static Ebt.Core.Services.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Inventory;
using Ebt.Core.Services;
using Ebt.Core.Production;
using Ebt.Core.Viability;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Sales;

/// <summary>Credit limit checks and shipped-quantity / progress lookups shared by order release, shipment and the order screens.</summary>
public sealed partial class SalesService
{
    /// <summary>
    /// Hard credit check at release and shipment. An order already authorised by a manager (credit-override event, written at creation or here) passes;
    /// otherwise an exceeded limit blocks unless a manager overrides, and the override is logged on the order.
    /// </summary>
    private async Task EnsureCreditAsync(SalesOrder o, string stage, bool overrideCredit, string? user, CancellationToken ct)
    {
        var credit = await CreditAsync(o.CustomerId, o.PaymentTermId, 0m, null, ct);
        if (!credit.Exceeded) return;
        if (await db.SalesEvents.AnyAsync(e => e.Kind == SalesRecordKind.Order && e.RecordId == o.Id && e.Action == "credit-override", ct)) return;
        if (!overrideCredit)
            throw SalesException.Conflict($"Credit limit exceeded: limit {credit.Limit:0.00}, open orders {credit.Open:0.00}, receivable {credit.Receivable:0.00}; a manager must authorise the {stage}");
        Log(SalesRecordKind.Order, o.Id, "credit-override", null, null, $"{stage}: limite {credit.Limit:0.00} excedido (pedidos em aberto {credit.Open:0.00}, a receber {credit.Receivable:0.00})", user);
    }

    public async Task<CreditCheck> CreditAsync(int customerId, int? paymentTermId, decimal thisOrder, int? excludeOrderId, CancellationToken ct = default)
    {
        var customerLimit = await db.Customers.AsNoTracking().Where(c => c.Id == customerId).Select(c => c.CreditLimit).FirstOrDefaultAsync(ct);
        var termLimit = paymentTermId is { } pt ? await db.PaymentTerms.Where(p => p.Id == pt).Select(p => p.CreditLimit).FirstOrDefaultAsync(ct) : null;
        var limit = customerLimit ?? termLimit;
        var lines = await db.SalesOrderLines.AsNoTracking()
            .Where(l => l.Order!.CustomerId == customerId && OpenOrder.Contains(l.Order.Status) && l.OrderId != excludeOrderId)
            .Select(l => new { l.Id, l.Quantity, l.UnitPrice, l.IpiPercent }).ToListAsync(ct);
        var ids = lines.Select(l => l.Id).ToList();
        var shipped = await ShippedAsync(ids, ct);
        var open = lines.Sum(l => Money(Math.Max(0, l.Quantity - shipped.GetValueOrDefault(l.Id)) * l.UnitPrice * (1 + l.IpiPercent / 100m)));
        var receivable = await new Ebt.Core.Receivables.ReceivablesService(db).OpenBalanceAsync(customerId, ct);
        return new CreditCheck(limit, open, thisOrder, limit is { } lim && open + receivable + thisOrder > lim, customerLimit is not null ? "customer" : termLimit is not null ? "term" : null, receivable);
    }

    public async Task<Dictionary<int, decimal>> ShippedAsync(IReadOnlyCollection<int> orderLineIds, CancellationToken ct = default) =>
        await db.DeliveryLines.Where(l => orderLineIds.Contains(l.OrderLineId) && (l.Delivery!.Status == DeliveryStatus.Shipped || l.Delivery.Status == DeliveryStatus.Delivered))
            .GroupBy(l => l.OrderLineId).Select(g => new { g.Key, Qty = g.Sum(x => x.Quantity) }).ToDictionaryAsync(x => x.Key, x => x.Qty, ct);

    public async Task<Dictionary<int, OrderProgressInfo>> ProgressAsync(IReadOnlyCollection<int> orderIds, CancellationToken ct = default)
    {
        var lines = await db.SalesOrderLines.AsNoTracking().Where(l => orderIds.Contains(l.OrderId))
            .Select(l => new { l.Id, l.OrderId, l.ProductId, l.Quantity, l.FromStock, l.DueDate, l.ReservationId, l.ProductionOrderId, Ref = l.ProductionOrder!.Reference, Status = (ProductionOrderStatus?)l.ProductionOrder.Status, Order = l.Order!.Status })
            .ToListAsync(ct);
        var lineIds = lines.Select(l => l.Id).ToList();
        var shipped = await ShippedAsync(lineIds, ct);
        var planned = await db.DeliveryLines.Where(l => lineIds.Contains(l.OrderLineId) && l.Delivery!.Status == DeliveryStatus.Planned)
            .GroupBy(l => l.OrderLineId).Select(g => new { g.Key, Qty = g.Sum(x => x.Quantity) }).ToDictionaryAsync(x => x.Key, x => x.Qty, ct);
        var refs = lines.Where(l => l.Ref != null).Select(l => l.Ref!).Distinct().ToList();
        var produced = await db.StockMovements.Where(m => m.Type == MovementType.ProductionReceipt && m.Document!.Reference != null && refs.Contains(m.Document.Reference))
            .GroupBy(m => m.Document!.Reference!).Select(g => new { g.Key, Qty = g.Sum(x => x.Quantity) }).ToDictionaryAsync(x => x.Key, x => x.Qty, ct);
        var reservationIds = lines.Where(l => l.ReservationId != null).Select(l => l.ReservationId!.Value).ToList();
        var reserved = await db.StockReservations.Where(r => reservationIds.Contains(r.Id) && r.Status == ReservationStatus.Open)
            .ToDictionaryAsync(r => r.Id, r => r.Quantity - r.Consumed, ct);
        var freeRaw = await stock.FreeQuantitiesAsync(lines.Select(l => l.ProductId).Distinct().ToList(), ct);
        var free = freeRaw.ToDictionary(kv => kv.Key, kv => Math.Max(0, kv.Value));
        var today = Today();

        var result = new Dictionary<int, OrderProgressInfo>();
        foreach (var g in lines.GroupBy(l => l.OrderId))
        {
            var rows = g.Select(l =>
            {
                var made = l.Ref is null ? 0m : Math.Max(0, produced.GetValueOrDefault(l.Ref));
                var sh = shipped.GetValueOrDefault(l.Id);
                var pl = planned.GetValueOrDefault(l.Id);
                var remaining = Math.Max(0, l.Quantity - sh);
                var available = (l.ReservationId is { } rid ? reserved.GetValueOrDefault(rid) : 0m) + free[l.ProductId];
                var ready = remaining <= 0 || (l.ProductionOrderId is null || ProductionDone.Contains(l.Status!.Value) || l.FromStock + made >= l.Quantity) && available > 0;
                return new OrderLineProgress(l.Id, l.Quantity, l.FromStock, made, sh, pl, remaining, available, l.Ref, l.Status, ready);
            }).ToList();
            var total = g.Sum(l => l.Quantity);
            var progress = total == 0 ? 0 : Math.Min(1m, rows.Sum(r => Math.Min(r.Quantity, Math.Max(r.Shipped, r.FromStock + r.Produced))) / total);
            var late = OpenOrder.Contains(g.First().Order) && g.Any(l => l.DueDate < today && rows.First(r => r.LineId == l.Id).Remaining > 0);
            result[g.Key] = new OrderProgressInfo(rows, Math.Round(progress, 4), rows.All(r => r.Ready), late);
        }
        return result;
    }
}
