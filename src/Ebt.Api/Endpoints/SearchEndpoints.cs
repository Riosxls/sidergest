using System.Security.Claims;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record SearchHit(int Id, string Title, string? Subtitle);
public record SearchGroup(string Key, IReadOnlyList<SearchHit> Hits);
public record SearchOut(string Query, IReadOnlyList<SearchGroup> Groups);

/// <summary>Global search behind the command palette: a few hits per entity in one round trip.</summary>
public static class SearchEndpoints
{
    /// <summary>Policy a caller must satisfy to see each group. Groups the caller cannot read are left out, not returned empty.</summary>
    public static readonly (string Key, string Policy)[] Groups =
    [
        ("products", Policies.Read),
        ("production-orders", Policies.Read),
        ("sales-orders", Policies.Read),
        ("quotes", Policies.Read),
        ("customers", Policies.Read),
        ("fiscal-documents", Policies.Read),
        ("certificates", Policies.Read),
    ];

    public static void MapSearch(this WebApplication app)
    {
        app.MapGet("/api/search", async (string? q, int? take, ClaimsPrincipal user, IAuthorizationService auth, EbtDbContext db, CancellationToken ct) =>
        {
            var term = (q ?? "").Trim();
            if (term.Length < 2) return Results.Ok(new SearchOut(term, []));
            var n = Math.Clamp(take ?? 4, 1, 10);
            var like = Like(term);
            var groups = new List<SearchGroup>();
            foreach (var (key, policy) in Groups)
            {
                if (!(await auth.AuthorizeAsync(user, policy)).Succeeded) continue;
                var hits = await Hits(db, key, term, like, n, ct);
                if (hits.Count > 0) groups.Add(new SearchGroup(key, hits));
            }
            return Results.Ok(new SearchOut(term, groups));
        }).WithTags("Search").RequireAuthorization(Policies.Read);
    }

    private static async Task<IReadOnlyList<SearchHit>> Hits(EbtDbContext db, string key, string term, string like, int n, CancellationToken ct)
    {
        switch (key)
        {
            case "products":
                return (await db.Products.AsNoTracking()
                    .Where(p => p.Code.StartsWith(term) || EF.Functions.ILike(p.Name, like))
                    .OrderBy(p => p.Code).Take(n).Select(p => new { p.Id, p.Code, p.Name }).ToListAsync(ct))
                    .Select(p => new SearchHit(p.Id, $"{p.Code}  {p.Name}", null)).ToList();
            case "production-orders":
                return (await db.ProductionOrders.AsNoTracking()
                    .Where(o => EF.Functions.ILike(o.Reference, like) || EF.Functions.ILike(o.Product!.Code, like))
                    .OrderByDescending(o => o.CreatedAt).Take(n).Select(o => new { o.Id, o.Reference, Code = o.Product!.Code, o.Product.Name }).ToListAsync(ct))
                    .Select(o => new SearchHit(o.Id, o.Reference, $"{o.Code}  {o.Name}")).ToList();
            case "sales-orders":
                return (await db.SalesOrders.AsNoTracking()
                    .Where(o => EF.Functions.ILike(o.Reference, like) || EF.Functions.ILike(o.Customer!.Name, like) || EF.Functions.ILike(o.CustomerPo!, like))
                    .OrderByDescending(o => o.CreatedAt).Take(n).Select(o => new { o.Id, o.Reference, Customer = o.Customer!.Name, o.CustomerPo }).ToListAsync(ct))
                    .Select(o => new SearchHit(o.Id, o.Reference, o.CustomerPo == null ? o.Customer : $"{o.Customer} · PC {o.CustomerPo}")).ToList();
            case "quotes":
                return (await db.Quotes.AsNoTracking()
                    .Where(o => EF.Functions.ILike(o.Reference, like) || EF.Functions.ILike(o.Customer!.Name, like) || EF.Functions.ILike(o.CustomerReference!, like))
                    .OrderByDescending(o => o.CreatedAt).Take(n).Select(o => new { o.Id, o.Reference, Customer = o.Customer!.Name }).ToListAsync(ct))
                    .Select(o => new SearchHit(o.Id, o.Reference, o.Customer)).ToList();
            case "customers":
                return (await db.Customers.AsNoTracking()
                    .Where(c => EF.Functions.ILike(c.Name, like) || EF.Functions.ILike(c.TradeName!, like) || EF.Functions.ILike(c.Document!, like) || EF.Functions.ILike(c.LegacyCode!, like))
                    .OrderBy(c => c.Name).Take(n).Select(c => new { c.Id, c.Name, c.TradeName, c.Document }).ToListAsync(ct))
                    .Select(c => new SearchHit(c.Id, c.Name, string.Join(" · ", new[] { c.TradeName, c.Document }.Where(s => !string.IsNullOrWhiteSpace(s))))).ToList();
            case "fiscal-documents":
                return (await db.FiscalDocuments.AsNoTracking()
                    .Where(d => EF.Functions.ILike(d.RecipientName!, like) || d.AccessKey == term || d.Number.ToString() == term)
                    .OrderByDescending(d => d.Series).ThenByDescending(d => d.Number).Take(n).Select(d => new { d.Id, d.Series, d.Number, d.RecipientName }).ToListAsync(ct))
                    .Select(d => new SearchHit(d.Id, $"NF {d.Number}", d.RecipientName)).ToList();
            default:
                return (await db.QualityCertificates.AsNoTracking()
                    .Where(c => EF.Functions.ILike(c.Reference, like) || EF.Functions.ILike(c.Order!.Reference, like) || EF.Functions.ILike(c.Order.Customer!.Name, like)
                        || EF.Functions.ILike(c.Description, like) || c.CustomerPo != null && EF.Functions.ILike(c.CustomerPo!, like) || c.InvoiceNumber != null && EF.Functions.ILike(c.InvoiceNumber!, like))
                    .OrderByDescending(c => c.Year).ThenByDescending(c => c.Number).Take(n).Select(c => new { c.Id, c.Reference, Customer = c.Order!.Customer!.Name }).ToListAsync(ct))
                    .Select(c => new SearchHit(c.Id, c.Reference, c.Customer)).ToList();
        }
    }
}
