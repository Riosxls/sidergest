using System.Security.Claims;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Sales;
using Ebt.Core.Viability;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record FeasibilityIn(int CustomerId, string Title, int? QuoteId = null, int? ProductId = null, string? Characteristics = null, string? Transformations = null, string? Finishing = null,
    string? Packaging = null, decimal? MonthlyConsumptionKg = null, int? OrdersAllowed = null);
public record FeasibilityNoteIn(string? Note = null);
public record SignoffOut(SignoffArea Area, string? By, DateTimeOffset? At, string? Note);
public record FeasibilityOrderOut(int OrderId, string Reference, SalesOrderStatus Status);
public record FeasibilitySummaryOut(int Id, int Number, string Reference, int? QuoteId, string? QuoteReference, int CustomerId, string CustomerName, int? ProductId, string? ProductCode, string Title,
    FeasibilityStatus Status, int Signed, int OrdersAllowed, int OrdersUsed, decimal? MonthlyConsumptionKg, DateTimeOffset CreatedAt);
public record FeasibilityOut(int Id, int Number, string Reference, int? QuoteId, string? QuoteReference, int CustomerId, string CustomerName, int? ProductId, string? ProductCode, string? ProductName, string Title,
    string? Characteristics, string? Transformations, string? Finishing, string? Packaging, decimal? MonthlyConsumptionKg, FeasibilityStatus Status, string? RejectionReason,
    int OrdersAllowed, int OrdersUsed, int OrdersRemaining, IReadOnlyList<SignoffOut> Signoffs, IReadOnlyList<FeasibilityOrderOut> Orders, string? CreatedBy, DateTimeOffset CreatedAt, IReadOnlyList<SalesEventOut> History);

public static class ViabilityPolicies
{
    public const string Quality = "viability-quality";
    public const string Production = "viability-production";
    public const string Commercial = "viability-commercial";

    public static string For(SignoffArea a) => a switch { SignoffArea.Quality => Quality, SignoffArea.Production => Production, _ => Commercial };
}

public static class ViabilityEndpoints
{
    public static IServiceCollection AddViability(this IServiceCollection services)
    {
        return services;
    }

    private static string? Who(ClaimsPrincipal user) => user.Identity?.Name;

    public static void MapViability(this WebApplication app)
    {
        var g = app.MapGroup("/api/viability").WithTags("Viability").RequireAuthorization(Policies.Read).AddEndpointFilter(new RowVersionFilter<FeasibilityStudy>());

        g.MapGet("/", async (EbtDbContext db, FeasibilityStatus? status, int? customerId, int? quoteId, int? productId, bool? usable, string? q, int? skip, int? take, CancellationToken ct) =>
        {
            var x = db.FeasibilityStudies.AsNoTracking();
            if (status is { } st) x = x.Where(f => f.Status == st);
            if (customerId is { } c) x = x.Where(f => f.CustomerId == c);
            if (quoteId is { } qi) x = x.Where(f => f.QuoteId == qi);
            if (productId is { } pi) x = x.Where(f => f.ProductId == pi || f.ProductId == null);
            if (Has(q)) x = x.Where(f => EF.Functions.ILike(f.Reference, Like(q!)) || EF.Functions.ILike(f.Title, Like(q)) || EF.Functions.ILike(f.Customer!.Name, Like(q)));
            var rows = await x.OrderByDescending(f => f.Number).Select(f => new { F = f, Customer = f.Customer!.Name, Quote = f.Quote == null ? null : f.Quote.Reference, Product = f.Product == null ? null : f.Product.Code }).ToListAsync(ct);
            var used = await ViabilityRules.UsedOrdersAsync(db, rows.Select(r => r.F.Id).ToList(), null, ct);
            var items = rows.Select(r => new FeasibilitySummaryOut(r.F.Id, r.F.Number, r.F.Reference, r.F.QuoteId, r.Quote, r.F.CustomerId, r.Customer, r.F.ProductId, r.Product, r.F.Title, r.F.Status,
                Signed(r.F), r.F.OrdersAllowed, used.GetValueOrDefault(r.F.Id), r.F.MonthlyConsumptionKg, r.F.CreatedAt));
            if (usable == true) items = items.Where(i => i.Status == FeasibilityStatus.Approved && i.OrdersUsed < i.OrdersAllowed);
            var list = items.ToList();
            var s = Math.Max(skip ?? 0, 0);
            var n = Math.Clamp(take ?? 50, 1, 500);
            return Results.Ok(new Page<FeasibilitySummaryOut>(list.Skip(s).Take(n).ToList(), list.Count, s, n));
        });

        g.MapGet("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
            await db.FeasibilityStudies.AnyAsync(f => f.Id == id, ct) ? Results.Ok(await Load(db, id, ct)) : Results.NotFound());

        g.MapPost("/", async (FeasibilityIn i, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await Validate(db, i, ct);
            var number = await db.Database.SqlQueryRaw<int>($"SELECT nextval('{EbtDbContext.FeasibilityNumbers}')::int AS \"Value\"").SingleAsync(ct);
            var f = new FeasibilityStudy { Number = number, Reference = $"FAV {number}", Title = i.Title.Trim(), CustomerId = i.CustomerId, Status = FeasibilityStatus.Draft, CreatedBy = Who(user), CreatedAt = DateTimeOffset.UtcNow };
            Apply(i, f);
            db.FeasibilityStudies.Add(f);
            await db.SaveChangesAsync(ct);
            Log(db, f.Id, "created", null, f.Status, null, Who(user));
            await db.SaveChangesAsync(ct);
            return Results.Created($"/api/viability/{f.Id}", await Load(db, f.Id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapPut("/{id:int}", async (int id, FeasibilityIn i, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var f = await db.FeasibilityStudies.FindAsync([id], ct);
            if (f is null) return Results.NotFound();
            if (f.Status is not (FeasibilityStatus.Draft or FeasibilityStatus.Rejected)) throw SalesException.Conflict($"Study is {f.Status}; reopen it to edit");
            if (f.CustomerId != i.CustomerId) throw SalesException.Invalid("customerId", "The customer cannot change");
            await Validate(db, i, ct);
            var from = f.Status;
            Apply(i, f);
            f.Title = i.Title.Trim();
            f.Status = FeasibilityStatus.Draft;
            f.RejectionReason = null;
            ClearSignoffs(f);
            Log(db, f.Id, "edited", from, f.Status, null, Who(user));
            await db.SaveChangesAsync(ct);
            return Results.Ok(await Load(db, id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapPost("/{id:int}/submit", async (int id, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var f = await db.FeasibilityStudies.FindAsync([id], ct);
            if (f is null) return Results.NotFound();
            if (f.Status != FeasibilityStatus.Draft) throw SalesException.Conflict($"Study is {f.Status}");
            if (!Has(f.Characteristics)) throw SalesException.Invalid("characteristics", "Describe the characteristics before sending to review");
            f.Status = FeasibilityStatus.InReview;
            Log(db, id, "submitted", FeasibilityStatus.Draft, f.Status, null, Who(user));
            await db.SaveChangesAsync(ct);
            return Results.Ok(await Load(db, id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        foreach (var area in Enum.GetValues<SignoffArea>())
        {
            var slug = area.ToString().ToLowerInvariant();
            g.MapPost($"/{{id:int}}/sign/{slug}", async (int id, FeasibilityNoteIn i, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
            {
                var f = await db.FeasibilityStudies.FindAsync([id], ct);
                if (f is null) return Results.NotFound();
                if (f.Status != FeasibilityStatus.InReview) throw SalesException.Conflict($"Study is {f.Status}; it must be in review to sign");
                if (SignedAt(f, area) is not null) throw SalesException.Conflict($"{area} already signed");
                SetSignoff(f, area, Who(user), DateTimeOffset.UtcNow, Clean(i.Note));
                var from = f.Status;
                if (Signed(f) == 3) f.Status = FeasibilityStatus.Approved;
                Log(db, id, $"signed-{slug}", from, f.Status, Clean(i.Note), Who(user));
                await db.SaveChangesAsync(ct);
                return Results.Ok(await Load(db, id, ct));
            }).RequireAuthorization(ViabilityPolicies.For(area));

            g.MapPost($"/{{id:int}}/reject/{slug}", async (int id, FeasibilityNoteIn i, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
            {
                var f = await db.FeasibilityStudies.FindAsync([id], ct);
                if (f is null) return Results.NotFound();
                if (f.Status != FeasibilityStatus.InReview) throw SalesException.Conflict($"Study is {f.Status}; it must be in review to reject");
                if (!Has(i.Note)) throw SalesException.Invalid("note", "Give the reason");
                f.Status = FeasibilityStatus.Rejected;
                f.RejectionReason = $"{area}: {i.Note!.Trim()}";
                Log(db, id, $"rejected-{slug}", FeasibilityStatus.InReview, f.Status, i.Note.Trim(), Who(user));
                await db.SaveChangesAsync(ct);
                return Results.Ok(await Load(db, id, ct));
            }).RequireAuthorization(ViabilityPolicies.For(area));
        }

        g.MapPost("/{id:int}/reopen", async (int id, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var f = await db.FeasibilityStudies.FindAsync([id], ct);
            if (f is null) return Results.NotFound();
            if (f.Status is FeasibilityStatus.Draft) throw SalesException.Conflict("Study is already a draft");
            if ((await ViabilityRules.UsedOrdersAsync(db, [id], null, ct)).GetValueOrDefault(id) > 0) throw SalesException.Conflict("Study already backs orders; create a new one instead");
            var from = f.Status;
            f.Status = FeasibilityStatus.Draft;
            f.RejectionReason = null;
            ClearSignoffs(f);
            Log(db, id, "reopened", from, f.Status, null, Who(user));
            await db.SaveChangesAsync(ct);
            return Results.Ok(await Load(db, id, ct));
        }).RequireAuthorization(SalesPolicies.Sell);

        g.MapDelete("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
        {
            var f = await db.FeasibilityStudies.FindAsync([id], ct);
            if (f is null) return Results.NotFound();
            if (f.Status != FeasibilityStatus.Draft) return Results.Problem("Only drafts can be deleted", statusCode: StatusCodes.Status409Conflict);
            db.FeasibilityStudies.Remove(f);
            await db.SalesEvents.Where(e => e.Kind == SalesRecordKind.Feasibility && e.RecordId == id).ExecuteDeleteAsync(ct);
            await db.SaveChangesAsync(ct);
            return Results.NoContent();
        }).RequireAuthorization(SalesPolicies.Sell);
    }

    private static async Task Validate(EbtDbContext db, FeasibilityIn i, CancellationToken ct)
    {
        if (!Has(i.Title)) throw SalesException.Invalid("title", "Required");
        if (i.MonthlyConsumptionKg < 0) throw SalesException.Invalid("monthlyConsumptionKg", "Cannot be negative");
        if (i.OrdersAllowed is < 1) throw SalesException.Invalid("ordersAllowed", "At least 1");
        if (!await db.Customers.AnyAsync(c => c.Id == i.CustomerId, ct)) throw SalesException.Invalid("customerId", "Customer not found");
        if (i.QuoteId is { } q && !await db.Quotes.AnyAsync(x => x.Id == q && x.CustomerId == i.CustomerId, ct)) throw SalesException.Invalid("quoteId", "Quote not found for this customer");
        if (i.ProductId is { } p && !await db.Products.AnyAsync(x => x.Id == p, ct)) throw SalesException.Invalid("productId", "Product not found");
    }

    private static void Apply(FeasibilityIn i, FeasibilityStudy f)
    {
        f.QuoteId = i.QuoteId;
        f.ProductId = i.ProductId;
        f.Characteristics = Clean(i.Characteristics);
        f.Transformations = Clean(i.Transformations);
        f.Finishing = Clean(i.Finishing);
        f.Packaging = Clean(i.Packaging);
        f.MonthlyConsumptionKg = i.MonthlyConsumptionKg;
        f.OrdersAllowed = i.OrdersAllowed ?? FeasibilityStudy.DefaultOrdersAllowed;
    }

    private static DateTimeOffset? SignedAt(FeasibilityStudy f, SignoffArea a) => a switch { SignoffArea.Quality => f.QualityAt, SignoffArea.Production => f.ProductionAt, _ => f.CommercialAt };
    private static int Signed(FeasibilityStudy f) => Enum.GetValues<SignoffArea>().Count(a => SignedAt(f, a) is not null);

    private static void SetSignoff(FeasibilityStudy f, SignoffArea a, string? by, DateTimeOffset? at, string? note)
    {
        switch (a)
        {
            case SignoffArea.Quality: (f.QualityBy, f.QualityAt, f.QualityNote) = (by, at, note); break;
            case SignoffArea.Production: (f.ProductionBy, f.ProductionAt, f.ProductionNote) = (by, at, note); break;
            default: (f.CommercialBy, f.CommercialAt, f.CommercialNote) = (by, at, note); break;
        }
    }

    private static void ClearSignoffs(FeasibilityStudy f)
    {
        foreach (var a in Enum.GetValues<SignoffArea>()) SetSignoff(f, a, null, null, null);
    }

    private static void Log(EbtDbContext db, int id, string action, FeasibilityStatus? from, FeasibilityStatus to, string? note, string? user) =>
        db.SalesEvents.Add(new SalesEvent { Kind = SalesRecordKind.Feasibility, RecordId = id, Action = action, FromStatus = from?.ToString(), ToStatus = to.ToString(), Note = note, User = user, At = DateTimeOffset.UtcNow });

    private static async Task<FeasibilityOut> Load(EbtDbContext db, int id, CancellationToken ct)
    {
        var f = await db.FeasibilityStudies.AsNoTracking().Include(x => x.Customer).Include(x => x.Quote).Include(x => x.Product).FirstAsync(x => x.Id == id, ct);
        var orderRows = await db.SalesOrderLines.AsNoTracking().Where(l => l.FeasibilityStudyId == id).Select(l => new { l.OrderId, l.Order!.Reference, l.Order.Status }).Distinct().OrderBy(o => o.OrderId).ToListAsync(ct);
        var orders = orderRows.Select(o => new FeasibilityOrderOut(o.OrderId, o.Reference, o.Status)).ToList();
        var used = (await ViabilityRules.UsedOrdersAsync(db, [id], null, ct)).GetValueOrDefault(id);
        var history = await db.SalesEvents.AsNoTracking().Where(e => e.Kind == SalesRecordKind.Feasibility && e.RecordId == id).OrderByDescending(e => e.At).ThenByDescending(e => e.Id)
            .Select(e => new SalesEventOut(e.Id, e.Action, e.FromStatus, e.ToStatus, e.Note, e.User, e.At)).ToListAsync(ct);
        var signoffs = new[]
        {
            new SignoffOut(SignoffArea.Quality, f.QualityBy, f.QualityAt, f.QualityNote),
            new SignoffOut(SignoffArea.Production, f.ProductionBy, f.ProductionAt, f.ProductionNote),
            new SignoffOut(SignoffArea.Commercial, f.CommercialBy, f.CommercialAt, f.CommercialNote)
        };
        return new FeasibilityOut(f.Id, f.Number, f.Reference, f.QuoteId, f.Quote?.Reference, f.CustomerId, f.Customer!.Name, f.ProductId, f.Product?.Code, f.Product?.Name, f.Title, f.Characteristics, f.Transformations,
            f.Finishing, f.Packaging, f.MonthlyConsumptionKg, f.Status, f.RejectionReason, f.OrdersAllowed, used, Math.Max(0, f.OrdersAllowed - used), signoffs, orders, f.CreatedBy, f.CreatedAt, history);
    }
}
