using Ebt.Core.Data;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Api.Infrastructure;

/// <summary>
/// Optimistic concurrency over HTTP for routes shaped like .../{id}[/action]. Responses carry the row's Postgres xmin as an ETag;
/// a write that sends a stale If-Match is rejected with 412 before the handler runs.
/// </summary>
public sealed class RowVersionFilter<TEntity> : IEndpointFilter where TEntity : class
{
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext ctx, EndpointFilterDelegate next)
    {
        var http = ctx.HttpContext;
        if (!int.TryParse(http.Request.RouteValues["id"]?.ToString(), out var id)) return await next(ctx);
        var db = http.RequestServices.GetRequiredService<EbtDbContext>();

        var ifMatch = http.Request.Headers.IfMatch.ToString();
        if (!HttpMethods.IsGet(http.Request.Method) && !string.IsNullOrWhiteSpace(ifMatch) && ifMatch != "*")
        {
            var current = await VersionAsync(db, id, http.RequestAborted);
            if (current is { } v && Tag(v) != ifMatch.Trim())
                return Results.Problem("The record was changed by someone else; reload and try again", statusCode: StatusCodes.Status412PreconditionFailed, title: "Stale version");
        }

        var result = await next(ctx);
        if (await VersionAsync(db, id, http.RequestAborted) is { } after) http.Response.Headers.ETag = Tag(after);
        return result;
    }

    private static string Tag(uint version) => $"\"{version}\"";

    private static async Task<uint?> VersionAsync(EbtDbContext db, int id, CancellationToken ct) =>
        await db.Set<TEntity>().AsNoTracking().Where(e => EF.Property<int>(e, "Id") == id).Select(e => (uint?)EF.Property<uint>(e, "xmin")).FirstOrDefaultAsync(ct);
}
