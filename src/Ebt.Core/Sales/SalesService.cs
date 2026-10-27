using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Production;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Sales;

public sealed class SalesService(EbtDbContext db, StockService stock, ProductionService production)
{
    public static readonly QuoteStatus[] OpenQuote = [QuoteStatus.Draft, QuoteStatus.PendingApproval, QuoteStatus.Approved, QuoteStatus.Sent, QuoteStatus.Accepted];
    public static readonly SalesOrderStatus[] OpenOrder = [SalesOrderStatus.Created, SalesOrderStatus.Released, SalesOrderStatus.PartiallyShipped];
    private static readonly QuoteStatus[] Revisable = [QuoteStatus.PendingApproval, QuoteStatus.Approved, QuoteStatus.Sent, QuoteStatus.Rejected, QuoteStatus.Expired];
    private static readonly ProductionOrderStatus[] ProductionDone = [ProductionOrderStatus.Finished, ProductionOrderStatus.Closed];

    public static string QuoteReference(int number, int revision) => revision == 0 ? $"PROP {number}" : $"PROP {number}/R{revision}";
    public static string OrderReference(int number) => $"PV {number}";
    public static string DeliveryReference(int number) => $"ENT {number}";

    public async Task<SalesSettings> SettingsAsync(CancellationToken ct = default) =>
        await db.SalesSettings.FirstOrDefaultAsync(ct) ?? throw new InvalidOperationException("sales_settings row missing");

    public async Task<PriceListEntry?> PriceAsync(int productId, int? customerId, DateOnly date, CancellationToken ct = default) =>
        await db.PriceList.AsNoTracking()
            .Where(p => p.ProductId == productId && (p.CustomerId == customerId || p.CustomerId == null) && p.ValidFrom <= date && (p.ValidTo == null || p.ValidTo >= date))
            .OrderBy(p => p.CustomerId == null).ThenByDescending(p => p.ValidFrom)
            .FirstOrDefaultAsync(ct);

    public static QuoteTotals Totals(IEnumerable<(decimal Qty, decimal Price, decimal Ipi, decimal? List)> lines)
    {
        var list = lines.ToList();
        var products = list.Sum(l => Money(l.Qty * l.Price));
        var ipi = list.Sum(l => Money(l.Qty * l.Price * l.Ipi / 100m));
        var discount = list.Where(l => l.List is > 0).Select(l => Math.Round((1 - l.Price / l.List!.Value) * 100m, 2)).DefaultIfEmpty(0).Max();
        return new QuoteTotals(products, ipi, products + ipi, discount);
    }

    public static QuoteTotals Totals(Quote q) => Totals(q.Lines.Select(l => (l.Quantity, l.UnitPrice, l.IpiPercent, l.ListPrice)));

    public async Task<Quote> CreateQuoteAsync(QuoteInput i, string? user, CancellationToken ct = default)
    {
        var settings = await SettingsAsync(ct);
        await ValidateHeaderAsync(i.CustomerId, i.AddressId, i.PaymentTermId, ct);
        if (i.ValidityDays is <= 0) throw SalesException.Invalid("validityDays", "Must be greater than zero");
        var lines = await BuildLinesAsync(i.CustomerId, i.Lines, ct);
        return await InTransaction(async () =>
        {
            var number = await NextAsync(EbtDbContext.SalesQuoteNumbers, ct);
            var q = new Quote
            {
                Number = number, Reference = QuoteReference(number, 0), CustomerId = i.CustomerId, Status = QuoteStatus.Draft, CreatedBy = user, CreatedAt = DateTimeOffset.UtcNow,
                ValidityDays = i.ValidityDays ?? settings.DefaultValidityDays, Conditions = Clean(i.Conditions) ?? settings.DefaultConditions
            };
            ApplyHeader(q, i);
            q.Lines = lines.Select((l, n) => ToQuoteLine(l, n)).ToList();
            q.NeedsApproval = Totals(q).MaxDiscountPercent > settings.MaxDiscountPercent;
            db.Quotes.Add(q);
            await db.SaveChangesAsync(ct);
            Log(SalesRecordKind.Quote, q.Id, "created", null, q.Status, null, user);
            await db.SaveChangesAsync(ct);
            return q;
        }, ct);
    }

    public async Task<Quote> UpdateQuoteAsync(int id, QuoteInput i, string? user, CancellationToken ct = default)
    {
        var settings = await SettingsAsync(ct);
        await ValidateHeaderAsync(i.CustomerId, i.AddressId, i.PaymentTermId, ct);
        if (i.ValidityDays is <= 0) throw SalesException.Invalid("validityDays", "Must be greater than zero");
        var lines = await BuildLinesAsync(i.CustomerId, i.Lines, ct);
        return await InTransaction(async () =>
        {
            var q = await LockQuoteAsync(id, ct);
            if (q.Status != QuoteStatus.Draft) throw SalesException.Conflict("Only draft quotes can be edited; revise it first");
            q.CustomerId = i.CustomerId;
            q.ValidityDays = i.ValidityDays ?? q.ValidityDays;
            q.Conditions = Clean(i.Conditions);
            ApplyHeader(q, i);
            db.QuoteLines.RemoveRange(q.Lines);
            await db.SaveChangesAsync(ct);
            q.Lines = lines.Select((l, n) => ToQuoteLine(l, n)).ToList();
            q.NeedsApproval = Totals(q).MaxDiscountPercent > settings.MaxDiscountPercent;
            Log(SalesRecordKind.Quote, q.Id, "edited", q.Status, q.Status, null, user);
            await db.SaveChangesAsync(ct);
            return q;
        }, ct);
    }

    public async Task DeleteQuoteAsync(int id, CancellationToken ct = default)
    {
        await InTransaction(async () =>
        {
            var q = await LockQuoteAsync(id, ct);
            if (q.Status != QuoteStatus.Draft || q.Revision > 0) throw SalesException.Conflict("Only new drafts can be deleted; cancel it instead");
            db.Quotes.Remove(q);
            db.SalesEvents.RemoveRange(db.SalesEvents.Where(e => e.Kind == SalesRecordKind.Quote && e.RecordId == id));
            await db.SaveChangesAsync(ct);
            return 0;
        }, ct);
    }

    public Task<Quote> SendAsync(int id, string? sentTo, string? note, string? user, CancellationToken ct = default) => QuoteStep(id, "sent", note, user, ct, async q =>
    {
        if (q.Status is not (QuoteStatus.Draft or QuoteStatus.Approved)) throw SalesException.Conflict($"Quote is {q.Status}");
        if (q.Lines.Count == 0) throw SalesException.Conflict("Quote has no items");
        var settings = await SettingsAsync(ct);
        var totals = Totals(q);
        if (totals.Products < settings.MinimumOrderValue) throw SalesException.Conflict($"Below the minimum order value of {settings.MinimumOrderValue:0.00}");
        q.NeedsApproval = totals.MaxDiscountPercent > settings.MaxDiscountPercent;
        if (q.Status == QuoteStatus.Draft && q.NeedsApproval)
        {
            q.Status = QuoteStatus.PendingApproval;
            return "submitted";
        }
        var to = Clean(sentTo) ?? q.ContactEmail;
        if (to is null) throw SalesException.Invalid("sentTo", "Give the customer contact or e-mail");
        q.Status = QuoteStatus.Sent;
        q.SentAt = DateTimeOffset.UtcNow;
        q.SentTo = to;
        q.ValidUntil = Today().AddDays(q.ValidityDays);
        return "sent";
    });

    public Task<Quote> ApproveAsync(int id, string? note, string? user, CancellationToken ct = default) => QuoteStep(id, "approved", note, user, ct, q =>
    {
        if (q.Status != QuoteStatus.PendingApproval) throw SalesException.Conflict($"Quote is {q.Status}");
        q.Status = QuoteStatus.Approved;
        q.ApprovedBy = user;
        q.ApprovedAt = DateTimeOffset.UtcNow;
        return Task.FromResult<string?>(null);
    });

    public Task<Quote> RejectApprovalAsync(int id, string? note, string? user, CancellationToken ct = default) => QuoteStep(id, "approval-rejected", note, user, ct, q =>
    {
        if (q.Status != QuoteStatus.PendingApproval) throw SalesException.Conflict($"Quote is {q.Status}");
        if (Clean(note) is null) throw SalesException.Invalid("note", "Required");
        q.Status = QuoteStatus.Draft;
        return Task.FromResult<string?>(null);
    });

    public Task<Quote> AcceptAsync(int id, string? customerPo, string? note, string? user, CancellationToken ct = default) => QuoteStep(id, "accepted", note, user, ct, q =>
    {
        if (q.Status != QuoteStatus.Sent) throw SalesException.Conflict($"Quote is {q.Status}");
        if (q.ValidUntil < Today()) throw SalesException.Conflict($"Quote expired on {q.ValidUntil:dd/MM/yyyy}; revise it");
        q.Status = QuoteStatus.Accepted;
        q.CustomerPo = Clean(customerPo);
        q.DecidedAt = DateTimeOffset.UtcNow;
        q.DecisionBy = user;
        q.DecisionNote = Clean(note);
        return Task.FromResult<string?>(null);
    });

    public Task<Quote> DeclineAsync(int id, string? reason, string? user, CancellationToken ct = default) => QuoteStep(id, "declined", reason, user, ct, q =>
    {
        if (q.Status != QuoteStatus.Sent) throw SalesException.Conflict($"Quote is {q.Status}");
        if (Clean(reason) is null) throw SalesException.Invalid("reason", "Required");
        q.Status = QuoteStatus.Rejected;
        q.DecidedAt = DateTimeOffset.UtcNow;
        q.DecisionBy = user;
        q.DecisionNote = Clean(reason);
        return Task.FromResult<string?>(null);
    });

    public Task<Quote> ReviseAsync(int id, string? note, string? user, CancellationToken ct = default) => QuoteStep(id, "revised", note, user, ct, q =>
    {
        if (!Revisable.Contains(q.Status)) throw SalesException.Conflict($"Quote is {q.Status}");
        q.Revision++;
        q.Reference = QuoteReference(q.Number, q.Revision);
        q.Status = QuoteStatus.Draft;
        q.ApprovedAt = null;
        q.ApprovedBy = null;
        q.SentAt = null;
        q.SentTo = null;
        q.ValidUntil = null;
        q.DecidedAt = null;
        q.DecisionBy = null;
        q.DecisionNote = null;
        return Task.FromResult<string?>(null);
    });

    public Task<Quote> CancelQuoteAsync(int id, string? reason, string? user, CancellationToken ct = default) => QuoteStep(id, "cancelled", reason, user, ct, q =>
    {
        if (!OpenQuote.Contains(q.Status) && q.Status is not (QuoteStatus.Rejected or QuoteStatus.Expired)) throw SalesException.Conflict($"Quote is {q.Status}");
        if (Clean(reason) is null) throw SalesException.Invalid("reason", "Required");
        q.Status = QuoteStatus.Cancelled;
        q.DecisionNote = Clean(reason);
        return Task.FromResult<string?>(null);
    });

    public async Task<int> ExpireOverdueAsync(CancellationToken ct = default)
    {
        var today = Today();
        var overdue = await db.Quotes.Where(q => q.Status == QuoteStatus.Sent && q.ValidUntil < today).ToListAsync(ct);
        foreach (var q in overdue)
        {
            q.Status = QuoteStatus.Expired;
            Log(SalesRecordKind.Quote, q.Id, "expired", QuoteStatus.Sent, QuoteStatus.Expired, $"Validade {q.ValidUntil:dd/MM/yyyy}", "system");
        }
        if (overdue.Count > 0) await db.SaveChangesAsync(ct);
        return overdue.Count;
    }

    public async Task<SalesOrder> ConvertAsync(int quoteId, ConvertInput i, bool mayOverrideCredit, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var q = await LockQuoteAsync(quoteId, ct);
            if (q.Status != QuoteStatus.Accepted) throw SalesException.Conflict($"Quote is {q.Status}; the customer must accept it first");
            var addressId = i.AddressId ?? q.AddressId ?? await db.CustomerAddresses.Where(a => a.CustomerId == q.CustomerId).OrderBy(a => a.Id).Select(a => (int?)a.Id).FirstOrDefaultAsync(ct)
                ?? throw SalesException.Invalid("addressId", "Customer has no address; register the plant/delivery address first");
            var today = Today();
            var lines = q.Lines.OrderBy(l => l.Sequence).Select(l => new SalesLineInput(l.ProductId, l.Quantity, l.UnitPrice, l.IpiPercent, l.IcmsPercent, l.LeadTimeDays,
                l.DeliveryDate ?? (l.LeadTimeDays is { } d ? today.AddDays(d) : null), l.Description)).ToList();
            var order = await CreateOrderCoreAsync(new SalesOrderInput(q.CustomerId, addressId, lines, Clean(i.CustomerPo) ?? q.CustomerPo, q.PaymentTermId, q.Freight, q.Notes), q, i.OverrideCredit && mayOverrideCredit, user, ct);
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
        var credit = await CreditAsync(i.CustomerId, i.PaymentTermId, Totals(lines.Select(l => (l.Quantity, l.UnitPrice, l.IpiPercent, (decimal?)null))).Total, null, ct);
        if (credit.Exceeded && !overrideCredit)
            throw SalesException.Conflict($"Credit limit exceeded: limit {credit.Limit:0.00}, open {credit.Open:0.00}, this order {credit.ThisOrder:0.00}");
        var number = await NextAsync(EbtDbContext.SalesOrderNumbers, ct);
        var today = Today();
        var order = new SalesOrder
        {
            Number = number, Reference = OrderReference(number), QuoteId = quote?.Id, CustomerId = i.CustomerId, AddressId = i.AddressId, CustomerPo = Clean(i.CustomerPo),
            PaymentTermId = i.PaymentTermId, Freight = i.Freight, Notes = Clean(i.Notes), Status = SalesOrderStatus.Created, CreatedBy = user, CreatedAt = DateTimeOffset.UtcNow,
            Lines = lines.Select((l, n) => new SalesOrderLine
            {
                Sequence = (n + 1) * 10, ProductId = l.ProductId, CustomerPartNumber = l.CustomerPartNumber, Description = l.Description, Quantity = l.Quantity, Unit = l.Unit,
                UnitPrice = l.UnitPrice, IpiPercent = l.IpiPercent, IcmsPercent = l.IcmsPercent, DueDate = l.DeliveryDate ?? today.AddDays(l.LeadTimeDays ?? 30)
            }).ToList()
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
        return await InTransaction(async () =>
        {
            var o = await LockOrderAsync(id, ct);
            if (o.Status != SalesOrderStatus.Created) throw SalesException.Conflict("Only orders not yet released can be edited");
            if (o.CustomerId != i.CustomerId) throw SalesException.Invalid("customerId", "The customer cannot change");
            var today = Today();
            o.AddressId = i.AddressId;
            o.CustomerPo = Clean(i.CustomerPo);
            o.PaymentTermId = i.PaymentTermId;
            o.Freight = i.Freight;
            o.Notes = Clean(i.Notes);
            db.SalesOrderLines.RemoveRange(o.Lines);
            await db.SaveChangesAsync(ct);
            o.Lines = lines.Select((l, n) => new SalesOrderLine
            {
                Sequence = (n + 1) * 10, ProductId = l.ProductId, CustomerPartNumber = l.CustomerPartNumber, Description = l.Description, Quantity = l.Quantity, Unit = l.Unit,
                UnitPrice = l.UnitPrice, IpiPercent = l.IpiPercent, IcmsPercent = l.IcmsPercent, DueDate = l.DeliveryDate ?? today.AddDays(l.LeadTimeDays ?? 30)
            }).ToList();
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
                var of = await production.CreateOrderAsync(new OrderInput(line.ProductId, toProduce, line.DueDate, ProductionOrderKind.Standard, o.CustomerId,
                    Notes: $"{o.Reference} item {line.Sequence}{(o.CustomerPo is null ? "" : $" · pedido cliente {o.CustomerPo}")}"), user, ct);
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
        var free = new Dictionary<int, decimal>();
        foreach (var p in lines.Select(l => l.ProductId).Distinct()) free[p] = Math.Max(0, await stock.FreeQuantityAsync(new StockItem(null, p), null, ct));
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

    public async Task<Delivery> CreateDeliveryAsync(int orderId, DeliveryInput i, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var o = await LockOrderAsync(orderId, ct);
            if (o.Status is not (SalesOrderStatus.Released or SalesOrderStatus.PartiallyShipped)) throw SalesException.Conflict($"Order is {o.Status}; release it to production first");
            var addressId = i.AddressId ?? o.AddressId;
            if (!await db.CustomerAddresses.AnyAsync(a => a.Id == addressId && a.CustomerId == o.CustomerId, ct)) throw SalesException.Invalid("addressId", "Address does not belong to the customer");
            var progress = (await ProgressAsync([o.Id], ct))[o.Id];
            var requested = i.Lines is { Count: > 0 }
                ? i.Lines
                : progress.Lines.Where(p => p.Remaining - p.Planned > 0).Select(p => new DeliveryLineInput(p.LineId, p.Remaining - p.Planned)).ToList();
            if (requested.Count == 0) throw SalesException.Conflict("Nothing left to deliver");
            var products = await db.Products.AsNoTracking().Where(p => o.Lines.Select(l => l.ProductId).Contains(p.Id)).ToDictionaryAsync(p => p.Id, ct);
            var number = await NextAsync(EbtDbContext.DeliveryNumbers, ct);
            var d = new Delivery
            {
                Number = number, Reference = DeliveryReference(number), OrderId = o.Id, AddressId = addressId, PlannedDate = i.PlannedDate, Status = DeliveryStatus.Planned,
                Carrier = Clean(i.Carrier), Notes = Clean(i.Notes), CreatedBy = user, CreatedAt = DateTimeOffset.UtcNow
            };
            decimal? weight = 0m;
            foreach (var (r, n) in requested.Select((r, n) => (r, n)))
            {
                var line = o.Lines.FirstOrDefault(l => l.Id == r.OrderLineId) ?? throw SalesException.Invalid($"lines[{n}].orderLineId", "Not a line of this order");
                var p = progress.Lines.First(x => x.LineId == line.Id);
                if (r.Quantity <= 0) throw SalesException.Invalid($"lines[{n}].quantity", "Must be greater than zero");
                if (r.Quantity > p.Remaining - p.Planned) throw SalesException.Invalid($"lines[{n}].quantity", $"Only {p.Remaining - p.Planned:0.####} left to deliver");
                if (d.Lines.Any(x => x.OrderLineId == line.Id)) throw SalesException.Invalid($"lines[{n}].orderLineId", "Repeated line");
                var product = products[line.ProductId];
                var packages = product.PiecesPerPackage is > 0 ? (int)Math.Ceiling(r.Quantity / product.PiecesPerPackage.Value) : 0;
                d.Lines.Add(new DeliveryLine { OrderLineId = line.Id, Quantity = r.Quantity, Packages = packages });
                weight = product.NetWeightKg is { } w && weight is { } acc ? acc + w * r.Quantity : null;
            }
            d.Packages = d.Lines.Sum(l => l.Packages);
            d.GrossWeightKg = weight is { } kg ? Math.Round(kg, 3) : null;
            db.Deliveries.Add(d);
            await db.SaveChangesAsync(ct);
            Log(SalesRecordKind.Delivery, d.Id, "created", null, d.Status, $"Pedido {o.Reference}", user);
            Log(SalesRecordKind.Order, o.Id, "delivery-planned", o.Status, o.Status, $"{d.Reference} para {d.PlannedDate:dd/MM/yyyy}", user);
            await db.SaveChangesAsync(ct);
            return d;
        }, ct);
    }

    public async Task<Delivery> ShipAsync(int id, ShipInput i, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var d = await LockDeliveryAsync(id, ct);
            if (d.Status != DeliveryStatus.Planned) throw SalesException.Conflict($"Delivery is {d.Status}");
            var o = await LockOrderAsync(d.OrderId, ct);
            if (o.Status is not (SalesOrderStatus.Released or SalesOrderStatus.PartiallyShipped)) throw SalesException.Conflict($"Order is {o.Status}");
            var location = await ShippingLocationAsync(ct);
            var stockLines = new List<StockLine>();
            foreach (var dl in d.Lines)
            {
                var line = o.Lines.First(l => l.Id == dl.OrderLineId);
                var rest = dl.Quantity;
                if (line.ReservationId is { } rid && await db.StockReservations.AsNoTracking().FirstOrDefaultAsync(r => r.Id == rid && r.Status == ReservationStatus.Open, ct) is { } res)
                {
                    var take = Math.Min(rest, res.Quantity - res.Consumed);
                    if (take > 0) stockLines.Add(new StockLine(null, line.ProductId, location, take, ReservationId: rid));
                    rest -= take;
                }
                if (rest > 0) stockLines.Add(new StockLine(null, line.ProductId, location, rest));
            }
            var doc = await stock.PostAsync(new StockPost(MovementType.Shipment, i.Date, stockLines, d.Reference, CustomerId: o.CustomerId, Notes: $"{o.Reference}{(Clean(i.InvoiceNumber) is { } nf ? $" · NF {nf}" : "")}"), user ?? "system", ct);
            d.StockDocumentId = doc.Id;
            d.Status = DeliveryStatus.Shipped;
            d.ShippedAt = DateTimeOffset.UtcNow;
            d.ShippedBy = user;
            d.InvoiceNumber = Clean(i.InvoiceNumber) ?? d.InvoiceNumber;
            d.Carrier = Clean(i.Carrier) ?? d.Carrier;
            d.VehiclePlate = Clean(i.VehiclePlate)?.ToUpper();
            d.GrossWeightKg = i.GrossWeightKg ?? d.GrossWeightKg;
            Log(SalesRecordKind.Delivery, d.Id, "shipped", DeliveryStatus.Planned, d.Status, d.InvoiceNumber is null ? null : $"NF {d.InvoiceNumber}", user);
            await db.SaveChangesAsync(ct);
            await RefreshOrderStatusAsync(o, $"{d.Reference} expedida", user, ct);
            return d;
        }, ct);
    }

    public async Task<Delivery> ConfirmAsync(int id, DateOnly? date, string? receivedBy, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var d = await LockDeliveryAsync(id, ct);
            if (d.Status != DeliveryStatus.Shipped) throw SalesException.Conflict($"Delivery is {d.Status}; ship it first");
            d.Status = DeliveryStatus.Delivered;
            d.DeliveredAt = date is { } dt ? new DateTimeOffset(dt.ToDateTime(TimeOnly.FromTimeSpan(TimeSpan.FromHours(12))), TimeSpan.Zero) : DateTimeOffset.UtcNow;
            d.ReceivedBy = Clean(receivedBy);
            Log(SalesRecordKind.Delivery, d.Id, "delivered", DeliveryStatus.Shipped, d.Status, d.ReceivedBy is null ? null : $"Recebido por {d.ReceivedBy}", user);
            await db.SaveChangesAsync(ct);
            var o = await LockOrderAsync(d.OrderId, ct);
            await RefreshOrderStatusAsync(o, $"{d.Reference} entregue", user, ct);
            return d;
        }, ct);
    }

    public async Task<Delivery> CancelDeliveryAsync(int id, string? reason, string? user, CancellationToken ct = default)
    {
        if (Clean(reason) is null) throw SalesException.Invalid("reason", "Required");
        return await InTransaction(async () =>
        {
            var d = await LockDeliveryAsync(id, ct);
            if (d.Status is DeliveryStatus.Cancelled or DeliveryStatus.Delivered) throw SalesException.Conflict($"Delivery is {d.Status}");
            var from = d.Status;
            if (d.Status == DeliveryStatus.Shipped && d.StockDocumentId is { } doc) await stock.ReverseAsync(doc, user ?? "system", $"{d.Reference} cancelada: {Clean(reason)}", ct);
            d.Status = DeliveryStatus.Cancelled;
            Log(SalesRecordKind.Delivery, d.Id, "cancelled", from, d.Status, Clean(reason), user);
            await db.SaveChangesAsync(ct);
            var o = await LockOrderAsync(d.OrderId, ct);
            await RefreshOrderStatusAsync(o, $"{d.Reference} cancelada", user, ct);
            return d;
        }, ct);
    }

    private async Task RefreshOrderStatusAsync(SalesOrder o, string note, string? user, CancellationToken ct)
    {
        if (o.Status is SalesOrderStatus.Created or SalesOrderStatus.Cancelled) return;
        var ids = o.Lines.Select(l => l.Id).ToList();
        var shipped = await ShippedAsync(ids, ct);
        var all = o.Lines.All(l => shipped.GetValueOrDefault(l.Id) >= l.Quantity);
        var any = shipped.Values.Any(v => v > 0);
        var allDelivered = all && !await db.Deliveries.AnyAsync(d => d.OrderId == o.Id && d.Status == DeliveryStatus.Shipped, ct);
        var next = allDelivered ? SalesOrderStatus.Delivered : all ? SalesOrderStatus.Shipped : any ? SalesOrderStatus.PartiallyShipped : SalesOrderStatus.Released;
        foreach (var line in o.Lines.Where(l => shipped.GetValueOrDefault(l.Id) >= l.Quantity && l.ReservationId is not null))
            if (await db.StockReservations.FirstOrDefaultAsync(r => r.Id == line.ReservationId && r.Status == ReservationStatus.Open, ct) is { } r)
                r.Status = ReservationStatus.Released;
        if (next != o.Status) Log(SalesRecordKind.Order, o.Id, "status", o.Status, next, note, user);
        else Log(SalesRecordKind.Order, o.Id, "delivery", o.Status, o.Status, note, user);
        o.Status = next;
        await db.SaveChangesAsync(ct);
    }

    private async Task<int> ShippingLocationAsync(CancellationToken ct)
    {
        if ((await SettingsAsync(ct)).ShippingLocationId is { } s) return s;
        if ((await production.SettingsAsync(ct)).ReceiptLocationId is { } r) return r;
        return await db.StockLocations.Where(l => l.Code == ProductionService.DefaultReceiptLocationCode && l.Active).Select(l => (int?)l.Id).FirstOrDefaultAsync(ct)
               ?? throw SalesException.Conflict($"Set the shipping location in /api/sales/settings or create stock location {ProductionService.DefaultReceiptLocationCode}");
    }

    private sealed record ResolvedLine(int ProductId, string? CustomerPartNumber, string Description, decimal Quantity, string Unit, decimal UnitPrice, decimal? ListPrice, decimal IpiPercent, decimal IcmsPercent, int? LeadTimeDays, DateOnly? DeliveryDate);

    private async Task<List<ResolvedLine>> BuildLinesAsync(int customerId, IReadOnlyList<SalesLineInput>? input, CancellationToken ct)
    {
        if (input is null || input.Count == 0) throw SalesException.Invalid("lines", "At least one item");
        var today = Today();
        var ids = input.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.Products.AsNoTracking().Where(p => ids.Contains(p.Id)).ToDictionaryAsync(p => p.Id, ct);
        var customerParts = await db.ProductCustomers.AsNoTracking().Where(pc => pc.CustomerId == customerId && ids.Contains(pc.ProductId)).ToDictionaryAsync(pc => pc.ProductId, ct);
        var result = new List<ResolvedLine>();
        foreach (var (l, n) in input.Select((l, n) => (l, n)))
        {
            var f = $"lines[{n}]";
            if (!products.TryGetValue(l.ProductId, out var p)) throw SalesException.Invalid($"{f}.productId", "Product not found");
            if (p.Blocked) throw SalesException.Invalid($"{f}.productId", $"Product {p.Code} is blocked");
            if (l.Quantity <= 0) throw SalesException.Invalid($"{f}.quantity", "Must be greater than zero");
            if (l.UnitPrice < 0) throw SalesException.Invalid($"{f}.unitPrice", "Cannot be negative");
            if (l.IpiPercent is < 0 or > 100) throw SalesException.Invalid($"{f}.ipiPercent", "Between 0 and 100");
            if (l.IcmsPercent is < 0 or > 100) throw SalesException.Invalid($"{f}.icmsPercent", "Between 0 and 100");
            if (l.LeadTimeDays is < 0) throw SalesException.Invalid($"{f}.leadTimeDays", "Cannot be negative");
            var price = await PriceAsync(p.Id, customerId, today, ct);
            var unitPrice = l.UnitPrice ?? price?.UnitPrice ?? throw SalesException.Invalid($"{f}.unitPrice", $"No price for {p.Code}; give one or register it in the price list");
            customerParts.TryGetValue(p.Id, out var cp);
            result.Add(new ResolvedLine(p.Id, cp?.CustomerPartNumber, Clean(l.Description) ?? cp?.CustomerDescription ?? p.Name, l.Quantity, p.StockUnit, unitPrice, price?.UnitPrice,
                l.IpiPercent ?? price?.IpiPercent ?? 0m, l.IcmsPercent ?? price?.IcmsPercent ?? 0m, l.LeadTimeDays, l.DeliveryDate));
        }
        return result;
    }

    private static QuoteLine ToQuoteLine(ResolvedLine l, int n) => new()
    {
        Sequence = (n + 1) * 10, ProductId = l.ProductId, CustomerPartNumber = l.CustomerPartNumber, Description = l.Description, Quantity = l.Quantity, Unit = l.Unit,
        UnitPrice = l.UnitPrice, ListPrice = l.ListPrice, IpiPercent = l.IpiPercent, IcmsPercent = l.IcmsPercent, LeadTimeDays = l.LeadTimeDays, DeliveryDate = l.DeliveryDate
    };

    private static void ApplyHeader(Quote q, QuoteInput i)
    {
        q.AddressId = i.AddressId;
        q.PaymentTermId = i.PaymentTermId;
        q.Freight = i.Freight;
        q.ContactName = Clean(i.ContactName);
        q.ContactEmail = Clean(i.ContactEmail);
        q.CustomerReference = Clean(i.CustomerReference);
        q.Notes = Clean(i.Notes);
    }

    private async Task ValidateHeaderAsync(int customerId, int? addressId, int? paymentTermId, CancellationToken ct)
    {
        var customer = await db.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.Id == customerId, ct) ?? throw SalesException.Invalid("customerId", "Customer not found");
        if (!customer.Active) throw SalesException.Invalid("customerId", $"Customer {customer.Name} is inactive");
        if (addressId is { } a && !await db.CustomerAddresses.AnyAsync(x => x.Id == a && x.CustomerId == customerId, ct)) throw SalesException.Invalid("addressId", "Address does not belong to the customer");
        if (paymentTermId is { } p && !await db.PaymentTerms.AnyAsync(x => x.Id == p && x.Active, ct)) throw SalesException.Invalid("paymentTermId", "Unknown or inactive payment term");
    }

    private async Task<Quote> QuoteStep(int id, string action, string? note, string? user, CancellationToken ct, Func<Quote, Task<string?>> change) =>
        await InTransaction(async () =>
        {
            var q = await LockQuoteAsync(id, ct);
            var from = q.Status;
            var overridden = await change(q);
            Log(SalesRecordKind.Quote, q.Id, overridden ?? action, from, q.Status, Clean(note), user);
            await db.SaveChangesAsync(ct);
            return q;
        }, ct);

    private void Log(SalesRecordKind kind, int id, string action, object? from, object? to, string? note, string? user) =>
        db.SalesEvents.Add(new SalesEvent { Kind = kind, RecordId = id, Action = action, FromStatus = from?.ToString(), ToStatus = to?.ToString(), Note = Clean(note), User = user, At = DateTimeOffset.UtcNow });

    private async Task<int> NextAsync(string sequence, CancellationToken ct) =>
        await db.Database.SqlQueryRaw<int>($"SELECT nextval('{sequence}')::int AS \"Value\"").SingleAsync(ct);

    private async Task<Quote> LockQuoteAsync(int id, CancellationToken ct)
    {
        if ((await db.Database.SqlQuery<int>($"SELECT id AS \"Value\" FROM quotes WHERE id = {id} FOR UPDATE").ToListAsync(ct)).Count == 0) throw SalesException.NotFound("Quote");
        var q = await db.Quotes.Include(x => x.Lines).FirstAsync(x => x.Id == id, ct);
        await db.Entry(q).ReloadAsync(ct);
        return q;
    }

    private async Task<SalesOrder> LockOrderAsync(int id, CancellationToken ct)
    {
        if ((await db.Database.SqlQuery<int>($"SELECT id AS \"Value\" FROM sales_orders WHERE id = {id} FOR UPDATE").ToListAsync(ct)).Count == 0) throw SalesException.NotFound("Order");
        var o = await db.SalesOrders.Include(x => x.Lines).FirstAsync(x => x.Id == id, ct);
        await db.Entry(o).ReloadAsync(ct);
        return o;
    }

    private async Task<Delivery> LockDeliveryAsync(int id, CancellationToken ct)
    {
        if ((await db.Database.SqlQuery<int>($"SELECT id AS \"Value\" FROM deliveries WHERE id = {id} FOR UPDATE").ToListAsync(ct)).Count == 0) throw SalesException.NotFound("Delivery");
        var d = await db.Deliveries.Include(x => x.Lines).FirstAsync(x => x.Id == id, ct);
        await db.Entry(d).ReloadAsync(ct);
        return d;
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

    public static DateOnly Today() => DateOnly.FromDateTime(DateTime.Today);
    private static decimal Money(decimal d) => Math.Round(d, 2, MidpointRounding.AwayFromZero);
    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}
