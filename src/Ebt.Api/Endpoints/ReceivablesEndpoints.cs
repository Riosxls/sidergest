using System.Security.Claims;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Receivables;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record ReceivableOut(int Id, int DocumentId, int Number, int Series, int? CustomerId, string CustomerName, int Sequence, int Count, DateOnly DueDate, decimal Amount, decimal Paid, decimal Balance, ReceivableStatus Status, int DaysOverdue);
public record ReceivablePaymentIn(DateOnly? PaidOn, decimal Amount, string? Method, string? Notes);
public record ReceivablePaymentOut(int Id, int InstallmentId, DateOnly PaidOn, decimal Amount, string? Method, string? Notes, DateTimeOffset CreatedAt, string? CreatedBy, DateTimeOffset? ReversedAt, string? ReversedBy, string? ReverseReason);

public static class ReceivablePolicies
{
    /// <summary>Post and reverse payments on duplicatas. Reading follows the read policy.</summary>
    public const string Post = "receivables-post";
}

public static class ReceivablesEndpoints
{
    public static void MapReceivables(this WebApplication app)
    {
        var g = app.MapGroup("/api/receivables").WithTags("Receivables").RequireAuthorization(Policies.Read);

        g.MapGet("/", async (ReceivablesService svc, int? customerId, string? status, DateOnly? dueFrom, DateOnly? dueTo, bool? overdue, string? q, int? skip, int? take, CancellationToken ct) =>
        {
            var today = Clock.Today();
            var rows = svc.Filtered(new ReceivableFilter(customerId, status, dueFrom, dueTo, overdue == true), today);
            if (Has(q)) rows = rows.Where(r => EF.Functions.ILike(r.CustomerName, Like(q!)) || r.Number.ToString() == q.Trim());
            var total = await rows.CountAsync(ct);
            var sk = Math.Max(skip ?? 0, 0);
            var tk = Math.Clamp(take ?? 50, 1, 200);
            var items = await rows.OrderBy(r => r.DueDate).ThenBy(r => r.Number).ThenBy(r => r.Sequence).Skip(sk).Take(tk).ToListAsync(ct);
            return Results.Ok(new Page<ReceivableOut>(items.Select(r => ToOut(r, today)).ToList(), total, sk, tk));
        });

        // Open and overdue balance per customer; the customer screen reads its own row.
        g.MapGet("/balances", async (ReceivablesService svc, int? customerId, CancellationToken ct) => Results.Ok(await svc.BalancesAsync(customerId, ct)));

        // Rows per customer plus a last row (customerId null, name "Total") with the sums.
        g.MapGet("/aging", async (ReceivablesService svc, int? customerId, CancellationToken ct) => Results.Ok(await svc.AgingAsync(customerId, ct)));

        g.MapGet("/installments/{id:int}/payments", async (int id, EbtDbContext db, CancellationToken ct) =>
            Results.Ok(await db.ReceivablePayments.AsNoTracking().Where(p => p.InstallmentId == id).OrderBy(p => p.PaidOn).ThenBy(p => p.Id)
                .Select(p => new ReceivablePaymentOut(p.Id, p.InstallmentId, p.PaidOn, p.Amount, p.Method, p.Notes, p.CreatedAt, p.CreatedBy, p.ReversedAt, p.ReversedBy, p.ReverseReason)).ToListAsync(ct)));

        g.MapPost("/installments/{id:int}/payments", async (int id, ReceivablePaymentIn i, ReceivablesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var p = await svc.PostAsync(id, new PostPayment(i.PaidOn, i.Amount, i.Method, i.Notes), user.Identity?.Name, ct);
            return Results.Ok(new ReceivablePaymentOut(p.Id, p.InstallmentId, p.PaidOn, p.Amount, p.Method, p.Notes, p.CreatedAt, p.CreatedBy, p.ReversedAt, p.ReversedBy, p.ReverseReason));
        }).RequireAuthorization(ReceivablePolicies.Post);

        // Estorno: the payment stays in the history, flagged as reversed, and the change is audited.
        g.MapDelete("/payments/{id:int}", async (int id, string? reason, ReceivablesService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.ReverseAsync(id, reason, user.Identity?.Name, ct);
            return Results.NoContent();
        }).RequireAuthorization(ReceivablePolicies.Post);
    }

    private static ReceivableOut ToOut(ReceivableRow r, DateOnly today) =>
        new(r.Id, r.DocumentId, r.Number, r.Series, r.CustomerId, r.CustomerName, r.Sequence, r.Count, r.DueDate, r.Amount, r.Paid, r.Balance, r.StatusOn(today),
            r.Balance > 0 && r.DueDate < today ? today.DayNumber - r.DueDate.DayNumber : 0);
}
