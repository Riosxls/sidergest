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
            q.NeedsApproval = NeedsApprovalFor(Totals(q), settings);
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
            q.Conditions = Clean(i.Conditions) ?? settings.DefaultConditions;
            ApplyHeader(q, i);
            // Replacing only the lines would leave the quote row untouched, so its row version would not move and a stale editor would not be caught.
            db.Entry(q).Property(x => x.Notes).IsModified = true;
            db.QuoteLines.RemoveRange(q.Lines);
            await db.SaveChangesAsync(ct);
            q.Lines = lines.Select((l, n) => ToQuoteLine(l, n)).ToList();
            q.NeedsApproval = NeedsApprovalFor(Totals(q), settings);
            Log(SalesRecordKind.Quote, q.Id, "edited", q.Status, q.Status, null, user);
            await db.SaveChangesAsync(ct);
            return q;
        }, ct);
    }

    /// <summary>
    /// Sales staff may delete only a brand-new draft. An admin may also clear out drafts of any revision and quotes that ended without an order
    /// (cancelled, declined, expired), e.g. test data; a quote that became an order is never deleted.
    /// </summary>
    public async Task DeleteQuoteAsync(int id, bool admin, CancellationToken ct = default)
    {
        await InTransaction(async () =>
        {
            var q = await LockQuoteAsync(id, ct);
            var allowed = admin
                ? q.Status is QuoteStatus.Draft or QuoteStatus.Cancelled or QuoteStatus.Rejected or QuoteStatus.Expired
                : q.Status == QuoteStatus.Draft && q.Revision == 0;
            if (!allowed) throw SalesException.Conflict(admin ? "Only drafts and cancelled, declined or expired quotes can be deleted" : "Only new drafts can be deleted; cancel it instead");
            if (q.SalesOrderId is not null || await db.SalesOrders.AnyAsync(o => o.QuoteId == id, ct)) throw SalesException.Conflict("This quote has a sales order and cannot be deleted");
            if (await db.FeasibilityStudies.AnyAsync(f => f.QuoteId == id, ct)) throw SalesException.Conflict("A feasibility study is linked to this quote; remove the link first");
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
        q.NeedsApproval = NeedsApprovalFor(totals, settings);
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

    /// <summary>After the customer approves: registers the purchase order, which needs its text or file attached to the quote.</summary>
    /// <summary>The customer's purchase order is in. When it carries delivery dates of its own, <paramref name="deliveryDates"/> replace the lead time of those items (the date the customer wrote wins, even when it is later than the lead time would give).</summary>
    public Task<Quote> ReceivePurchaseOrderAsync(int id, string? customerPo, string? note, string? user, CancellationToken ct = default, IReadOnlyList<QuoteLineDate>? deliveryDates = null) => QuoteStep(id, "po-received", note, user, ct, q =>
    {
        if (q.Status != QuoteStatus.Accepted) throw SalesException.Conflict($"Quote is {q.Status}; the customer must approve it first");
        if (Clean(q.RequestText) is null && q.RequestFileName is null) throw SalesException.Conflict("Attach the customer's purchase order (file or text) first");
        var changes = new List<string>();
        foreach (var (d, n) in (deliveryDates ?? []).Select((d, n) => (d, n)))
        {
            var line = q.Lines.FirstOrDefault(l => l.Id == d.LineId) ?? throw SalesException.Invalid($"deliveryDates[{n}].lineId", "Not a line of this quote");
            if (d.DeliveryDate is { } day && day < Today()) throw SalesException.Invalid($"deliveryDates[{n}].deliveryDate", "Cannot be in the past");
            if (line.DeliveryDate == d.DeliveryDate) continue;
            line.DeliveryDate = d.DeliveryDate;
            changes.Add(d.DeliveryDate is { } to ? $"item {line.Sequence}: {to:dd/MM/yyyy}" : $"item {line.Sequence}: volta ao prazo em dias úteis");
        }
        if (changes.Count > 0) Log(SalesRecordKind.Quote, q.Id, "delivery-dates", q.Status, q.Status, "Data de entrega do pedido de compra do cliente · " + string.Join("; ", changes), user);
        q.Status = QuoteStatus.PurchaseOrder;
        q.CustomerPo = Clean(customerPo) ?? q.CustomerPo;
        return Task.FromResult<string?>(null);
    });

    public Task<Quote> AcceptAsync(int id, string? customerPo, string? note, string? user, CancellationToken ct = default) => QuoteStep(id, "accepted", note, user, ct, q =>
    {
        if (q.Status != QuoteStatus.Sent) throw SalesException.Conflict($"Quote is {q.Status}");
        if (q.ValidUntil < Today()) throw SalesException.Conflict($"Quote expired on {q.ValidUntil:dd/MM/yyyy}; revise it");
        q.Status = QuoteStatus.Accepted;
        q.CustomerPo = Clean(customerPo) ?? q.CustomerPo;
        q.DecidedAt = DateTimeOffset.UtcNow;
        q.DecisionBy = user;
        q.DecisionNote = Clean(note);
        return Task.FromResult<string?>(null);
    });

    /// <summary>
    /// The sale is lost. While the quote is out with the customer (Sent) this is "cliente recusou"; once the customer had approved it or sent a purchase order
    /// (Accepted, PurchaseOrder) it is "cliente desistiu". Both end as Rejected with a lost reason; the history tells them apart.
    /// </summary>
    public Task<Quote> DeclineAsync(int id, string? reason, LostReason? lostReason, string? user, CancellationToken ct = default) => QuoteStep(id, "declined", reason, user, ct, q =>
    {
        if (q.Status is not (QuoteStatus.Sent or QuoteStatus.Accepted or QuoteStatus.PurchaseOrder)) throw SalesException.Conflict($"Quote is {q.Status}");
        if (Clean(reason) is null) throw SalesException.Invalid("reason", "Required");
        if (lostReason is { } lr && !Enum.IsDefined(lr)) throw SalesException.Invalid("lostReason", "Unknown reason");
        var gaveUp = q.Status is QuoteStatus.Accepted or QuoteStatus.PurchaseOrder;
        q.LostReason = lostReason ?? (gaveUp ? LostReason.CustomerGaveUp : null);
        q.Status = QuoteStatus.Rejected;
        q.DecidedAt = DateTimeOffset.UtcNow;
        q.DecisionBy = user;
        q.DecisionNote = Clean(reason);
        return Task.FromResult<string?>(gaveUp ? "gave-up" : null);
    });

    /// <summary>Takes a quote that is waiting for (or has) the manager's approval back to draft so it can be edited; it must be approved again if the discount still needs it.</summary>
    public Task<Quote> ReopenAsync(int id, string? note, string? user, CancellationToken ct = default) => QuoteStep(id, "reopened", note, user, ct, q =>
    {
        if (q.Status is not (QuoteStatus.PendingApproval or QuoteStatus.Approved)) throw SalesException.Conflict($"Quote is {q.Status}; only a quote waiting for or holding an approval goes back to draft");
        q.Status = QuoteStatus.Draft;
        q.ApprovedBy = null;
        q.ApprovedAt = null;
        return Task.FromResult<string?>(null);
    });

    /// <summary>Moves the validity date of a quote that is still with the customer; an expired one is sent again (back to Sent) with the new date.</summary>
    public Task<Quote> ExtendValidityAsync(int id, DateOnly? validUntil, string? note, string? user, CancellationToken ct = default) => QuoteStep(id, "validity-extended", note, user, ct, q =>
    {
        if (q.Status is not (QuoteStatus.Sent or QuoteStatus.Expired)) throw SalesException.Conflict($"Quote is {q.Status}; only a sent or expired quote can have its validity extended");
        var today = Today();
        if (validUntil is not { } v || v < today) throw SalesException.Invalid("validUntil", "Give a date from today on");
        if (v > today.AddDays(365)) throw SalesException.Invalid("validUntil", "At most one year from today");
        q.ValidUntil = v;
        q.Status = QuoteStatus.Sent;
        return Task.FromResult<string?>(null);
    });

    /// <summary>
    /// The customer changed their mind: cancels this quote (kept for history) and opens a new draft with the next letter (PROP 4685-A → -B),
    /// copying customer, items and prazo. <paramref name="customerPo"/>: null carries the old PO forward, blank clears it, text replaces it.
    /// </summary>
    public async Task<Quote> ReviseAsync(int id, string? reason, string? customerPo, string? user, CancellationToken ct = default)
    {
        if (Clean(reason) is null) throw SalesException.Invalid("note", "Required");
        return await InTransaction(async () =>
        {
            var old = await LockQuoteAsync(id, ct);
            if (!Revisable.Contains(old.Status)) throw SalesException.Conflict($"Quote is {old.Status}");
            var next = await db.Quotes.Where(x => x.Number == old.Number).MaxAsync(x => x.Revision, ct) + 1;
            if (next > 25) throw SalesException.Conflict("Too many revisions of this quote");
            foreach (var original in await db.Quotes.Where(x => x.Number == old.Number && x.Revision == 0).ToListAsync(ct))
                original.Reference = QuoteReference(original.Number, 0, revised: true);
            var settings = await SettingsAsync(ct);
            var q = new Quote
            {
                Number = old.Number, Revision = next, Reference = QuoteReference(old.Number, next), CustomerId = old.CustomerId, Status = QuoteStatus.Draft, CreatedBy = user, CreatedAt = DateTimeOffset.UtcNow,
                AddressId = old.AddressId, ContactName = old.ContactName, ContactEmail = old.ContactEmail, CustomerReference = old.CustomerReference, PaymentTermId = old.PaymentTermId,
                CustomPaymentTerm = old.CustomPaymentTerm, Freight = old.Freight, ValidityDays = old.ValidityDays, Conditions = old.Conditions, Notes = old.Notes,
                CustomerPo = customerPo is null ? old.CustomerPo : Clean(customerPo),
                Lines = old.Lines.OrderBy(l => l.Sequence).Select(l => new QuoteLine
                {
                    Sequence = l.Sequence, ProductId = l.ProductId, CustomerPartNumber = l.CustomerPartNumber, Description = l.Description, Quantity = l.Quantity, Unit = l.Unit, UnitPrice = l.UnitPrice,
                    ListPrice = l.ListPrice, IpiPercent = l.IpiPercent, IcmsPercent = l.IcmsPercent, LeadTimeDays = l.LeadTimeDays, DeliveryDate = l.DeliveryDate
                }).ToList()
            };
            q.NeedsApproval = NeedsApprovalFor(Totals(q), settings);
            var from = old.Status;
            old.Status = QuoteStatus.Cancelled;
            old.DecisionNote = Clean(reason);
            db.Quotes.Add(q);
            await db.SaveChangesAsync(ct);
            // The attached purchase order stays with the cancelled version: the new revision needs its own, and the history says where the old one is.
            var attached = old.RequestFileName is not null || Clean(old.RequestText) is not null ? $" (pedido de compra anterior anexado em {old.Reference})" : "";
            Log(SalesRecordKind.Quote, old.Id, "cancelled", from, old.Status, $"Revisão {q.Reference}: {Clean(reason)}", user);
            Log(SalesRecordKind.Quote, q.Id, "revised", null, q.Status, $"Revisão de {QuoteReference(old.Number, old.Revision, revised: true)}: {Clean(reason)}{attached}", user);
            await db.SaveChangesAsync(ct);
            return q;
        }, ct);
    }

    public Task<Quote> CancelQuoteAsync(int id, string? reason, string? user, CancellationToken ct = default) => QuoteStep(id, "cancelled", reason, user, ct, q =>
    {
        if (!OpenQuote.Contains(q.Status) && q.Status is not (QuoteStatus.Rejected or QuoteStatus.Expired)) throw SalesException.Conflict($"Quote is {q.Status}");
        if (Clean(reason) is null) throw SalesException.Invalid("reason", "Required");
        q.Status = QuoteStatus.Cancelled;
        q.DecisionNote = Clean(reason);
        return Task.FromResult<string?>(null);
    });

    /// <summary>
    /// Copies a quote into a brand-new draft (next number, no revision letter). Prices are kept as quoted; the list price is looked up again for the
    /// (possibly new) customer, so the discount is measured against their price list. Address and contact are cleared when the customer changes.
    /// </summary>
    public async Task<Quote> DuplicateAsync(int id, int? customerId, string? user, CancellationToken ct = default)
    {
        var src = await db.Quotes.AsNoTracking().Include(x => x.Lines).FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw SalesException.NotFound("Quote");
        var customer = customerId ?? src.CustomerId;
        var input = new QuoteInput(customer,
            src.Lines.OrderBy(l => l.Sequence).Select(l => new SalesLineInput(l.ProductId, l.Quantity, l.UnitPrice, l.IpiPercent, l.IcmsPercent, l.LeadTimeDays, null, l.Description)).ToList(),
            customer == src.CustomerId ? src.AddressId : null, src.PaymentTermId, src.Freight, src.ValidityDays,
            customer == src.CustomerId ? src.ContactName : null, customer == src.CustomerId ? src.ContactEmail : null, null, src.Conditions, src.Notes, src.CustomPaymentTerm);
        var q = await CreateQuoteAsync(input, user, ct);
        Log(SalesRecordKind.Quote, q.Id, "duplicated", null, q.Status, $"Cópia de {src.Reference}", user);
        await db.SaveChangesAsync(ct);
        return q;
    }

    public async Task<int> ExpireOverdueAsync(CancellationToken ct = default)
    {
        var today = Today();
        var overdue = await db.Quotes.Where(q => q.Status == QuoteStatus.Sent && q.ValidUntil < today).ToListAsync(ct);
        foreach (var q in overdue)
        {
            q.Status = QuoteStatus.Expired;
            Log(SalesRecordKind.Quote, q.Id, "expired", QuoteStatus.Sent, QuoteStatus.Expired, $"Validade {q.ValidUntil:dd/MM/yyyy}", "system");
        }
        // A discount approval nobody used goes stale: prices and the price list move on, so the quote returns to draft and must be approved again.
        var lapseBefore = DateTimeOffset.UtcNow.AddDays(-(await SettingsAsync(ct)).ApprovalValidityDays);
        var stale = await db.Quotes.Where(q => q.Status == QuoteStatus.Approved && q.ApprovedAt < lapseBefore).ToListAsync(ct);
        foreach (var q in stale)
        {
            q.Status = QuoteStatus.Draft;
            q.ApprovedBy = null;
            q.ApprovedAt = null;
            Log(SalesRecordKind.Quote, q.Id, "approval-lapsed", QuoteStatus.Approved, QuoteStatus.Draft, "Aprovação de desconto vencida sem envio ao cliente", "system");
        }
        if (overdue.Count + stale.Count > 0) await db.SaveChangesAsync(ct);
        return overdue.Count + stale.Count;
    }
}
