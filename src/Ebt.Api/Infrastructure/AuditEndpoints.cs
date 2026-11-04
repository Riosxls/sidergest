using Ebt.Core.Data;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Api.Infrastructure;

public sealed class HttpCurrentUser(IHttpContextAccessor accessor) : ICurrentUser
{
    public string? Name => accessor.HttpContext?.User.Identity?.Name;
}

public record AuditOut(long Id, DateTimeOffset At, string? User, string Entity, string EntityId, string Action, string Changes);

public static class AuditEndpoints
{
    public static void MapAudit(this WebApplication app)
    {
        app.MapGet("/api/audit/actions", async (EbtDbContext db, CancellationToken ct) =>
            Results.Ok(await db.AuditLog.AsNoTracking().Select(a => a.Action).Distinct().OrderBy(a => a).ToListAsync(ct)))
            .WithTags("Audit").RequireAuthorization(Policies.Admin);
        app.MapGet("/api/audit", async (EbtDbContext db, string? entity, string? entityId, string? user, string? action, DateTimeOffset? from, DateTimeOffset? to, int? skip, int? take, CancellationToken ct) =>
        {
            var q = db.AuditLog.AsNoTracking().AsQueryable();
            if (Crud.Has(entity)) q = q.Where(a => a.Entity == entity!.Trim());
            if (Crud.Has(entityId)) q = q.Where(a => a.EntityId == entityId!.Trim());
            if (Crud.Has(user)) q = q.Where(a => a.User == user!.Trim().ToLower());
            if (Crud.Has(action)) { var act = action!.Trim().ToLower(); q = q.Where(a => a.Action.ToLower() == act); }
            if (from is { } f) q = q.Where(a => a.At >= f);
            if (to is { } t) q = q.Where(a => a.At <= t);
            var total = await q.CountAsync(ct);
            var (s, n) = Crud.Paging(skip, take);
            var items = await q.OrderByDescending(a => a.At).ThenByDescending(a => a.Id).Skip(s).Take(n)
                .Select(a => new AuditOut(a.Id, a.At, a.User, a.Entity, a.EntityId, a.Action, a.Changes)).ToListAsync(ct);
            return Results.Ok(new Page<AuditOut>(items, total, s, n));
        }).WithTags("Audit").RequireAuthorization(Policies.Admin);
    }
}
