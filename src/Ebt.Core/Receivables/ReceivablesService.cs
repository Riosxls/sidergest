using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Receivables;

public enum ReceivableStatus { Open, Partial, Paid, Overdue, Cancelled }

/// <summary>One duplicata with what was paid. Status is derived: Cancelled when its NF was cancelled, Paid when nothing is left, Overdue when a balance is past due.</summary>
public sealed class ReceivableRow
{
    public int Id { get; set; }
    public int DocumentId { get; set; }
    public int Number { get; set; }
    public int Series { get; set; }
    public int? CustomerId { get; set; }
    public string CustomerName { get; set; } = "";
    public int Sequence { get; set; }
    public int Count { get; set; }
    public DateOnly DueDate { get; set; }
    public decimal Amount { get; set; }
    public decimal Paid { get; set; }
    public bool NfCancelled { get; set; }
    public decimal Balance => NfCancelled ? 0m : Math.Max(0m, Amount - Paid);

    public ReceivableStatus StatusOn(DateOnly today) =>
        NfCancelled ? ReceivableStatus.Cancelled
        : Paid >= Amount ? ReceivableStatus.Paid
        : DueDate < today ? ReceivableStatus.Overdue
        : Paid > 0 ? ReceivableStatus.Partial : ReceivableStatus.Open;
}

public sealed record ReceivableFilter(int? CustomerId = null, string? Status = null, DateOnly? DueFrom = null, DateOnly? DueTo = null, bool OverdueOnly = false, int? Number = null);

public sealed record CustomerBalance(int CustomerId, string CustomerName, decimal Open, decimal Overdue, DateOnly? NextDue);

/// <summary>Balances by days past due. NotDue is what still has time; the others count days since the due date.</summary>
public sealed record AgingRow(int? CustomerId, string CustomerName, decimal NotDue, decimal Days1To30, decimal Days31To60, decimal Days61To90, decimal Over90, decimal Total);

public sealed record PostPayment(DateOnly? PaidOn, decimal Amount, string? Method = null, string? Notes = null);

/// <summary>
/// Contas a receber: the duplicatas of authorized sale NFs, payments posted against them (baixa) and reversals (estorno).
/// Balances are computed from the payments and the NF status, nothing is stored on the installment, so a cancelled NF stops counting at once.
/// </summary>
public sealed class ReceivablesService(EbtDbContext db)
{
    /// <summary>Duplicatas that exist for the books: sale NFs that are Authorized (live) or Cancelled (shown as such). Pending and Rejected NFs never count.</summary>
    public IQueryable<ReceivableRow> Rows() =>
        db.FiscalInstallments.AsNoTracking()
            .Where(i => i.Document!.Kind == FiscalKind.Sale && (i.Document.Status == FiscalStatus.Authorized || i.Document.Status == FiscalStatus.Cancelled))
            .Select(i => new ReceivableRow
            {
                Id = i.Id, DocumentId = i.DocumentId, Number = i.Document!.Number, Series = i.Document.Series, CustomerId = i.Document.CustomerId, CustomerName = i.Document.RecipientName,
                Sequence = i.Sequence, Count = i.Document.Installments.Count, DueDate = i.DueDate, Amount = i.Amount,
                Paid = i.Payments.Where(p => p.ReversedAt == null).Sum(p => (decimal?)p.Amount) ?? 0m,
                NfCancelled = i.Document.Status == FiscalStatus.Cancelled
            });

    public IQueryable<ReceivableRow> Filtered(ReceivableFilter f, DateOnly today)
    {
        var q = Rows();
        if (f.CustomerId is { } c) q = q.Where(r => r.CustomerId == c);
        if (f.Number is { } n) q = q.Where(r => r.Number == n);
        if (f.DueFrom is { } from) q = q.Where(r => r.DueDate >= from);
        if (f.DueTo is { } to) q = q.Where(r => r.DueDate <= to);
        if (f.OverdueOnly) q = q.Where(r => !r.NfCancelled && r.Paid < r.Amount && r.DueDate < today);
        return f.Status?.ToLowerInvariant() switch
        {
            "open" => q.Where(r => !r.NfCancelled && r.Paid == 0 && r.DueDate >= today),
            "partial" => q.Where(r => !r.NfCancelled && r.Paid > 0 && r.Paid < r.Amount && r.DueDate >= today),
            "paid" => q.Where(r => !r.NfCancelled && r.Paid >= r.Amount),
            "overdue" => q.Where(r => !r.NfCancelled && r.Paid < r.Amount && r.DueDate < today),
            "cancelled" => q.Where(r => r.NfCancelled),
            "pending" => q.Where(r => !r.NfCancelled && r.Paid < r.Amount),
            null or "" => q,
            _ => throw FiscalException.Invalid("status", "Use open, partial, paid, overdue, cancelled or pending")
        };
    }

    /// <summary>What the customer still owes on authorized NFs (also what the credit check adds to the order exposure).</summary>
    public async Task<decimal> OpenBalanceAsync(int customerId, CancellationToken ct = default) =>
        Math.Max(0m, await db.FiscalInstallments.AsNoTracking()
            .Where(i => i.Document!.Kind == FiscalKind.Sale && i.Document.Status == FiscalStatus.Authorized && i.Document.CustomerId == customerId)
            .SumAsync(i => (decimal?)(i.Amount - (i.Payments.Where(p => p.ReversedAt == null).Sum(p => (decimal?)p.Amount) ?? 0m)), ct) ?? 0m);

    public async Task<IReadOnlyList<CustomerBalance>> BalancesAsync(int? customerId, CancellationToken ct = default)
    {
        var today = Clock.Today();
        var q = Rows().Where(r => !r.NfCancelled && r.Paid < r.Amount && r.CustomerId != null);
        if (customerId is { } c) q = q.Where(r => r.CustomerId == c);
        var rows = await q.Select(r => new { r.CustomerId, r.CustomerName, r.DueDate, Balance = r.Amount - r.Paid }).ToListAsync(ct);
        return rows.GroupBy(r => r.CustomerId!.Value).Select(g => new CustomerBalance(g.Key, g.First().CustomerName, g.Sum(r => r.Balance),
            g.Where(r => r.DueDate < today).Sum(r => r.Balance), (DateOnly?)g.Min(r => r.DueDate))).OrderByDescending(b => b.Overdue).ThenByDescending(b => b.Open).ToList();
    }

    public async Task<IReadOnlyList<AgingRow>> AgingAsync(int? customerId, CancellationToken ct = default)
    {
        var today = Clock.Today();
        var q = Rows().Where(r => !r.NfCancelled && r.Paid < r.Amount);
        if (customerId is { } c) q = q.Where(r => r.CustomerId == c);
        var rows = await q.Select(r => new { r.CustomerId, r.CustomerName, r.DueDate, Balance = r.Amount - r.Paid }).ToListAsync(ct);
        AgingRow Sum(int? id, string name, IEnumerable<(DateOnly Due, decimal Balance)> items)
        {
            decimal b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0;
            foreach (var (due, bal) in items)
            {
                var late = today.DayNumber - due.DayNumber;
                if (late <= 0) b0 += bal; else if (late <= 30) b1 += bal; else if (late <= 60) b2 += bal; else if (late <= 90) b3 += bal; else b4 += bal;
            }
            return new AgingRow(id, name, b0, b1, b2, b3, b4, b0 + b1 + b2 + b3 + b4);
        }
        var perCustomer = rows.GroupBy(r => r.CustomerId).Select(g => Sum(g.Key, g.First().CustomerName, g.Select(r => (r.DueDate, r.Balance)))).OrderByDescending(a => a.Total).ToList();
        perCustomer.Add(Sum(null, "Total", rows.Select(r => (r.DueDate, r.Balance))));
        return perCustomer;
    }

    /// <summary>Posts a payment. Partial amounts are allowed; the amount may not exceed the balance. The installment row is locked so two postings cannot overpay it.</summary>
    public async Task<ReceivablePayment> PostAsync(int installmentId, PostPayment i, string? user, CancellationToken ct = default)
    {
        var today = Clock.Today();
        var amount = Math.Round(i.Amount, 2, MidpointRounding.AwayFromZero);
        if (amount <= 0) throw FiscalException.Invalid("amount", "Must be greater than zero");
        var paidOn = i.PaidOn ?? today;
        if (paidOn > today) throw FiscalException.Invalid("paidOn", "Cannot be in the future");
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        await db.Database.ExecuteSqlInterpolatedAsync($"select 1 from fiscal_installments where id = {installmentId} for update", ct);
        var row = await Rows().FirstOrDefaultAsync(r => r.Id == installmentId, ct) ?? throw FiscalException.NotFound("Duplicata");
        if (row.NfCancelled) throw FiscalException.Conflict($"NF {row.Number} was cancelled; its duplicatas cannot receive payments");
        if (amount > row.Balance) throw FiscalException.Conflict($"The amount ({amount:0.00}) is larger than the balance ({row.Balance:0.00})");
        var p = new ReceivablePayment { InstallmentId = installmentId, PaidOn = paidOn, Amount = amount, Method = Clean(i.Method), Notes = Clean(i.Notes), CreatedAt = DateTimeOffset.UtcNow, CreatedBy = user };
        db.ReceivablePayments.Add(p);
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        return p;
    }

    /// <summary>Reverses a payment (estorno): the row stays for the history, stops counting, and the change is audited.</summary>
    public async Task ReverseAsync(int paymentId, string? reason, string? user, CancellationToken ct = default)
    {
        if (Clean(reason) is not { } why) throw FiscalException.Invalid("reason", "Required");
        var p = await db.ReceivablePayments.FirstOrDefaultAsync(x => x.Id == paymentId, ct) ?? throw FiscalException.NotFound("Pagamento");
        if (p.ReversedAt is not null) throw FiscalException.Conflict("This payment was already reversed");
        p.ReversedAt = DateTimeOffset.UtcNow;
        p.ReversedBy = user;
        p.ReverseReason = why;
        await db.SaveChangesAsync(ct);
    }

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}
