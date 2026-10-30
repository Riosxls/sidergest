using static Ebt.Core.Services.Text;
using Ebt.Core.Data;
using Ebt.Core.Services;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Viability;
using Ebt.Core.Inventory;
using Ebt.Core.Production;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Sales;

public sealed partial class SalesService
{
    public async Task<SalesOrder> ConvertAsync(int quoteId, ConvertInput i, bool mayOverrideCredit, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var q = await LockQuoteAsync(quoteId, ct);
            if (q.Status != QuoteStatus.PurchaseOrder) throw SalesException.Conflict($"Quote is {q.Status}; register the customer's purchase order first");
            var addressId = i.AddressId ?? q.AddressId ?? await db.CustomerAddresses.Where(a => a.CustomerId == q.CustomerId).OrderBy(a => a.Id).Select(a => (int?)a.Id).FirstOrDefaultAsync(ct)
                ?? throw SalesException.Invalid("addressId", "Customer has no address; register the plant/delivery address first");
            var today = Today();
            var studies = await ViabilityRules.UsableForQuoteAsync(db, q.Id, ct);
            var lines = q.Lines.OrderBy(l => l.Sequence).Select(l => new SalesLineInput(l.ProductId, l.Quantity, l.UnitPrice, l.IpiPercent, l.IcmsPercent, l.LeadTimeDays,
                l.DeliveryDate ?? (l.LeadTimeDays is { } d ? WorkDays.Add(today, d) : null), l.Description, null, studies.TryGetValue(l.ProductId, out var fid) ? fid : null)).ToList();
            var order = await CreateOrderCoreAsync(new SalesOrderInput(q.CustomerId, addressId, lines, Clean(i.CustomerPo) ?? q.CustomerPo, q.PaymentTermId, q.Freight, q.Notes, null, q.CustomPaymentTerm), q, i.OverrideCredit && mayOverrideCredit, user, ct);
            var from = q.Status;
            q.Status = QuoteStatus.Converted;
            q.SalesOrderId = order.Id;
            Log(SalesRecordKind.Quote, q.Id, "converted", from, q.Status, order.Reference, user);
            await db.SaveChangesAsync(ct);
            return order;
        }, ct);
    }

    public Task<SalesOrder> CreateOrderAsync(SalesOrderInput i, bool overrideCredit, string? user, CancellationToken ct = default) =>
        InTransaction(() => CreateOrderCoreAsync(i, null, overrideCredit, user, ct), ct);

    private async Task<SalesOrder> CreateOrderCoreAsync(SalesOrderInput i, Quote? quote, bool overrideCredit, string? user, CancellationToken ct)
    {
        await ValidateHeaderAsync(i.CustomerId, i.AddressId, i.PaymentTermId, ct);
        var lines = await BuildLinesAsync(i.CustomerId, i.Lines, ct);
        await ViabilityRules.ValidateAsync(db, i.CustomerId, lines.Select(l => (l.ProductId, l.FeasibilityId)), null, ct);
        var credit = await CreditAsync(i.CustomerId, i.PaymentTermId, Totals(lines.Select(l => (l.Quantity, l.UnitPrice, l.IpiPercent, (decimal?)null))).Total, null, ct);
        if (credit.Exceeded && !overrideCredit)
            throw SalesException.Conflict($"Credit limit exceeded: limit {credit.Limit:0.00}, open {credit.Open:0.00}, this order {credit.ThisOrder:0.00}");
        var number = await NextAsync(EbtDbContext.SalesOrderNumbers, ct);
        var today = Today();
        var order = new SalesOrder
        {
            Number = number, Reference = OrderReference(number), QuoteId = quote?.Id, CustomerId = i.CustomerId, AddressId = i.AddressId, CustomerPo = Clean(i.CustomerPo),
            PaymentTermId = i.PaymentTermId, CustomPaymentTerm = Clean(i.CustomPaymentTerm), Freight = i.Freight, Notes = Clean(i.Notes), Company = CompanyOf(i.Company), BillTo = i.BillTo, Origin = i.Origin, Salesperson = Clean(i.Salesperson), Status = SalesOrderStatus.Created, CreatedBy = user, CreatedAt = DateTimeOffset.UtcNow,
            Lines = lines.Select((l, n) => new SalesOrderLine
            {
                Sequence = (n + 1) * 10, ProductId = l.ProductId, CustomerPartNumber = l.CustomerPartNumber, Description = l.Description, Quantity = l.Quantity, Unit = l.Unit,
                UnitPrice = l.UnitPrice, IpiPercent = l.IpiPercent, IcmsPercent = l.IcmsPercent, DueDate = l.DeliveryDate ?? (l.LeadTimeDays is { } d ? WorkDays.Add(today, d) : today.AddDays(30)),
                FeasibilityStudyId = l.FeasibilityId
            }.WithSpec(l.Spec)).ToList()
        };
        db.SalesOrders.Add(order);
        await db.SaveChangesAsync(ct);
        Log(SalesRecordKind.Order, order.Id, "created", null, order.Status, quote is null ? null : $"Da cotação {quote.Reference}", user);
        if (credit.Exceeded) Log(SalesRecordKind.Order, order.Id, "credit-override", null, null, $"Limite {credit.Limit:0.00} excedido (aberto {credit.Open:0.00})", user);
        await db.SaveChangesAsync(ct);
        return order;
    }

    public async Task<SalesOrder> UpdateOrderAsync(int id, SalesOrderInput i, string? user, CancellationToken ct = default)
    {
        await ValidateHeaderAsync(i.CustomerId, i.AddressId, i.PaymentTermId, ct);
        var lines = await BuildLinesAsync(i.CustomerId, i.Lines, ct);
        await ViabilityRules.ValidateAsync(db, i.CustomerId, lines.Select(l => (l.ProductId, l.FeasibilityId)), id, ct);
        return await InTransaction(async () =>
        {
            var o = await LockOrderAsync(id, ct);
            if (o.Status != SalesOrderStatus.Created) throw SalesException.Conflict("Only orders not yet released can be edited");
            if (o.CustomerId != i.CustomerId) throw SalesException.Invalid("customerId", "The customer cannot change");
            var today = Today();
            o.AddressId = i.AddressId;
            o.CustomerPo = Clean(i.CustomerPo);
            if (i.Company is not null) o.Company = CompanyOf(i.Company);
            o.PaymentTermId = i.PaymentTermId;
            o.CustomPaymentTerm = Clean(i.CustomPaymentTerm);
            o.Freight = i.Freight;
            o.Notes = Clean(i.Notes);
            o.BillTo = i.BillTo;
            o.Origin = i.Origin;
            o.Salesperson = Clean(i.Salesperson);
            db.SalesOrderLines.RemoveRange(o.Lines);
            await db.SaveChangesAsync(ct);
            o.Lines = lines.Select((l, n) => new SalesOrderLine
            {
                Sequence = (n + 1) * 10, ProductId = l.ProductId, CustomerPartNumber = l.CustomerPartNumber, Description = l.Description, Quantity = l.Quantity, Unit = l.Unit,
                UnitPrice = l.UnitPrice, IpiPercent = l.IpiPercent, IcmsPercent = l.IcmsPercent, DueDate = l.DeliveryDate ?? (l.LeadTimeDays is { } d ? WorkDays.Add(today, d) : today.AddDays(30)),
                FeasibilityStudyId = l.FeasibilityId
            }.WithSpec(l.Spec)).ToList();
            Log(SalesRecordKind.Order, o.Id, "edited", o.Status, o.Status, null, user);
            await db.SaveChangesAsync(ct);
            return o;
        }, ct);
    }

    public async Task<SalesOrder> ReleaseAsync(int id, bool useStock, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var o = await LockOrderAsync(id, ct);
            if (o.Status != SalesOrderStatus.Created) throw SalesException.Conflict($"Order is {o.Status}; only new orders can be released");
            var notes = new List<string>();
            foreach (var line in o.Lines.OrderBy(l => l.Sequence))
            {
                var free = useStock ? Math.Max(0, await stock.FreeQuantityAsync(new StockItem(null, line.ProductId), null, ct)) : 0m;
                var fromStock = Math.Min(free, line.Quantity);
                if (fromStock > 0)
                {
                    var r = await stock.ReserveAsync(new StockItem(null, line.ProductId), null, fromStock, o.Reference, line.DueDate, user ?? "system", ct);
                    line.ReservationId = r.Id;
                    line.FromStock = fromStock;
                }
                var toProduce = line.Quantity - fromStock;
                if (toProduce <= 0)
                {
                    notes.Add($"Item {line.Sequence}: {fromStock:0.####} do estoque");
                    continue;
                }
                var routing = line.FeasibilityStudyId is { } fid ? await db.FeasibilityStudies.AsNoTracking().FirstOrDefaultAsync(f => f.Id == fid, ct) : null;
                var of = await production.CreateOrderAsync(new OrderInput(line.ProductId, toProduce, line.DueDate, ProductionOrderKind.Standard, o.CustomerId,
                    Notes: $"{o.Reference} item {line.Sequence}{(o.CustomerPo is null ? "" : $" · pedido cliente {o.CustomerPo}")}{(routing is null ? "" : $" · {ViabilityRules.RoutingNote(routing)}")}"), user, ct);
                line.ProductionOrderId = of.Id;
                notes.Add($"Item {line.Sequence}: {of.Reference} ({toProduce:0.####}){(fromStock > 0 ? $" + {fromStock:0.####} do estoque" : "")}");
            }
            var from = o.Status;
            o.Status = SalesOrderStatus.Released;
            o.ReleasedAt = DateTimeOffset.UtcNow;
            o.ReleasedBy = user;
            Log(SalesRecordKind.Order, o.Id, "released", from, o.Status, string.Join("; ", notes), user);
            await db.SaveChangesAsync(ct);
            return o;
        }, ct);
    }

    public async Task<SalesOrder> CancelOrderAsync(int id, string? reason, string? user, CancellationToken ct = default)
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

    public async Task<CreditCheck> CreditAsync(int customerId, int? paymentTermId, decimal thisOrder, int? excludeOrderId, CancellationToken ct = default)
    {
        var limit = paymentTermId is { } pt ? await db.PaymentTerms.Where(p => p.Id == pt).Select(p => p.CreditLimit).FirstOrDefaultAsync(ct) : null;
        var lines = await db.SalesOrderLines.AsNoTracking()
            .Where(l => l.Order!.CustomerId == customerId && OpenOrder.Contains(l.Order.Status) && l.OrderId != excludeOrderId)
            .Select(l => new { l.Id, l.Quantity, l.UnitPrice, l.IpiPercent }).ToListAsync(ct);
        var ids = lines.Select(l => l.Id).ToList();
        var shipped = await ShippedAsync(ids, ct);
        var open = lines.Sum(l => Money(Math.Max(0, l.Quantity - shipped.GetValueOrDefault(l.Id)) * l.UnitPrice * (1 + l.IpiPercent / 100m)));
        return new CreditCheck(limit, open, thisOrder, limit is { } lim && open + thisOrder > lim);
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
