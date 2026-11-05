using System.Text.Json;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Sales;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public sealed record PriceSimulationIn(string? Shape, decimal? Diameter, decimal? Width, decimal? Height, decimal? Thickness, decimal? Length, string? Spec, decimal? Quantity, int? CustomerId, string? CustomerName,
    decimal? MarkupPercent, decimal? CostPerKg, decimal? PricePerKg, decimal? PricePerPiece, string? Basis, string? Confidence, string? Reason, string? Note, bool UsedInQuote);

public sealed record PriceSimulationOut(int Id, DateTimeOffset CreatedAt, string? CreatedBy, string Shape, decimal? Diameter, decimal? Width, decimal? Height, decimal? Thickness, decimal? Length, string? Spec, decimal? Quantity,
    int? CustomerId, string? CustomerName, decimal? MarkupPercent, decimal? CostPerKg, decimal PricePerKg, decimal? PricePerPiece, string Basis, string Confidence, string? Reason, string? Note, bool UsedInQuote);

/// <summary>Price suggestion for a tube of given dimensions, the import of the legacy price history that feeds it and the saved simulations. Prices are sensitive: read-only roles get 403.</summary>
public static class PriceSuggestionEndpoints
{
    private const long MaxImportBytes = 20 * 1024 * 1024;
    private static readonly string[] Shapes = ["Round", "Oblong", "Rectangular"];

    private static bool IsManager(System.Security.Claims.ClaimsPrincipal user) => user.IsInRole(nameof(UserRole.Admin)) || user.IsInRole(nameof(UserRole.SalesManager));

    public static void MapPriceSuggestion(this WebApplication app)
    {
        var g = app.MapGroup("/api/sales").WithTags("Sales");

        // shape=round (default): diameter, thickness, length. shape=oblong: width (long outside side), height (short outside side), thickness, length.
        // shape=rect: width and height (outside sides, either order), thickness, length.
        g.MapGet("/price-suggestion", async (PriceSuggestionService svc, decimal? diameter, decimal? thickness, decimal? length, int? customerId, decimal? quantity, int? productId, string? spec,
            string? shape, decimal? width, decimal? height, CancellationToken ct) =>
        {
            var oblong = string.Equals(shape, "oblong", StringComparison.OrdinalIgnoreCase);
            var rect = string.Equals(shape, "rect", StringComparison.OrdinalIgnoreCase) || string.Equals(shape, "rectangular", StringComparison.OrdinalIgnoreCase);
            if (!oblong && !rect && !string.IsNullOrWhiteSpace(shape) && !string.Equals(shape, "round", StringComparison.OrdinalIgnoreCase))
                return Results.ValidationProblem(Errors().Require(false, "shape", "Use round, oblong or rect"));
            var errors = Errors()
                .Require(thickness is > 0, "thickness", "Must be greater than zero")
                .Require(length is > 0, "length", "Must be greater than zero");
            if (oblong)
            {
                errors.Require(width is > 0, "width", "Must be greater than zero").Require(height is > 0, "height", "Must be greater than zero");
                if (errors.Count == 0) errors.Require(width!.Value >= height!.Value, "width", "The width is the long side: it cannot be smaller than the height");
                if (errors.Count == 0) errors.Require(thickness!.Value * 2 < height!.Value, "thickness", "Wall must be less than half the short side");
            }
            else if (rect)
            {
                errors.Require(width is > 0, "width", "Must be greater than zero").Require(height is > 0, "height", "Must be greater than zero");
                if (errors.Count == 0) errors.Require(thickness!.Value * 2 < Math.Min(width!.Value, height!.Value), "thickness", "Wall must be less than half the short side");
            }
            else
            {
                errors.Require(diameter is > 0, "diameter", "Must be greater than zero");
                if (errors.Count == 0) errors.Require(thickness!.Value * 2 < diameter!.Value, "thickness", "Wall must be less than half the diameter");
            }
            if (quantity is < 0) errors.Require(false, "quantity", "Cannot be negative");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            return Results.Ok(oblong
                ? await svc.SuggestOblongAsync(width!.Value, height!.Value, thickness!.Value, length!.Value, customerId, quantity, productId, spec, ct)
                : rect
                    ? await svc.SuggestRectangularAsync(width!.Value, height!.Value, thickness!.Value, length!.Value, customerId, quantity, productId, spec, ct)
                    : await svc.SuggestAsync(diameter!.Value, thickness!.Value, length!.Value, customerId, quantity, productId, spec, ct));
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

        // Saved simulations (reference data: the data reset leaves them alone).
        g.MapPost("/price-simulations", async (PriceSimulationIn i, EbtDbContext db, System.Security.Claims.ClaimsPrincipal user, CancellationToken ct) =>
        {
            var shape = Shapes.FirstOrDefault(s => string.Equals(s, i.Shape?.Trim(), StringComparison.OrdinalIgnoreCase));
            var errors = Errors()
                .Require(shape is not null, "shape", "Use Round, Oblong or Rectangular")
                .Require(i.Thickness is > 0, "thickness", "Must be greater than zero")
                .Require(i.Length is > 0, "length", "Must be greater than zero")
                .Require(i.PricePerKg is >= 0, "pricePerKg", "Must be zero or more")
                .Require(i.PricePerPiece is null or >= 0, "pricePerPiece", "Cannot be negative")
                .Require(i.CostPerKg is null or >= 0, "costPerKg", "Cannot be negative")
                .Require(i.Quantity is null or >= 0, "quantity", "Cannot be negative")
                .Require(!string.IsNullOrWhiteSpace(i.Basis) && i.Basis.Length <= 20, "basis", "Required, up to 20 characters")
                .Require(!string.IsNullOrWhiteSpace(i.Confidence) && i.Confidence.Length <= 10, "confidence", "Required, up to 10 characters")
                .Require((i.Spec?.Length ?? 0) <= 60, "spec", "Up to 60 characters")
                .Require((i.CustomerName?.Length ?? 0) <= 200, "customerName", "Up to 200 characters")
                .Require((i.Reason?.Length ?? 0) <= 500, "reason", "Up to 500 characters")
                .Require((i.Note?.Length ?? 0) <= 1000, "note", "Up to 1000 characters");
            if (shape == "Round") errors.Require(i.Diameter is > 0, "diameter", "Must be greater than zero");
            else if (shape is not null) errors.Require(i.Width is > 0, "width", "Must be greater than zero").Require(i.Height is > 0, "height", "Must be greater than zero");
            if (errors.Count > 0) return Results.ValidationProblem(errors);

            var sim = new PriceSimulation
            {
                CreatedAt = DateTimeOffset.UtcNow, CreatedBy = user.Identity?.Name, Shape = shape!,
                DiameterMm = i.Diameter, WidthMm = i.Width, HeightMm = i.Height, ThicknessMm = i.Thickness, LengthMm = i.Length,
                Spec = Clean(i.Spec), Quantity = i.Quantity, CustomerId = i.CustomerId, CustomerName = Clean(i.CustomerName),
                MarkupPercent = i.MarkupPercent, CostPerKg = i.CostPerKg, PricePerKg = i.PricePerKg!.Value, PricePerPiece = i.PricePerPiece,
                Basis = i.Basis!.Trim(), Confidence = i.Confidence!.Trim(), Reason = Clean(i.Reason), Note = Clean(i.Note), UsedInQuote = i.UsedInQuote
            };
            db.PriceSimulations.Add(sim);
            await db.SaveChangesAsync(ct);
            db.AuditLog.Add(new AuditEntry
            {
                At = DateTimeOffset.UtcNow, User = user.Identity?.Name, Entity = nameof(PriceSimulation), EntityId = sim.Id.ToString(), Action = "Create",
                Changes = JsonSerializer.Serialize(new { sim.Shape, diameter = sim.DiameterMm, width = sim.WidthMm, height = sim.HeightMm, thickness = sim.ThicknessMm, length = sim.LengthMm, sim.CustomerName, sim.PricePerKg, sim.Basis, sim.UsedInQuote })
            });
            await db.SaveChangesAsync(ct);
            return Results.Created($"/api/sales/price-simulations/{sim.Id}", new { id = sim.Id });
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapGet("/price-simulations", async (EbtDbContext db, int? take, CancellationToken ct) =>
        {
            var n = Math.Clamp(take ?? 20, 1, 100);
            var items = await db.PriceSimulations.AsNoTracking().OrderByDescending(s => s.CreatedAt).ThenByDescending(s => s.Id).Take(n)
                .Select(s => new PriceSimulationOut(s.Id, s.CreatedAt, s.CreatedBy, s.Shape, s.DiameterMm, s.WidthMm, s.HeightMm, s.ThicknessMm, s.LengthMm, s.Spec, s.Quantity, s.CustomerId, s.CustomerName,
                    s.MarkupPercent, s.CostPerKg, s.PricePerKg, s.PricePerPiece, s.Basis, s.Confidence, s.Reason, s.Note, s.UsedInQuote)).ToListAsync(ct);
            return Results.Ok(items);
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapDelete("/price-simulations/{id:int}", async (int id, EbtDbContext db, System.Security.Claims.ClaimsPrincipal user, CancellationToken ct) =>
        {
            var sim = await db.PriceSimulations.FirstOrDefaultAsync(s => s.Id == id, ct);
            if (sim is null) return Results.NotFound();
            if (!IsManager(user) && !string.Equals(sim.CreatedBy, user.Identity?.Name, StringComparison.Ordinal))
                return Results.Problem("Only the person who saved a simulation (or a manager) can delete it", statusCode: StatusCodes.Status403Forbidden);
            db.PriceSimulations.Remove(sim);
            db.AuditLog.Add(new AuditEntry { At = DateTimeOffset.UtcNow, User = user.Identity?.Name, Entity = nameof(PriceSimulation), EntityId = id.ToString(), Action = "Delete", Changes = JsonSerializer.Serialize(new { sim.Shape, sim.CustomerName, sim.PricePerKg }) });
            await db.SaveChangesAsync(ct);
            return Results.NoContent();
        }).RequireAuthorization(SalesPolicies.Sell);
    }

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}
