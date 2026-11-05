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

/// <summary>Changes to an order after it was released: cancel preview, close balance, reschedule and cancel.</summary>
public sealed partial class SalesService
{
    /// <summary>What cancelling the order would touch, so the screen can show it before the user confirms.</summary>
    public async Task<CancelOrderPreview> CancelPreviewAsync(int id, CancellationToken ct = default)
    {
        var o = await db.SalesOrders.AsNoTracking().Include(x => x.Lines).FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw SalesException.NotFound("Order");
        var deliveries = await db.Deliveries.AsNoTracking().Where(d => d.OrderId == id).Select(d => new { d.Reference, d.Status }).ToListAsync(ct);
        var ofIds = o.Lines.Where(l => l.ProductionOrderId != null).Select(l => l.ProductionOrderId!.Value).ToList();
        var ofs = await db.ProductionOrders.AsNoTracking().Where(p => ofIds.Contains(p.Id)).ToListAsync(ct);
        var reservationIds = o.Lines.Where(l => l.ReservationId != null).Select(l => l.ReservationId!.Value).ToList();
        return new CancelOrderPreview(
            deliveries.Where(d => d.Status == DeliveryStatus.Planned).Select(d => d.Reference).ToList(),
            deliveries.Where(d => d.Status is DeliveryStatus.Shipped or DeliveryStatus.Delivered).Select(d => d.Reference).ToList(),
            ofs.Where(p => ProductionService.Open.Contains(p.Status)).Select(p => new CancelOrderOf(p.Reference, p.Status, p.Status != ProductionOrderStatus.Created)).ToList(),
            await db.StockReservations.CountAsync(r => reservationIds.Contains(r.Id) && r.Status == ReservationStatus.Open, ct));
    }

    /// <summary>The customer takes what already shipped and drops the rest: each line shrinks to its shipped quantity and the order closes as shipped/delivered.</summary>
    public async Task<SalesOrder> CloseBalanceAsync(int id, string? reason, string? user, CancellationToken ct = default)
    {
        if (Clean(reason) is null) throw SalesException.Invalid("reason", "Required");
        return await InTransaction(async () =>
        {
            var o = await LockOrderAsync(id, ct);
            if (o.Status is not (SalesOrderStatus.Released or SalesOrderStatus.PartiallyShipped)) throw SalesException.Conflict($"Order is {o.Status}");
            var shipped = await ShippedAsync(o.Lines.Select(l => l.Id).ToList(), ct);
            if (!shipped.Values.Any(v => v > 0)) throw SalesException.Conflict("Nothing shipped yet; cancel the order instead");
            // An item that never shipped cannot shrink to zero (quantity must stay above zero): it is removed from the order instead, which is only possible
            // while nothing else hangs on it (a live production order). Checked before any write so a refusal leaves everything untouched.
            var drop = new List<SalesOrderLine>();
            foreach (var line in o.Lines.OrderBy(l => l.Sequence))
            {
                if (shipped.GetValueOrDefault(line.Id) > 0) continue;
                if (line.ProductionOrderId is { } pid && await db.ProductionOrders.AsNoTracking().FirstAsync(p => p.Id == pid, ct) is { } of && of.Status != ProductionOrderStatus.Cancelled)
                    throw SalesException.Conflict($"Item {line.Sequence} nunca foi expedido e tem a ordem de produção {of.Reference}: cancele a OF ou expeda o item antes de encerrar o saldo");
                drop.Add(line);
            }
            var notes = new List<string>();
            foreach (var d in await db.Deliveries.Where(d => d.OrderId == id && d.Status == DeliveryStatus.Planned).ToListAsync(ct))
            {
                d.Status = DeliveryStatus.Cancelled;
                Log(SalesRecordKind.Delivery, d.Id, "cancelled", DeliveryStatus.Planned, d.Status, $"Saldo do pedido {o.Reference} encerrado", user);
            }
            foreach (var line in drop)
            {
                if (line.ReservationId is { } rid && await db.StockReservations.AnyAsync(r => r.Id == rid && r.Status == ReservationStatus.Open, ct)) await stock.ReleaseAsync(rid, ct);
                // Only planned/cancelled deliveries can reference an unshipped line; their rows go with it (the delivery history keeps the story).
                db.DeliveryLines.RemoveRange(await db.DeliveryLines.Where(dl => dl.OrderLineId == line.Id).ToListAsync(ct));
                db.SalesOrderLines.Remove(line);
                o.Lines.Remove(line);
                notes.Add($"item {line.Sequence}: {line.Quantity:0.####} → removido (não expedido)");
            }
            foreach (var line in o.Lines.OrderBy(l => l.Sequence))
            {
                var sent = shipped.GetValueOrDefault(line.Id);
                if (sent >= line.Quantity) continue;
                notes.Add($"item {line.Sequence}: {line.Quantity:0.####} → {sent:0.####}");
                line.Quantity = sent;
                if (line.ProductionOrderId is { } pid && await db.ProductionOrders.AsNoTracking().FirstAsync(p => p.Id == pid, ct) is { } of && ProductionService.Open.Contains(of.Status))
                    notes.Add($"{of.Reference} segue aberta ({of.Status})");
            }
            if (notes.Count == 0) throw SalesException.Conflict("Every item was already shipped in full");
            Log(SalesRecordKind.Order, o.Id, "balance-closed", o.Status, o.Status, string.Join("; ", [Clean(reason)!, .. notes]), user);
            await db.SaveChangesAsync(ct);
            await RefreshOrderStatusAsync(o, "Saldo encerrado", user, ct);
            return o;
        }, ct);
    }

    /// <summary>Changes after release: new due dates (also moved on the open OFs) and the customer's PO number. Quantities and prices stay as released.</summary>
    public async Task<SalesOrder> RescheduleAsync(int id, RescheduleInput i, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var o = await LockOrderAsync(id, ct);
            if (o.Status is not (SalesOrderStatus.Released or SalesOrderStatus.PartiallyShipped)) throw SalesException.Conflict($"Order is {o.Status}; only orders in production or partly shipped can be rescheduled");
            var notes = new List<string>();
            foreach (var (r, n) in (i.Lines ?? []).Select((r, n) => (r, n)))
            {
                var line = o.Lines.FirstOrDefault(l => l.Id == r.LineId) ?? throw SalesException.Invalid($"lines[{n}].lineId", "Not a line of this order");
                if (line.DueDate == r.DueDate) continue;
                if (r.DueDate < Today()) throw SalesException.Invalid($"lines[{n}].dueDate", "Cannot move a due date into the past");
                notes.Add($"item {line.Sequence}: {line.DueDate:dd/MM/yyyy} → {r.DueDate:dd/MM/yyyy}");
                line.DueDate = r.DueDate;
                if (line.ProductionOrderId is { } pid && await db.ProductionOrders.FirstAsync(p => p.Id == pid, ct) is { } of && ProductionService.Open.Contains(of.Status)) of.DueDate = r.DueDate;
            }
            if (notes.Count > 0 && Clean(i.Reason) is null) throw SalesException.Invalid("reason", "Required when a due date changes");
            if (i.CustomerPo is not null && Clean(i.CustomerPo) != o.CustomerPo)
            {
                notes.Add($"pedido do cliente: {o.CustomerPo ?? "—"} → {Clean(i.CustomerPo) ?? "—"}");
                o.CustomerPo = Clean(i.CustomerPo);
            }
            if (notes.Count == 0) throw SalesException.Conflict("Nothing changed");
            Log(SalesRecordKind.Order, o.Id, "rescheduled", o.Status, o.Status, string.Join("; ", Clean(i.Reason) is { } why ? [why, .. notes] : notes), user);
            await db.SaveChangesAsync(ct);
            return o;
        }, ct);
    }

    public async Task<SalesOrder> CancelOrderAsync(int id, string? reason, string? user, CancellationToken ct = default, bool cancelProduction = false)
    {
        if (Clean(reason) is null) throw SalesException.Invalid("reason", "Required");
        return await InTransaction(async () =>
        {
            var o = await LockOrderAsync(id, ct);
            if (!OpenOrder.Contains(o.Status)) throw SalesException.Conflict($"Order is {o.Status}");
            if (await db.Deliveries.AnyAsync(d => d.OrderId == id && (d.Status == DeliveryStatus.Shipped || d.Status == DeliveryStatus.Delivered), ct))
                throw SalesException.Conflict("Order has shipped deliveries; cancel or reverse them first");
            var notes = new List<string>();
            foreach (var d in await db.Deliveries.Where(d => d.OrderId == id && d.Status == DeliveryStatus.Planned).ToListAsync(ct))
            {
                d.Status = DeliveryStatus.Cancelled;
                Log(SalesRecordKind.Delivery, d.Id, "cancelled", DeliveryStatus.Planned, d.Status, $"Pedido {o.Reference} cancelado", user);
            }
            foreach (var line in o.Lines)
            {
                if (line.ReservationId is { } rid && await db.StockReservations.AnyAsync(r => r.Id == rid && r.Status == ReservationStatus.Open, ct))
                    await stock.ReleaseAsync(rid, ct);
                if (line.ProductionOrderId is { } pid)
                {
                    var of = await db.ProductionOrders.AsNoTracking().FirstAsync(p => p.Id == pid, ct);
                    if (of.Status == ProductionOrderStatus.Created)
                    {
                        await production.CancelAsync(pid, $"Pedido {o.Reference} cancelado: {Clean(reason)}", false, ct);
                        notes.Add($"{of.Reference} cancelada");
                    }
                    else if (cancelProduction && ProductionService.Open.Contains(of.Status))
                    {
                        await production.CancelAsync(pid, $"Pedido {o.Reference} cancelado: {Clean(reason)}", true, ct);
                        notes.Add($"{of.Reference} cancelada ({of.Status})");
                    }
                    else if (ProductionService.Open.Contains(of.Status)) notes.Add($"{of.Reference} segue em produção ({of.Status})");
                }
            }
            var from = o.Status;
            o.Status = SalesOrderStatus.Cancelled;
            o.StatusReason = Clean(reason);
            Log(SalesRecordKind.Order, o.Id, "cancelled", from, o.Status, string.Join("; ", [Clean(reason)!, .. notes]), user);
            await db.SaveChangesAsync(ct);
            return o;
        }, ct);
    }

}
