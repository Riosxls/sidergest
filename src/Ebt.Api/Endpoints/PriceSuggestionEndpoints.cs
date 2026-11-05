using System.Text.Json;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Sales;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

/// <summary>Price suggestion for a tube of given dimensions and the import of the legacy price history that feeds it. Prices are sensitive: read-only roles get 403.</summary>
public static class PriceSuggestionEndpoints
{
    private const long MaxImportBytes = 20 * 1024 * 1024;

    public static void MapPriceSuggestion(this WebApplication app)
    {
        var g = app.MapGroup("/api/sales").WithTags("Sales");

        g.MapGet("/price-suggestion", async (PriceSuggestionService svc, decimal? diameter, decimal? thickness, decimal? length, int? customerId, decimal? quantity, int? productId, string? spec, CancellationToken ct) =>
        {
            var errors = Errors()
                .Require(diameter is > 0, "diameter", "Must be greater than zero")
                .Require(thickness is > 0, "thickness", "Must be greater than zero")
                .Require(length is > 0, "length", "Must be greater than zero");
            if (errors.Count == 0) errors.Require(thickness!.Value * 2 < diameter!.Value, "thickness", "Wall must be less than half the diameter");
            if (quantity is < 0) errors.Require(false, "quantity", "Cannot be negative");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            return Results.Ok(await svc.SuggestAsync(diameter!.Value, thickness!.Value, length!.Value, customerId, quantity, productId, spec, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapGet("/price-history/summary", async (PriceSuggestionService svc, CancellationToken ct) => Results.Ok(await svc.SummaryAsync(ct)))
            .RequireAuthorization(SalesPolicies.Sell);

        g.MapPost("/price-history/import", async (IFormFile file, PriceHistoryImporter importer, EbtDbContext db, System.Security.Claims.ClaimsPrincipal user, CancellationToken ct) =>
        {
            if (file.Length is 0 or > MaxImportBytes) return Results.BadRequest(new { message = "Arquivo vazio ou maior que 20 MB", field = "file" });
            await using var ms = new MemoryStream();
            await file.CopyToAsync(ms, ct);
            var result = await importer.ImportAsync(ms.ToArray(), ct);
            db.AuditLog.Add(new AuditEntry
            {
                At = DateTimeOffset.UtcNow, User = user.Identity?.Name, Entity = "PriceHistory", EntityId = "import", Action = "Import",
                Changes = JsonSerializer.Serialize(new { file = Path.GetFileName(file.FileName), result.Read, result.Imported, result.Updated, result.Duplicates, result.Skipped })
            });
            await db.SaveChangesAsync(ct);
            return Results.Ok(result);
        }).RequireAuthorization(SalesPolicies.PriceEdit).DisableAntiforgery();
    }
}
