using static Ebt.Core.Services.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
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
}
