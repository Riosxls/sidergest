using static Ebt.Core.Services.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Viability;
using Ebt.Core.Inventory;
using Ebt.Core.Production;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Sales;

public sealed partial class SalesService
{
    public async Task<Delivery> CreateDeliveryAsync(int orderId, DeliveryInput i, string? user, CancellationToken ct = default)
    {
        if (i.PlannedDate < Today().AddDays(-MaxBackdateDays)) throw SalesException.Invalid("plannedDate", $"Planned date more than {MaxBackdateDays} days in the past");
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
                weight = KgPerUnit(line, product) is { } kg && weight is { } acc ? acc + kg * r.Quantity : null; // sold-by-KG lines already are kg
            }
            d.Packages = d.Lines.Sum(l => l.Packages);
            d.GrossWeightKg = weight is { } total ? Math.Round(total, 3) : null;
            db.Deliveries.Add(d);
            await db.SaveChangesAsync(ct);
            Log(SalesRecordKind.Delivery, d.Id, "created", null, d.Status, $"Pedido {o.Reference}", user);
            Log(SalesRecordKind.Order, o.Id, "delivery-planned", o.Status, o.Status, $"{d.Reference} para {d.PlannedDate:dd/MM/yyyy}", user);
            await db.SaveChangesAsync(ct);
            return d;
        }, ct);
    }

    /// <summary>
    /// Physical shipment. A caller without the right to emit the NF (<paramref name="canEmitInvoice"/> false) ships the goods and leaves the NF pending for <see cref="EmitInvoiceAsync"/>.
    /// Shipping items that have no issued certificate (<see cref="ShipInput.WithoutCertificate"/>) needs <paramref name="canWaiveCertificate"/> (the certificates-issue capability or a sales manager).
    /// </summary>
    public async Task<Delivery> ShipAsync(int id, ShipInput i, string? user, CancellationToken ct = default, bool canEmitInvoice = true, bool overrideCredit = false, bool canWaiveCertificate = false)
    {
        if (i.Date < Today().AddDays(-MaxBackdateDays)) throw SalesException.Invalid("date", $"Shipping date more than {MaxBackdateDays} days in the past");
        return await InTransaction(async () =>
        {
            var (d, o) = await LockDeliveryAndOrderAsync(id, ct);
            if (d.Status != DeliveryStatus.Planned) throw SalesException.Conflict($"Delivery is {d.Status}");
            if (o.Status is not (SalesOrderStatus.Released or SalesOrderStatus.PartiallyShipped)) throw SalesException.Conflict($"Order is {o.Status}");
            await EnsureCreditAsync(o, "expedição", overrideCredit, user, ct);
            var certified = o.CertificateWaived || await CertificatesCoverAsync(o, d, ct);
            if (!certified && !i.WithoutCertificate)
                throw SalesException.Conflict($"{d.Reference} has items without an issued quality certificate. Issue one for each item, waive it on the order, or ship without it");
            if (!certified && !canWaiveCertificate)
                throw SalesException.Forbidden($"{d.Reference} has items without an issued quality certificate, and shipping without it needs the certificates-issue permission or a sales manager. Issue the certificates first");
            // Only someone who may emit the NF (or any shipper while emission is off) can name an NF number by hand; for others the field would skip the fiscal emission.
            var fiscalOn = await fiscal.EnabledAsync(ct);
            var typedInvoice = canEmitInvoice || !fiscalOn ? Clean(i.InvoiceNumber) : null;
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
            var doc = await stock.PostAsync(new StockPost(MovementType.Shipment, i.Date, stockLines, d.Reference, CustomerId: o.CustomerId, Notes: $"{o.Reference}{(typedInvoice is { } nf ? $" · NF {nf}" : "")}"), user ?? "system", ct);
            d.StockDocumentId = doc.Id;
            d.Status = DeliveryStatus.Shipped;
            d.ShippedAt = DateTimeOffset.UtcNow;
            d.ShippedBy = user;
            d.InvoiceNumber = typedInvoice ?? d.InvoiceNumber;
            d.Carrier = Clean(i.Carrier) ?? d.Carrier;
            d.VehiclePlate = Clean(i.VehiclePlate)?.ToUpper();
            d.GrossWeightKg = i.GrossWeightKg ?? d.GrossWeightKg;
            d.LotNumber = Clean(i.LotNumber) ?? d.LotNumber;
            d.InvoicedValue = i.InvoicedValue ?? d.InvoicedValue;
            // Venda (5101): stock is lowered first, then the NF is authorized; if SEFAZ rejects, the transaction rolls back and stock is untouched.
            // Every local write (delivery, order status, history) is saved BEFORE the SEFAZ call: SEFAZ authorizes on its own connection and cannot be rolled back, so the
            // only thing left to do after it is stamping the NF number. If even that fails, the authorized NF stays without a delivery and the next ship
            // attempt picks it up again (FiscalService.IssueSaleAsync "orphan" path) instead of issuing a second NF.
            var invoicePending = d.InvoiceNumber is null && !canEmitInvoice && fiscalOn;
            var willIssue = d.InvoiceNumber is null && !invoicePending && fiscalOn;
            var shippedNote = string.Join(" · ", new[] { d.InvoiceNumber is null ? null : $"NF {d.InvoiceNumber}", invoicePending ? "NF pendente" : null, certified ? null : "sem certificado" }.OfType<string>());
            Log(SalesRecordKind.Delivery, d.Id, "shipped", DeliveryStatus.Planned, d.Status, shippedNote.Length > 0 ? shippedNote : null, user);
            await db.SaveChangesAsync(ct);
            await RefreshOrderStatusAsync(o, $"{d.Reference} expedida", user, ct);
            if (willIssue)
            {
                var invoice = await fiscal.IssueSaleAsync(d, o, new SaleInvoiceOptions(i.Cfop, i.Freight ?? 0m, Clean(i.Carrier), Clean(i.VehiclePlate)?.ToUpper(), i.GrossWeightKg), user, ct);
                d.InvoiceNumber = invoice.Number.ToString();
                doc.Notes = $"{doc.Notes} · NF {invoice.Number}";
                var shipped = await db.SalesEvents.Where(e => e.Kind == SalesRecordKind.Delivery && e.RecordId == d.Id && e.Action == "shipped").OrderByDescending(e => e.Id).FirstAsync(ct);
                shipped.Note = string.Join(" · ", new[] { $"NF {d.InvoiceNumber}", certified ? null : "sem certificado" }.OfType<string>());
                await db.SaveChangesAsync(ct);
            }
            return d;
        }, ct);
    }

    /// <summary>True when every line of the delivery has an issued certificate: one for that order line, or for its product when the certificate names no line. A certificate linked to another delivery does not count.</summary>
    private async Task<bool> CertificatesCoverAsync(SalesOrder o, Delivery d, CancellationToken ct)
    {
        var issued = await db.QualityCertificates.AsNoTracking()
            .Where(c => c.OrderId == o.Id && c.Status == CertificateStatus.Issued && (c.DeliveryId == null || c.DeliveryId == d.Id))
            .Select(c => new { c.OrderLineId, c.ProductId }).ToListAsync(ct);
        return d.Lines.All(dl =>
        {
            var line = o.Lines.First(l => l.Id == dl.OrderLineId);
            return issued.Any(c => c.OrderLineId == line.Id || (c.OrderLineId is null && c.ProductId == line.ProductId));
        });
    }

    /// <summary>
    /// Orders (of those given) that still wait for a quality certificate, with the same per-line rule as <see cref="CertificatesCoverAsync"/>: every line with something left to ship
    /// needs an issued certificate for that line, or for its product when the certificate names no line. Waived orders never wait; a certificate tied to a delivery that already
    /// shipped or was cancelled no longer covers what is left.
    /// </summary>
    public async Task<HashSet<int>> OrdersNeedingCertificateAsync(IReadOnlyCollection<int> orderIds, CancellationToken ct = default)
    {
        if (orderIds.Count == 0) return [];
        var orders = await db.SalesOrders.AsNoTracking().Where(o => orderIds.Contains(o.Id) && !o.CertificateWaived)
            .Select(o => new { o.Id, Lines = o.Lines.Select(l => new { l.Id, l.ProductId, l.Quantity }).ToList() }).ToListAsync(ct);
        var shipped = await ShippedAsync(orders.SelectMany(o => o.Lines.Select(l => l.Id)).ToList(), ct);
        var issued = await db.QualityCertificates.AsNoTracking()
            .Where(c => orderIds.Contains(c.OrderId) && c.Status == CertificateStatus.Issued && (c.DeliveryId == null || db.Deliveries.Any(d => d.Id == c.DeliveryId && d.Status == DeliveryStatus.Planned)))
            .Select(c => new { c.OrderId, c.OrderLineId, c.ProductId }).ToListAsync(ct);
        return orders.Where(o => o.Lines.Any(l => l.Quantity - shipped.GetValueOrDefault(l.Id) > 0
                && !issued.Any(c => c.OrderId == o.Id && (c.OrderLineId == l.Id || (c.OrderLineId is null && c.ProductId == l.ProductId))))).Select(o => o.Id).ToHashSet();
    }

    /// <summary>Issues the sale NF of a delivery that was shipped without one (the shipper lacked the right to emit it).</summary>
    public async Task<Delivery> EmitInvoiceAsync(int id, EmitInvoiceInput i, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var (d, o) = await LockDeliveryAndOrderAsync(id, ct);
            if (d.Status is not (DeliveryStatus.Shipped or DeliveryStatus.Delivered)) throw SalesException.Conflict($"Delivery is {d.Status}; ship it first");
            if (d.InvoiceNumber is not null || await db.FiscalDocuments.AnyAsync(f => f.DeliveryId == id && f.Kind == FiscalKind.Sale && f.Status == FiscalStatus.Authorized, ct))
                throw SalesException.Conflict("This delivery already has an NF");
            if (!await fiscal.EnabledAsync(ct)) throw SalesException.Conflict("NF emission is disabled");
            var invoice = await fiscal.IssueSaleAsync(d, o, new SaleInvoiceOptions(i.Cfop, i.Freight ?? 0m, Clean(i.Carrier) ?? d.Carrier, Clean(i.VehiclePlate)?.ToUpper() ?? d.VehiclePlate, i.GrossWeightKg ?? d.GrossWeightKg), user, ct);
            d.InvoiceNumber = invoice.Number.ToString();
            if (d.StockDocumentId is { } sd && await db.StockDocuments.FirstOrDefaultAsync(x => x.Id == sd, ct) is { } doc) doc.Notes = $"{doc.Notes} · NF {invoice.Number}";
            Log(SalesRecordKind.Delivery, d.Id, "invoice-emitted", d.Status, d.Status, $"NF {invoice.Number}", user);
            await db.SaveChangesAsync(ct);
            return d;
        }, ct);
    }

    public async Task<Delivery> ConfirmAsync(int id, DateOnly? date, string? receivedBy, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var (d, o) = await LockDeliveryAndOrderAsync(id, ct);
            if (d.Status != DeliveryStatus.Shipped) throw SalesException.Conflict($"Delivery is {d.Status}; ship it first");
            if (date is { } day)
            {
                if (day > Today()) throw SalesException.Invalid("date", "The delivery cannot be confirmed for a future date");
                if (d.ShippedAt is { } sent && day < Ebt.Core.Services.Clock.DateOf(sent)) throw SalesException.Invalid("date", "The delivery date cannot be before the shipping date");
            }
            d.Status = DeliveryStatus.Delivered;
            d.DeliveredAt = date is { } dt ? new DateTimeOffset(dt.ToDateTime(TimeOnly.FromTimeSpan(TimeSpan.FromHours(12))), TimeSpan.Zero) : DateTimeOffset.UtcNow;
            d.ReceivedBy = Clean(receivedBy);
            Log(SalesRecordKind.Delivery, d.Id, "delivered", DeliveryStatus.Shipped, d.Status, d.ReceivedBy is null ? null : $"Recebido por {d.ReceivedBy}", user);
            await db.SaveChangesAsync(ct);
            await RefreshOrderStatusAsync(o, $"{d.Reference} entregue", user, ct);
            return d;
        }, ct);
    }

    public Task<Delivery> CancelDeliveryAsync(int id, string? reason, string? user, CancellationToken ct = default) => CancelDeliveryCoreAsync(id, reason, user, false, ct);

    /// <param name="invoiceBeingCancelled">True only from <see cref="CancelInvoiceAsync"/>, which cancels the NF itself right after the delivery was undone.</param>
    private async Task<Delivery> CancelDeliveryCoreAsync(int id, string? reason, string? user, bool invoiceBeingCancelled, CancellationToken ct)
    {
        if (Clean(reason) is null) throw SalesException.Invalid("reason", "Required");
        return await InTransaction(async () =>
        {
            var (d, o) = await LockDeliveryAndOrderAsync(id, ct);
            if (d.Status is DeliveryStatus.Cancelled or DeliveryStatus.Delivered) throw SalesException.Conflict($"Delivery is {d.Status}");
            if (!invoiceBeingCancelled && await db.FiscalDocuments.Where(f => f.DeliveryId == id && f.Status == FiscalStatus.Authorized).Select(f => (int?)f.Number).FirstOrDefaultAsync(ct) is { } nfNumber)
                throw SalesException.Conflict($"NF {nfNumber} is authorized for this delivery; cancel the NF first");
            // A Pending NF is an unknown SEFAZ outcome: it may be authorized there, so the goods cannot come back before the portal is checked.
            if (await db.FiscalDocuments.AnyAsync(f => f.DeliveryId == id && f.Status == FiscalStatus.Pending, ct))
                throw SalesException.Conflict("Há uma NF pendente de retorno da SEFAZ para esta entrega. Confira a situação da nota no portal da SEFAZ antes de cancelar a entrega");
            var from = d.Status;
            if (d.Status == DeliveryStatus.Shipped && d.StockDocumentId is { } doc) await stock.ReverseAsync(doc, user ?? "system", $"{d.Reference} cancelada: {Clean(reason)}", ct);
            d.Status = DeliveryStatus.Cancelled;
            Log(SalesRecordKind.Delivery, d.Id, "cancelled", from, d.Status, Clean(reason), user);
            await db.SaveChangesAsync(ct);
            await RefreshOrderStatusAsync(o, $"{d.Reference} cancelada", user, ct);
            return d;
        }, ct);
    }

    /// <summary>Cancels the NF of a shipped delivery at SEFAZ, then cancels the delivery (stock comes back, the order reopens). Blocked once the delivery is confirmed.</summary>
    public async Task<FiscalDocument> CancelInvoiceAsync(int documentId, string? reason, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var f = await db.FiscalDocuments.AsNoTracking().FirstOrDefaultAsync(x => x.Id == documentId, ct) ?? throw SalesException.NotFound("NF");
            if (f.Kind != FiscalKind.Sale || f.DeliveryId is not { } deliveryId) throw SalesException.Conflict($"NF {f.Number} is not a sale NF");
            var (d, _) = await LockDeliveryAndOrderAsync(deliveryId, ct);
            if (d.Status == DeliveryStatus.Delivered) throw SalesException.Conflict($"{d.Reference} was already delivered; issue a return NF instead of cancelling");
            // The delivery goes first (stock back, order reopened): that is where a closed period or another rule can refuse. SEFAZ is called last, so a refusal
            // here leaves the NF untouched, and a SEFAZ refusal rolls the delivery cancellation back with everything else.
            await CancelDeliveryCoreAsync(deliveryId, $"NF {f.Number} cancelada: {Clean(reason)}", user, true, ct);
            return await fiscal.CancelAsync(documentId, reason, user, ct);
        }, ct);
    }
}
