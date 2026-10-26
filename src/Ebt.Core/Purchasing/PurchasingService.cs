using System.Text.RegularExpressions;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Purchasing;

public sealed class PurchasingException(int status, string message, string? field = null) : Exception(message)
{
    public int Status { get; } = status;
    public string? Field { get; } = field;

    public static PurchasingException Invalid(string field, string message) => new(400, message, field);
    public static PurchasingException Conflict(string message) => new(409, message);
    public static PurchasingException NotFound(string what) => new(404, $"{what} not found");
}

public sealed record RequisitionInput(int? MaterialId, string? Description, string? Unit, decimal Quantity, string? Department, DateOnly? NeededBy, string? Application, string? Notes);
public sealed record OrderLineInput(int? MaterialId, string? Description, string? Unit, decimal Quantity, decimal UnitPrice, decimal DiscountPercent, decimal IcmsPercent, decimal IpiPercent, DateOnly DueDate, IReadOnlyList<int>? RequisitionIds);
public sealed record OrderInput(int SupplierId, string? PaymentTerms, string? Notes, IReadOnlyList<OrderLineInput> Lines);
public sealed record BidInput(decimal UnitPrice, decimal DiscountPercent, decimal IcmsPercent, decimal IpiPercent, int? LeadTimeDays, string? PaymentTerms, string? Notes);
public sealed record ReceiptLineInput(int PurchaseOrderLineId, decimal Quantity, decimal? UnitPrice, string? LotCode);
public sealed record ReceiptInput(int SupplierId, string InvoiceNumber, string? InvoiceSeries, DateOnly InvoiceDate, DateTimeOffset? ReceivedAt, decimal? InvoiceTotal, string? DivergenceJustification, string? Notes, IReadOnlyList<ReceiptLineInput> Lines);

public sealed partial class PurchasingService(EbtDbContext db, IEnumerable<IGoodsReceiptHandler> handlers)
{
    public const decimal DivergenceTolerance = 0.01m;

    private static readonly RequisitionStatus[] Quotable = [RequisitionStatus.Approved, RequisitionStatus.QuoteRejected];
    private static readonly RequisitionStatus[] Orderable = [RequisitionStatus.Approved, RequisitionStatus.QuoteApproved, RequisitionStatus.QuoteRejected];
    private static readonly RequisitionStatus[] Cancellable = [RequisitionStatus.PendingApproval, RequisitionStatus.Approved, RequisitionStatus.Rejected, RequisitionStatus.QuoteRejected];

    public static decimal NetUnitPrice(decimal unitPrice, decimal discountPercent) => unitPrice * (1 - discountPercent / 100m);

    public static decimal LineTotal(decimal quantity, decimal unitPrice, decimal discountPercent, decimal ipiPercent) =>
        Math.Round(quantity * NetUnitPrice(unitPrice, discountPercent) * (1 + ipiPercent / 100m), 2, MidpointRounding.AwayFromZero);

    public async Task<PurchaseRequisition> CreateRequisitionAsync(RequisitionInput i, string? user, CancellationToken ct)
    {
        if (i.Quantity <= 0) throw PurchasingException.Invalid("quantity", "Must be greater than zero");
        var (description, unit) = await DescribeAsync(i.MaterialId, i.Description, i.Unit, ct);
        var req = new PurchaseRequisition
        {
            MaterialId = i.MaterialId,
            Description = description,
            Unit = unit,
            Quantity = i.Quantity,
            Department = Clean(i.Department),
            NeededBy = i.NeededBy,
            Application = Clean(i.Application),
            Notes = Clean(i.Notes),
            Status = RequisitionStatus.PendingApproval,
            RequestedBy = user,
            RequestedAt = DateTimeOffset.UtcNow
        };
        db.PurchaseRequisitions.Add(req);
        await db.SaveChangesAsync(ct);
        return req;
    }

    public async Task<PurchaseRequisition> DecideRequisitionAsync(int id, bool approve, decimal? approvedQuantity, string? note, string? user, CancellationToken ct)
    {
        var req = await db.PurchaseRequisitions.FindAsync([id], ct) ?? throw PurchasingException.NotFound("Requisition");
        if (req.Status != RequisitionStatus.PendingApproval) throw PurchasingException.Conflict($"Requisition is {req.Status}, not pending approval");
        if (approve && approvedQuantity is <= 0) throw PurchasingException.Invalid("approvedQuantity", "Must be greater than zero");
        req.Status = approve ? RequisitionStatus.Approved : RequisitionStatus.Rejected;
        if (approve && approvedQuantity is { } q) req.Quantity = q;
        req.ApprovedQuantity = approve ? req.Quantity : null;
        req.DecidedBy = user;
        req.DecidedAt = DateTimeOffset.UtcNow;
        req.DecisionNote = Clean(note);
        await db.SaveChangesAsync(ct);
        return req;
    }

    public async Task<PurchaseRequisition> CancelRequisitionAsync(int id, string? note, string? user, CancellationToken ct)
    {
        var req = await db.PurchaseRequisitions.FindAsync([id], ct) ?? throw PurchasingException.NotFound("Requisition");
        if (!Cancellable.Contains(req.Status)) throw PurchasingException.Conflict($"A requisition that is {req.Status} cannot be cancelled");
        req.Status = RequisitionStatus.Cancelled;
        req.DecidedBy = user;
        req.DecidedAt = DateTimeOffset.UtcNow;
        req.DecisionNote = Clean(note) ?? req.DecisionNote;
        await db.SaveChangesAsync(ct);
        return req;
    }

    public async Task<Quotation> CreateQuotationAsync(IReadOnlyList<int> requisitionIds, IReadOnlyList<int> supplierIds, string? notes, string? user, CancellationToken ct)
    {
        if (requisitionIds.Count == 0) throw PurchasingException.Invalid("requisitionIds", "At least one requisition");
        if (supplierIds.Count == 0) throw PurchasingException.Invalid("supplierIds", "At least one supplier");
        var reqs = await db.PurchaseRequisitions.Where(r => requisitionIds.Contains(r.Id)).ToListAsync(ct);
        if (reqs.Count != requisitionIds.Distinct().Count()) throw PurchasingException.Invalid("requisitionIds", "Unknown requisition");
        if (reqs.FirstOrDefault(r => !Quotable.Contains(r.Status)) is { } bad)
            throw PurchasingException.Conflict($"Requisition {bad.Number} is {bad.Status}; only approved requisitions can be quoted");
        var suppliers = await ActiveSuppliersAsync(supplierIds, ct);

        var quotation = new Quotation { Status = QuotationStatus.Open, Notes = Clean(notes), CreatedBy = user, CreatedAt = DateTimeOffset.UtcNow };
        var n = 0;
        foreach (var group in reqs.GroupBy(r => (r.MaterialId, Description: r.MaterialId is null ? r.Description.ToUpperInvariant() : "", r.Unit)).OrderBy(g => g.Min(r => r.Number)))
        {
            var first = group.First();
            var item = new QuotationItem { Item = ++n, MaterialId = first.MaterialId, Description = first.Description, Unit = first.Unit, Quantity = group.Sum(r => r.Quantity) };
            item.Bids.AddRange(suppliers.Select(s => new QuotationBid { SupplierId = s, Status = BidStatus.Pending }));
            foreach (var r in group)
            {
                r.Status = RequisitionStatus.Quoting;
                item.Requisitions.Add(r);
            }
            quotation.Items.Add(item);
        }
        db.Quotations.Add(quotation);
        await db.SaveChangesAsync(ct);
        return quotation;
    }

    public async Task<Quotation> AddQuotationSupplierAsync(int quotationId, int supplierId, CancellationToken ct)
    {
        var quotation = await LoadQuotationAsync(quotationId, ct);
        RequireOpen(quotation);
        await ActiveSuppliersAsync([supplierId], ct);
        foreach (var item in quotation.Items.Where(i => !IsDecided(i) && i.Bids.All(b => b.SupplierId != supplierId)))
            item.Bids.Add(new QuotationBid { SupplierId = supplierId, Status = BidStatus.Pending });
        await db.SaveChangesAsync(ct);
        return quotation;
    }

    public async Task<QuotationBid> RecordBidAsync(int bidId, BidInput i, CancellationToken ct)
    {
        var bid = await db.QuotationBids.Include(b => b.QuotationItem!).ThenInclude(x => x.Quotation).FirstOrDefaultAsync(b => b.Id == bidId, ct)
                  ?? throw PurchasingException.NotFound("Bid");
        RequireOpen(bid.QuotationItem!.Quotation!);
        if (bid.Status != BidStatus.Pending) throw PurchasingException.Conflict($"Bid is already {bid.Status}");
        ValidatePrice(i.UnitPrice, i.DiscountPercent, i.IcmsPercent, i.IpiPercent);
        if (i.LeadTimeDays is < 0) throw PurchasingException.Invalid("leadTimeDays", "Must not be negative");
        bid.UnitPrice = i.UnitPrice;
        bid.DiscountPercent = i.DiscountPercent;
        bid.IcmsPercent = i.IcmsPercent;
        bid.IpiPercent = i.IpiPercent;
        bid.LeadTimeDays = i.LeadTimeDays;
        bid.PaymentTerms = Clean(i.PaymentTerms);
        bid.Notes = Clean(i.Notes);
        bid.RespondedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        return bid;
    }

    public async Task<Quotation> AwardAsync(int quotationId, int itemId, int bidId, CancellationToken ct)
    {
        var quotation = await LoadQuotationAsync(quotationId, ct);
        RequireOpen(quotation);
        var item = quotation.Items.FirstOrDefault(i => i.Id == itemId) ?? throw PurchasingException.NotFound("Quotation item");
        if (IsDecided(item)) throw PurchasingException.Conflict($"Item {item.Item} is already decided");
        var bid = item.Bids.FirstOrDefault(b => b.Id == bidId) ?? throw PurchasingException.NotFound("Bid");
        if (bid.UnitPrice is null) throw PurchasingException.Conflict("The supplier has not quoted a price yet");
        foreach (var b in item.Bids) b.Status = b == bid ? BidStatus.Approved : BidStatus.Rejected;
        foreach (var r in item.Requisitions.Where(r => r.Status == RequisitionStatus.Quoting)) r.Status = RequisitionStatus.QuoteApproved;
        CloseIfDecided(quotation);
        await db.SaveChangesAsync(ct);
        return quotation;
    }

    public async Task<Quotation> RejectItemAsync(int quotationId, int itemId, CancellationToken ct)
    {
        var quotation = await LoadQuotationAsync(quotationId, ct);
        RequireOpen(quotation);
        var item = quotation.Items.FirstOrDefault(i => i.Id == itemId) ?? throw PurchasingException.NotFound("Quotation item");
        if (IsDecided(item)) throw PurchasingException.Conflict($"Item {item.Item} is already decided");
        foreach (var b in item.Bids) b.Status = BidStatus.Rejected;
        foreach (var r in item.Requisitions.Where(r => r.Status == RequisitionStatus.Quoting)) r.Status = RequisitionStatus.QuoteRejected;
        CloseIfDecided(quotation);
        await db.SaveChangesAsync(ct);
        return quotation;
    }

    public async Task<Quotation> CancelQuotationAsync(int quotationId, CancellationToken ct)
    {
        var quotation = await LoadQuotationAsync(quotationId, ct);
        RequireOpen(quotation);
        if (quotation.Items.Any(IsDecided)) throw PurchasingException.Conflict("Some items are already decided; reject the remaining items instead");
        quotation.Status = QuotationStatus.Cancelled;
        foreach (var item in quotation.Items)
        {
            foreach (var b in item.Bids) b.Status = BidStatus.Rejected;
            foreach (var r in item.Requisitions.ToList())
            {
                r.Status = RequisitionStatus.Approved;
                r.QuotationItemId = null;
            }
        }
        await db.SaveChangesAsync(ct);
        return quotation;
    }

    public async Task<PurchaseOrder> CreateOrderAsync(OrderInput i, string? user, CancellationToken ct)
    {
        if (i.Lines is not { Count: > 0 }) throw PurchasingException.Invalid("lines", "At least one line");
        await ActiveSuppliersAsync([i.SupplierId], ct);
        var order = NewOrder(i.SupplierId, i.PaymentTerms, i.Notes, user);
        var reqIds = i.Lines.SelectMany(l => l.RequisitionIds ?? []).ToList();
        if (reqIds.Count != reqIds.Distinct().Count()) throw PurchasingException.Invalid("requisitionIds", "A requisition can only be on one line");
        var reqs = await db.PurchaseRequisitions.Where(r => reqIds.Contains(r.Id)).ToDictionaryAsync(r => r.Id, ct);

        foreach (var (l, idx) in i.Lines.Select((l, idx) => (l, idx)))
        {
            if (l.Quantity <= 0) throw PurchasingException.Invalid($"lines[{idx}].quantity", "Must be greater than zero");
            ValidatePrice(l.UnitPrice, l.DiscountPercent, l.IcmsPercent, l.IpiPercent, $"lines[{idx}].");
            var (description, unit) = await DescribeAsync(l.MaterialId, l.Description, l.Unit, ct);
            var line = new PurchaseOrderLine
            {
                LineNumber = idx + 1, MaterialId = l.MaterialId, Description = description, Unit = unit, Quantity = l.Quantity,
                UnitPrice = l.UnitPrice, DiscountPercent = l.DiscountPercent, IcmsPercent = l.IcmsPercent, IpiPercent = l.IpiPercent, DueDate = l.DueDate
            };
            foreach (var rid in l.RequisitionIds ?? [])
            {
                if (!reqs.TryGetValue(rid, out var r)) throw PurchasingException.Invalid($"lines[{idx}].requisitionIds", $"Unknown requisition {rid}");
                if (!Orderable.Contains(r.Status)) throw PurchasingException.Conflict($"Requisition {r.Number} is {r.Status}; it must be approved before ordering");
                if (r.MaterialId != l.MaterialId) throw PurchasingException.Invalid($"lines[{idx}].requisitionIds", $"Requisition {r.Number} is for a different material");
                r.Status = RequisitionStatus.OrderIssued;
                line.Requisitions.Add(r);
            }
            order.Lines.Add(line);
        }
        db.PurchaseOrders.Add(order);
        await db.SaveChangesAsync(ct);
        return order;
    }

    public async Task<PurchaseOrder> CreateOrderFromQuotationAsync(int quotationId, int supplierId, string? notes, string? user, CancellationToken ct)
    {
        var quotation = await LoadQuotationAsync(quotationId, ct);
        if (quotation.Status == QuotationStatus.Cancelled) throw PurchasingException.Conflict("Quotation is cancelled");
        var bidIds = quotation.Items.SelectMany(i => i.Bids).Where(b => b.SupplierId == supplierId && b.Status == BidStatus.Approved).Select(b => b.Id).ToList();
        var ordered = await db.PurchaseOrderLines.Where(l => l.QuotationBidId != null && bidIds.Contains(l.QuotationBidId.Value)).Select(l => l.QuotationBidId!.Value).ToListAsync(ct);
        var awarded = quotation.Items
            .Select(item => (item, bid: item.Bids.FirstOrDefault(b => b.SupplierId == supplierId && b.Status == BidStatus.Approved)))
            .Where(x => x.bid is not null && !ordered.Contains(x.bid.Id))
            .OrderBy(x => x.item.Item)
            .ToList();
        if (awarded.Count == 0) throw PurchasingException.Conflict("No awarded items left to order from this supplier");
        await ActiveSuppliersAsync([supplierId], ct);

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var order = NewOrder(supplierId, awarded.Select(x => x.bid!.PaymentTerms).FirstOrDefault(t => t is not null), notes, user);
        foreach (var (item, bid) in awarded)
        {
            var line = new PurchaseOrderLine
            {
                LineNumber = order.Lines.Count + 1, MaterialId = item.MaterialId, Description = item.Description, Unit = item.Unit, Quantity = item.Quantity,
                UnitPrice = bid!.UnitPrice!.Value, DiscountPercent = bid.DiscountPercent, IcmsPercent = bid.IcmsPercent, IpiPercent = bid.IpiPercent,
                DueDate = bid.LeadTimeDays is { } lead ? today.AddDays(lead) : item.Requisitions.Min(r => r.NeededBy) ?? today,
                QuotationBidId = bid.Id
            };
            foreach (var r in item.Requisitions.Where(r => r.Status == RequisitionStatus.QuoteApproved))
            {
                r.Status = RequisitionStatus.OrderIssued;
                line.Requisitions.Add(r);
            }
            order.Lines.Add(line);
        }
        db.PurchaseOrders.Add(order);
        await db.SaveChangesAsync(ct);
        return order;
    }

    public async Task<PurchaseOrder> CancelOrderAsync(int id, string? reason, string? user, CancellationToken ct)
    {
        var order = await LoadOrderAsync(id, ct);
        if (order.Status is not PurchaseOrderStatus.Open) throw PurchasingException.Conflict($"Order is {order.Status}; only open orders without receipts can be cancelled");
        if (order.Lines.Any(l => l.ReceivedQuantity > 0)) throw PurchasingException.Conflict("Order has receipts; close it instead");
        if (!Has(reason)) throw PurchasingException.Invalid("reason", "Required");
        order.Status = PurchaseOrderStatus.Cancelled;
        Stamp(order, reason, user);
        foreach (var line in order.Lines)
        {
            line.Closed = true;
            line.QuotationBidId = null;
            ReleaseRequisitions(line);
        }
        await db.SaveChangesAsync(ct);
        return order;
    }

    public async Task<PurchaseOrder> CloseOrderAsync(int id, string? reason, string? user, CancellationToken ct)
    {
        var order = await LoadOrderAsync(id, ct);
        if (order.Status is not (PurchaseOrderStatus.Open or PurchaseOrderStatus.PartiallyReceived)) throw PurchasingException.Conflict($"Order is already {order.Status}");
        if (order.Lines.All(l => l.ReceivedQuantity == 0)) throw PurchasingException.Conflict("Nothing was received; cancel the order instead");
        if (!Has(reason)) throw PurchasingException.Invalid("reason", "Required");
        order.Status = PurchaseOrderStatus.Closed;
        Stamp(order, reason, user);
        foreach (var line in order.Lines.Where(l => !l.Closed))
        {
            line.Closed = true;
            if (line.ReceivedQuantity == 0) ReleaseRequisitions(line);
        }
        await db.SaveChangesAsync(ct);
        return order;
    }

    public async Task<PurchaseOrderLine> RescheduleLineAsync(int orderId, int lineId, DateOnly dueDate, CancellationToken ct)
    {
        var line = await db.PurchaseOrderLines.Include(l => l.PurchaseOrder).FirstOrDefaultAsync(l => l.Id == lineId && l.PurchaseOrderId == orderId, ct)
                   ?? throw PurchasingException.NotFound("Order line");
        if (line.Closed || line.PurchaseOrder!.Status is not (PurchaseOrderStatus.Open or PurchaseOrderStatus.PartiallyReceived))
            throw PurchasingException.Conflict("Line is closed");
        line.DueDate = dueDate;
        await db.SaveChangesAsync(ct);
        return line;
    }

    public async Task<GoodsReceipt> ReceiveAsync(ReceiptInput i, string? user, CancellationToken ct)
    {
        if (!Has(i.InvoiceNumber)) throw PurchasingException.Invalid("invoiceNumber", "Required");
        if (i.Lines is not { Count: > 0 }) throw PurchasingException.Invalid("lines", "At least one line");
        if (i.Lines.Select(l => l.PurchaseOrderLineId).Distinct().Count() != i.Lines.Count) throw PurchasingException.Invalid("lines", "Each order line can appear once");
        var receivedAt = i.ReceivedAt ?? DateTimeOffset.UtcNow;
        if (receivedAt > DateTimeOffset.UtcNow.AddMinutes(5)) throw PurchasingException.Invalid("receivedAt", "Must not be in the future");
        if (i.InvoiceDate > DateOnly.FromDateTime(receivedAt.UtcDateTime).AddDays(1)) throw PurchasingException.Invalid("invoiceDate", "Must not be after the receipt date");

        var own = db.Database.CurrentTransaction is null;
        await using var tx = own ? await db.Database.BeginTransactionAsync(ct) : null;

        var ids = i.Lines.Select(l => l.PurchaseOrderLineId).ToArray();
        await db.Database.ExecuteSqlInterpolatedAsync($"SELECT 1 FROM purchase_order_lines WHERE id = ANY({ids}) FOR UPDATE", ct);
        var lines = await db.PurchaseOrderLines.Include(l => l.PurchaseOrder!).ThenInclude(o => o.Lines).Include(l => l.Material).Include(l => l.Requisitions)
            .Where(l => ids.Contains(l.Id)).ToDictionaryAsync(l => l.Id, ct);
        var settings = await db.PurchasingSettings.AsNoTracking().FirstOrDefaultAsync(ct) ?? new PurchasingSettings();
        var receiptDate = DateOnly.FromDateTime(receivedAt.UtcDateTime);

        var receipt = new GoodsReceipt
        {
            SupplierId = i.SupplierId, InvoiceNumber = i.InvoiceNumber.Trim(), InvoiceSeries = Clean(i.InvoiceSeries) ?? "", InvoiceDate = i.InvoiceDate,
            ReceivedAt = receivedAt, ReceivedBy = user, InvoiceTotal = i.InvoiceTotal, DivergenceJustification = Clean(i.DivergenceJustification), Notes = Clean(i.Notes)
        };
        foreach (var (l, idx) in i.Lines.Select((l, idx) => (l, idx)))
        {
            var f = $"lines[{idx}]";
            if (!lines.TryGetValue(l.PurchaseOrderLineId, out var line)) throw PurchasingException.Invalid($"{f}.purchaseOrderLineId", "Unknown order line");
            var order = line.PurchaseOrder!;
            if (order.SupplierId != i.SupplierId) throw PurchasingException.Invalid($"{f}.purchaseOrderLineId", $"Order {order.Number} belongs to another supplier");
            if (order.Status is not (PurchaseOrderStatus.Open or PurchaseOrderStatus.PartiallyReceived) || line.Closed)
                throw PurchasingException.Conflict($"Order {order.Number} line {line.LineNumber} is closed");
            if (l.Quantity <= 0) throw PurchasingException.Invalid($"{f}.quantity", "Must be greater than zero");
            if (l.UnitPrice is < 0) throw PurchasingException.Invalid($"{f}.unitPrice", "Must not be negative");
            var limit = line.Quantity * (1 + settings.ReceivingTolerancePercent / 100m);
            if (line.ReceivedQuantity + l.Quantity > limit)
                throw PurchasingException.Conflict($"Order {order.Number} line {line.LineNumber}: receiving {l.Quantity} would exceed ordered {line.Quantity} + {settings.ReceivingTolerancePercent}% (already received {line.ReceivedQuantity})");
            if (!settings.AllowEarlyReceipt && receiptDate < line.DueDate.AddDays(-settings.EarlyReceiptGraceDays))
                throw PurchasingException.Conflict($"Order {order.Number} line {line.LineNumber} is due {line.DueDate:yyyy-MM-dd}; early receipt is not allowed");

            var price = l.UnitPrice ?? line.UnitPrice;
            receipt.Lines.Add(new GoodsReceiptLine
            {
                PurchaseOrderLine = line, MaterialId = line.MaterialId, Material = line.Material, Quantity = l.Quantity, Unit = line.Unit, UnitPrice = price,
                DiscountPercent = line.DiscountPercent, IcmsPercent = line.IcmsPercent, IpiPercent = line.IpiPercent,
                Total = LineTotal(l.Quantity, price, line.DiscountPercent, line.IpiPercent), LotCode = Clean(l.LotCode)
            });
            line.ReceivedQuantity += l.Quantity;
            var status = line.ReceivedQuantity >= line.Quantity ? RequisitionStatus.Received : RequisitionStatus.PartiallyReceived;
            foreach (var r in line.Requisitions) r.Status = status;
        }

        receipt.CalculatedTotal = receipt.Lines.Sum(l => l.Total);
        if (i.InvoiceTotal is { } typed && Math.Abs(typed - receipt.CalculatedTotal) > DivergenceTolerance && receipt.DivergenceJustification is null)
            throw PurchasingException.Invalid("divergenceJustification", $"Invoice total {typed:0.00} differs from calculated {receipt.CalculatedTotal:0.00}; a justification is required");

        foreach (var order in lines.Values.Select(l => l.PurchaseOrder!).Distinct())
            order.Status = order.Lines.All(l => l.Closed || l.ReceivedQuantity >= l.Quantity) ? PurchaseOrderStatus.Received : PurchaseOrderStatus.PartiallyReceived;

        receipt.Installments.AddRange(Installments(lines.Values.First().PurchaseOrder!.PaymentTerms, i.InvoiceDate, i.InvoiceTotal ?? receipt.CalculatedTotal));
        await UpdateSupplierMaterialsAsync(receipt, ct);
        db.GoodsReceipts.Add(receipt);
        await db.SaveChangesAsync(ct);

        var evt = new GoodsReceived(receipt.Id, receipt.Number, receipt.SupplierId, receipt.ReceivedAt, receipt.InvoiceNumber, receipt.InvoiceSeries, receipt.InvoiceDate, receipt.ReceivedBy,
            receipt.Lines.Where(l => l.Material is not null).Select(l =>
            {
                var m = l.Material!;
                var factor = string.Equals(l.Unit, m.StockUnit, StringComparison.OrdinalIgnoreCase) ? 1m : m.PurchaseFactor;
                var stockQty = l.Quantity * factor;
                return new GoodsReceivedLine(l.Id, l.PurchaseOrderLine!.PurchaseOrderId, l.PurchaseOrderLineId, m.Id, stockQty, m.StockUnit,
                    Math.Round(l.Quantity * NetUnitPrice(l.UnitPrice, l.DiscountPercent) / stockQty, 6), l.IcmsPercent, l.IpiPercent, l.LotCode, m.RequiresInspection);
            }).ToList());
        foreach (var handler in handlers) await handler.HandleAsync(evt, ct);

        if (tx is not null) await tx.CommitAsync(ct);
        return receipt;
    }

    public static IEnumerable<PayableInstallment> Installments(string? paymentTerms, DateOnly invoiceDate, decimal total)
    {
        var days = DaysPattern().Matches(paymentTerms ?? "").Select(m => int.Parse(m.Value)).Where(d => d <= 720).ToList();
        if (days.Count == 0) days = [0];
        var share = Math.Round(total / days.Count, 2, MidpointRounding.ToZero);
        return days.Select((d, idx) => new PayableInstallment
        {
            Sequence = idx + 1,
            DueDate = invoiceDate.AddDays(d),
            Amount = idx == days.Count - 1 ? total - share * (days.Count - 1) : share
        });
    }

    [GeneratedRegex(@"\d{1,3}")]
    private static partial Regex DaysPattern();

    private async Task UpdateSupplierMaterialsAsync(GoodsReceipt receipt, CancellationToken ct)
    {
        var materialIds = receipt.Lines.Where(l => l.MaterialId is not null).Select(l => l.MaterialId!.Value).Distinct().ToList();
        var existing = await db.SupplierMaterials.Where(s => s.SupplierId == receipt.SupplierId && materialIds.Contains(s.MaterialId)).ToDictionaryAsync(s => s.MaterialId, ct);
        foreach (var l in receipt.Lines.Where(l => l.MaterialId is not null))
        {
            if (!existing.TryGetValue(l.MaterialId!.Value, out var sm))
                db.SupplierMaterials.Add(existing[l.MaterialId.Value] = sm = new SupplierMaterial { SupplierId = receipt.SupplierId, MaterialId = l.MaterialId.Value });
            if (sm.LastPurchaseDate is null || sm.LastPurchaseDate <= receipt.InvoiceDate)
            {
                sm.LastUnitPrice = Math.Round(NetUnitPrice(l.UnitPrice, l.DiscountPercent), 6);
                sm.LastPurchaseDate = receipt.InvoiceDate;
            }
        }
    }

    private static void ReleaseRequisitions(PurchaseOrderLine line)
    {
        foreach (var r in line.Requisitions.ToList())
        {
            r.Status = r.QuotationItemId is null ? RequisitionStatus.Approved : RequisitionStatus.QuoteApproved;
            r.PurchaseOrderLineId = null;
        }
    }

    private static PurchaseOrder NewOrder(int supplierId, string? paymentTerms, string? notes, string? user) => new()
    {
        SupplierId = supplierId, Status = PurchaseOrderStatus.Open, PaymentTerms = Clean(paymentTerms), Notes = Clean(notes), IssuedBy = user, IssuedAt = DateTimeOffset.UtcNow
    };

    private static void Stamp(PurchaseOrder order, string? reason, string? user)
    {
        order.ClosedAt = DateTimeOffset.UtcNow;
        order.ClosedBy = user;
        order.CloseReason = Clean(reason);
    }

    private async Task<Quotation> LoadQuotationAsync(int id, CancellationToken ct) =>
        await db.Quotations.Include(q => q.Items).ThenInclude(i => i.Bids).Include(q => q.Items).ThenInclude(i => i.Requisitions)
            .AsSplitQuery().FirstOrDefaultAsync(q => q.Id == id, ct) ?? throw PurchasingException.NotFound("Quotation");

    private async Task<PurchaseOrder> LoadOrderAsync(int id, CancellationToken ct) =>
        await db.PurchaseOrders.Include(o => o.Lines).ThenInclude(l => l.Requisitions).FirstOrDefaultAsync(o => o.Id == id, ct) ?? throw PurchasingException.NotFound("Order");

    private async Task<List<int>> ActiveSuppliersAsync(IReadOnlyList<int> ids, CancellationToken ct)
    {
        var distinct = ids.Distinct().ToList();
        var found = await db.Suppliers.Where(s => distinct.Contains(s.Id)).Select(s => new { s.Id, s.Active, s.Name }).ToListAsync(ct);
        if (found.Count != distinct.Count) throw PurchasingException.Invalid("supplierId", "Unknown supplier");
        if (found.FirstOrDefault(s => !s.Active) is { } inactive) throw PurchasingException.Conflict($"Supplier {inactive.Name} is inactive");
        return distinct;
    }

    private async Task<(string Description, string Unit)> DescribeAsync(int? materialId, string? description, string? unit, CancellationToken ct)
    {
        if (materialId is { } id)
        {
            var m = await db.Materials.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw PurchasingException.Invalid("materialId", "Unknown material");
            if (!m.Active) throw PurchasingException.Conflict($"Material {m.Code} is inactive");
            if (!m.GeneratesPurchaseOrder) throw PurchasingException.Conflict($"Material {m.Code} is not purchased");
            return (Clean(description) ?? m.Description, Clean(unit)?.ToUpperInvariant() ?? m.PurchaseUnit);
        }
        if (!Has(description)) throw PurchasingException.Invalid("description", "Required when no material is given");
        if (!Has(unit)) throw PurchasingException.Invalid("unit", "Required when no material is given");
        return (description!.Trim(), unit!.Trim().ToUpperInvariant());
    }

    private static void ValidatePrice(decimal unitPrice, decimal discount, decimal icms, decimal ipi, string prefix = "")
    {
        if (unitPrice < 0) throw PurchasingException.Invalid(prefix + "unitPrice", "Must not be negative");
        if (discount is < 0 or >= 100) throw PurchasingException.Invalid(prefix + "discountPercent", "Between 0 and 100");
        if (icms is < 0 or > 100) throw PurchasingException.Invalid(prefix + "icmsPercent", "Between 0 and 100");
        if (ipi is < 0 or > 100) throw PurchasingException.Invalid(prefix + "ipiPercent", "Between 0 and 100");
    }

    private static void RequireOpen(Quotation q)
    {
        if (q.Status != QuotationStatus.Open) throw PurchasingException.Conflict($"Quotation is {q.Status}");
    }

    private static bool IsDecided(QuotationItem item) => item.Bids.Count > 0 && item.Bids.All(b => b.Status != BidStatus.Pending)
                                                         || item.Requisitions.Any(r => r.Status == RequisitionStatus.QuoteRejected);

    private static void CloseIfDecided(Quotation q)
    {
        if (q.Items.All(IsDecided)) q.Status = QuotationStatus.Closed;
    }

    private static bool Has(string? value) => !string.IsNullOrWhiteSpace(value);
    private static string? Clean(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
