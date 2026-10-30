using Ebt.Api.Infrastructure;
using Ebt.Core.Maintenance;

namespace Ebt.Api.Endpoints;

public record DataResetIn(List<ResetScope> Scopes, string? Confirm = null);

public record DataResetOut(IReadOnlyList<ResetTableCount> Tables, long TotalRows);

public static class MaintenanceEndpoints
{
    /// <summary>The word the admin has to type before movement data is deleted.</summary>
    public const string ConfirmWord = "LIMPAR";

    public static void MapMaintenance(this WebApplication app)
    {
        var g = app.MapGroup("/api/admin/data-reset").WithTags("Maintenance").RequireAuthorization(Policies.Admin);

        g.MapPost("/preview", async (DataResetIn i, DataResetService svc, CancellationToken ct) =>
        {
            if (i.Scopes is not { Count: > 0 }) return Results.ValidationProblem(new Dictionary<string, string[]> { ["scopes"] = ["Choose at least one group"] });
            var tables = await svc.PreviewAsync(i.Scopes, ct);
            return Results.Ok(new DataResetOut(tables, tables.Sum(t => t.Rows)));
        });

        g.MapPost("/", async (DataResetIn i, DataResetService svc, CancellationToken ct) =>
        {
            if (i.Scopes is not { Count: > 0 }) return Results.ValidationProblem(new Dictionary<string, string[]> { ["scopes"] = ["Choose at least one group"] });
            if (i.Confirm != ConfirmWord) return Results.ValidationProblem(new Dictionary<string, string[]> { ["confirm"] = [$"Type {ConfirmWord} to confirm"] });
            try
            {
                var tables = await svc.ResetAsync(i.Scopes, ct);
                return Results.Ok(new DataResetOut(tables, tables.Sum(t => t.Rows)));
            }
            catch (DataResetException e)
            {
                return Results.Problem(e.Message, statusCode: StatusCodes.Status409Conflict, title: "Cannot clear data");
            }
        });
    }
}
