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
            // Lead times are working days counted from the day the customer approved the quote, not from the day the order is typed.
            var basis = q.DecidedAt is { } approved ? Clock.DateOf(approved) : today;
            var studies = await ViabilityRules.UsableForQuoteAsync(db, q.Id, ct);
            var lines = q.Lines.OrderBy(l => l.Sequence).Select(l => new SalesLineInput(l.ProductId, l.Quantity, l.UnitPrice, l.IpiPercent, l.IcmsPercent, l.LeadTimeDays,
                l.DeliveryDate ?? (l.LeadTimeDays is { } d ? WorkDays.Add(basis, d) : null), l.Description, null, studies.TryGetValue(l.ProductId, out var fid) ? fid : null)).ToList();
            var order = await CreateOrderCoreAsync(new SalesOrderInput(q.CustomerId, addressId, lines, Clean(i.CustomerPo) ?? q.CustomerPo, q.PaymentTermId, q.Freight, q.Notes, null, q.CustomPaymentTerm), q, i.OverrideCredit && mayOverrideCredit, user, ct);
            var from = q.Status;
            q.Status = QuoteStatus.Converted;
            q.SalesOrderId = order.Id;
            Log(SalesRecordKind.Quote, q.Id, "converted", from, q.Status, order.Reference, user);
            await db.SaveChangesAsync(ct);
            return order;
        }, ct);
    }

    public Task<SalesOrder> CreateOrderAsync(SalesOrderInput i, bool overrideCredit, string? user, CancellationToken ct = default, bool mayApprovePrices = false) =>
        InTransaction(() => CreateOrderCoreAsync(i, null, overrideCredit, user, ct, mayApprovePrices), ct);

    private async Task<SalesOrder> CreateOrderCoreAsync(SalesOrderInput i, Quote? quote, bool overrideCredit, string? user, CancellationToken ct, bool mayApprovePrices = false)
    {
        await ValidateHeaderAsync(i.CustomerId, i.AddressId, i.PaymentTermId, ct);
        var lines = await BuildLinesAsync(i.CustomerId, i.Lines, ct);
        if (quote is null) await EnsurePricesAllowedAsync(lines, mayApprovePrices, ct);
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

    public async Task<SalesOrder> UpdateOrderAsync(int id, SalesOrderInput i, string? user, CancellationToken ct = default, bool mayApprovePrices = false)
    {
        await ValidateHeaderAsync(i.CustomerId, i.AddressId, i.PaymentTermId, ct);
        var lines = await BuildLinesAsync(i.CustomerId, i.Lines, ct);
        await ViabilityRules.ValidateAsync(db, i.CustomerId, lines.Select(l => (l.ProductId, l.FeasibilityId)), id, ct);
        return await InTransaction(async () =>
        {
            var o = await LockOrderAsync(id, ct);
            if (o.Status != SalesOrderStatus.Created) throw SalesException.Conflict("Only orders not yet released can be edited");
            if (o.CustomerId != i.CustomerId) throw SalesException.Invalid("customerId", "The customer cannot change");
            if (o.QuoteId is null) await EnsurePricesAllowedAsync(lines, mayApprovePrices, ct);
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

    public async Task<SalesOrder> ReleaseAsync(int id, bool useStock, string? user, CancellationToken ct = default, bool overrideCredit = false)
    {
        return await InTransaction(async () =>
        {
            var o = await LockOrderAsync(id, ct);
            if (o.Status != SalesOrderStatus.Created) throw SalesException.Conflict($"Order is {o.Status}; only new orders can be released");
            await EnsureCreditAsync(o, "liberação", overrideCredit, user, ct);
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

}
