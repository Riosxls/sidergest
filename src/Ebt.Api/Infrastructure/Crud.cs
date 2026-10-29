using System.Linq.Expressions;
using Ebt.Core.Data;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Api.Infrastructure;

public record Page<T>(IReadOnlyList<T> Items, int Total, int Skip, int Take);

public sealed class CrudSpec<TEntity, TIn, TOut> where TEntity : class
{
    public required Expression<Func<TEntity, TOut>> Project { get; init; }
    public required Func<TIn, TEntity> Create { get; init; }
    public required Action<TIn, TEntity> Apply { get; init; }
    public Func<TIn, EbtDbContext, CancellationToken, Task<Dictionary<string, string[]>>>? Validate { get; init; }
    public Func<IQueryable<TEntity>, string, IQueryable<TEntity>>? Search { get; init; }
    public Func<IQueryable<TEntity>, IQueryable<TEntity>>? Order { get; init; }
    public Func<int, EbtDbContext, CancellationToken, Task<string?>>? BeforeDelete { get; init; }
    public string WritePolicy { get; init; } = Policies.Write;
}

public static class Crud
{
    public static RouteGroupBuilder MapCrud<TEntity, TIn, TOut>(this RouteGroupBuilder group, CrudSpec<TEntity, TIn, TOut> spec)
        where TEntity : class
    {
        group.MapGet("/", async (EbtDbContext db, string? q, int? skip, int? take, CancellationToken ct) =>
        {
            IQueryable<TEntity> query = db.Set<TEntity>().AsNoTracking();
            if (!string.IsNullOrWhiteSpace(q) && spec.Search is not null) query = spec.Search(query, q.Trim());
            var total = await query.CountAsync(ct);
            query = spec.Order is not null ? spec.Order(query) : query.OrderBy(e => EF.Property<int>(e, "Id"));
            var s = Math.Max(skip ?? 0, 0);
            var t = Math.Clamp(take ?? 50, 1, 500);
            var items = await query.Skip(s).Take(t).Select(spec.Project).ToListAsync(ct);
            return Results.Ok(new Page<TOut>(items, total, s, t));
        }).RequireAuthorization(Policies.Read);

        group.MapGet("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
        {
            var item = await db.Set<TEntity>().AsNoTracking().Where(e => EF.Property<int>(e, "Id") == id).Select(spec.Project).FirstOrDefaultAsync(ct);
            return item is null ? Results.NotFound() : Results.Ok(item);
        }).RequireAuthorization(Policies.Read);

        group.MapPost("/", async (TIn input, EbtDbContext db, HttpContext http, CancellationToken ct) =>
        {
            if (spec.Validate is not null)
            {
                var errors = await spec.Validate(input, db, ct);
                if (errors.Count > 0) return Results.ValidationProblem(errors);
            }
            var entity = spec.Create(input);
            db.Add(entity);
            await db.SaveChangesAsync(ct);
            var id = (int)db.Entry(entity).Property("Id").CurrentValue!;
            var dto = await db.Set<TEntity>().AsNoTracking().Where(e => EF.Property<int>(e, "Id") == id).Select(spec.Project).FirstAsync(ct);
            return Results.Created($"{http.Request.Path.Value!.TrimEnd('/')}/{id}", dto);
        }).RequireAuthorization(spec.WritePolicy);

        group.MapPut("/{id:int}", async (int id, TIn input, EbtDbContext db, CancellationToken ct) =>
        {
            var entity = await db.Set<TEntity>().FindAsync([id], ct);
            if (entity is null) return Results.NotFound();
            if (spec.Validate is not null)
            {
                var errors = await spec.Validate(input, db, ct);
                if (errors.Count > 0) return Results.ValidationProblem(errors);
            }
            spec.Apply(input, entity);
            await db.SaveChangesAsync(ct);
            var dto = await db.Set<TEntity>().AsNoTracking().Where(e => EF.Property<int>(e, "Id") == id).Select(spec.Project).FirstAsync(ct);
            return Results.Ok(dto);
        }).RequireAuthorization(spec.WritePolicy);

        group.MapDelete("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
        {
            var entity = await db.Set<TEntity>().FindAsync([id], ct);
            if (entity is null) return Results.NotFound();
            if (spec.BeforeDelete is not null && await spec.BeforeDelete(id, db, ct) is { } reason)
                return Results.Problem(reason, statusCode: StatusCodes.Status409Conflict);
            db.Remove(entity);
            await db.SaveChangesAsync(ct);
            return Results.NoContent();
        }).RequireAuthorization(spec.WritePolicy);

        return group;
    }

    public static Dictionary<string, string[]> Errors() => new();

    public static Dictionary<string, string[]> Require(this Dictionary<string, string[]> errors, bool condition, string field, string message)
    {
        if (!condition) errors[field] = errors.TryGetValue(field, out var existing) ? [.. existing, message] : [message];
        return errors;
    }

    /// <summary>Contains-pattern for ILIKE with the caller's own wildcard characters escaped (backslash is the default escape).</summary>
    public static string Like(string value) => "%" + value.Trim().Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_") + "%";

    public static bool Has(string? value) => !string.IsNullOrWhiteSpace(value);
    public static bool Digits(string? value, params int[] lengths) => Numeric(value) is { } v && v.All(char.IsDigit) && lengths.Contains(v.Length);
    public static string? Numeric(string? value) => Clean(value) is { } v && string.Concat(v.Where(c => c is not ('.' or '-' or '/' or ' '))) is { Length: > 0 } n ? n : null;
    public static string? Clean(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
