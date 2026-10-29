using static Ebt.Api.Infrastructure.Crud;
using System.Security.Claims;
using Ebt.Api.Infrastructure;
using Ebt.Core.Certificates;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Api.Endpoints;

public record CertificateMeasureOut(CertificateMeasureKind Kind, int Sequence, string Name, string? Specified, string? Found);
public record CertificateSummaryOut(int Id, string Reference, string Company, CertificateStatus Status, DateOnly IssueDate, int OrderId, string OrderReference, string CustomerName, string? CustomerPo, string? InvoiceNumber,
    decimal Quantity, string Unit, string Description, int? DeliveryId, string? DeliveryReference);
public record CertificateOut(int Id, string Company, int Number, int Year, string Reference, int OrderId, string OrderReference, int? OrderLineId, int? DeliveryId, string? DeliveryReference, int CustomerId, string CustomerName,
    string? CustomerPo, DateOnly IssueDate, string? InvoiceNumber, string? EffectiveInvoiceNumber, decimal Quantity, string Unit, int? ProductId, string? ProductCode, string Description, string? CustomerPartNumber,
    string? CustomerPartDescription, string? RawMaterialLot, string? Hardness, string? Finish, string? Notes, string? ApprovedBy, CertificateStatus Status, string? CancelReason, string? CreatedBy, DateTimeOffset CreatedAt,
    string? IssuedBy, DateTimeOffset? IssuedAt, IReadOnlyList<CertificateMeasureOut> Measures);
public record CertificateLinkIn(int? DeliveryId);
public record CertificateReasonIn(string? Reason);
public record CertificateWaiverIn(bool Waived);

public static class CertificatePolicies
{
    public const string Manage = "certificates";
}

public static class CertificateEndpoints
{
    public static IServiceCollection AddCertificates(this IServiceCollection services)
    {
        services.AddScoped<CertificateService>();
        return services;
    }

    private static string? Who(ClaimsPrincipal user) => user.Identity?.Name;

    public static void MapCertificates(this WebApplication app)
    {
        var g = app.MapGroup("/api/sales/certificates").WithTags("Certificates").RequireAuthorization(Policies.Read);

        g.MapGet("/", async (EbtDbContext db, CertificateStatus? status, int? orderId, int? deliveryId, int? customerId, string? company, string? q, int? skip, int? take, CancellationToken ct) =>
        {
            var x = db.QualityCertificates.AsNoTracking().AsQueryable();
            if (status is { } s) x = x.Where(c => c.Status == s);
            if (orderId is { } o) x = x.Where(c => c.OrderId == o);
            if (deliveryId is { } d) x = x.Where(c => c.DeliveryId == d);
            if (customerId is { } cu) x = x.Where(c => c.Order!.CustomerId == cu);
            if (!string.IsNullOrWhiteSpace(company)) x = x.Where(c => c.Company == company.Trim().ToUpper());
            if (!string.IsNullOrWhiteSpace(q))
            {
                var t = Like(q);
                x = x.Where(c => EF.Functions.ILike(c.Reference, t) || EF.Functions.ILike(c.Order!.Reference, t) || EF.Functions.ILike(c.Order.Customer!.Name, t) || EF.Functions.ILike(c.Description, t)
                    || c.CustomerPo != null && EF.Functions.ILike(c.CustomerPo!, t) || c.InvoiceNumber != null && EF.Functions.ILike(c.InvoiceNumber!, t) || c.Delivery!.InvoiceNumber != null && EF.Functions.ILike(c.Delivery.InvoiceNumber, t));
            }
            var (sk, n) = (Math.Max(skip ?? 0, 0), Math.Clamp(take ?? 50, 1, 500));
            var total = await x.CountAsync(ct);
            var items = await x.OrderByDescending(c => c.Year).ThenByDescending(c => c.Number).Skip(sk).Take(n).Select(c => new CertificateSummaryOut(c.Id, c.Reference, c.Company, c.Status, c.IssueDate, c.OrderId, c.Order!.Reference,
                c.Order.Customer!.Name, c.CustomerPo, c.InvoiceNumber ?? c.Delivery!.InvoiceNumber, c.Quantity, c.Unit, c.Description, c.DeliveryId, c.Delivery!.Reference)).ToListAsync(ct);
            return Results.Ok(new Page<CertificateSummaryOut>(items, total, sk, n));
        });

        g.MapGet("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) => await db.QualityCertificates.AnyAsync(c => c.Id == id, ct) ? Results.Ok(await Load(db, id, ct)) : Results.NotFound());

        g.MapPost("/", async (CertificateInput i, EbtDbContext db, CertificateService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var c = await svc.CreateAsync(i, Who(user), ct);
            return Results.Created($"/api/sales/certificates/{c.Id}", await Load(db, c.Id, ct));
        }).RequireAuthorization(CertificatePolicies.Manage);

        g.MapPut("/{id:int}", async (int id, CertificateInput i, EbtDbContext db, CertificateService svc, CancellationToken ct) =>
        {
            await svc.UpdateAsync(id, i, ct);
            return Results.Ok(await Load(db, id, ct));
        }).RequireAuthorization(CertificatePolicies.Manage);

        g.MapPost("/{id:int}/issue", async (int id, EbtDbContext db, CertificateService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.IssueAsync(id, Who(user), ct);
            return Results.Ok(await Load(db, id, ct));
        }).RequireAuthorization(CertificatePolicies.Manage);

        g.MapPost("/{id:int}/link-delivery", async (int id, CertificateLinkIn i, EbtDbContext db, CertificateService svc, CancellationToken ct) =>
        {
            await svc.LinkDeliveryAsync(id, i.DeliveryId, ct);
            return Results.Ok(await Load(db, id, ct));
        }).RequireAuthorization(CertificatePolicies.Manage);

        g.MapPost("/{id:int}/cancel", async (int id, CertificateReasonIn i, EbtDbContext db, CertificateService svc, CancellationToken ct) =>
        {
            await svc.CancelAsync(id, i.Reason, ct);
            return Results.Ok(await Load(db, id, ct));
        }).RequireAuthorization(CertificatePolicies.Manage);

        g.MapDelete("/{id:int}", async (int id, CertificateService svc, CancellationToken ct) =>
        {
            await svc.DeleteAsync(id, ct);
            return Results.NoContent();
        }).RequireAuthorization(CertificatePolicies.Manage);

        // Blank tables of the template, pre-filled with the product dimensions of an order line, used by the editor for a new certificate.
        g.MapGet("/template", async (EbtDbContext db, int? orderLineId, CancellationToken ct) =>
        {
            var p = orderLineId is { } lid ? await db.SalesOrderLines.AsNoTracking().Where(l => l.Id == lid).Select(l => l.Product).FirstOrDefaultAsync(ct) : null;
            return Results.Ok(CertificateService.TemplateMeasures(p).Select((m, n) => new CertificateMeasureOut(m.Kind, n + 1, m.Name, m.Specified, m.Found)));
        });

        app.MapPost("/api/sales/orders/{id:int}/certificate-waiver", async (int id, CertificateWaiverIn i, CertificateService svc, CancellationToken ct) =>
        {
            await svc.SetWaivedAsync(id, i.Waived, ct);
            return Results.Ok(new { waived = i.Waived });
        }).WithTags("Certificates").RequireAuthorization(CertificatePolicies.Manage);
    }

    private static async Task<CertificateOut> Load(EbtDbContext db, int id, CancellationToken ct)
    {
        var c = await db.QualityCertificates.AsNoTracking().Include(x => x.Measures).Include(x => x.Delivery).Include(x => x.Order).ThenInclude(o => o!.Customer).FirstAsync(x => x.Id == id, ct);
        var measures = c.Measures.OrderBy(m => m.Kind).ThenBy(m => m.Sequence).Select(m => new CertificateMeasureOut(m.Kind, m.Sequence, m.Name, m.Specified, m.Found)).ToList();
        return new CertificateOut(c.Id, c.Company, c.Number, c.Year, c.Reference, c.OrderId, c.Order!.Reference, c.OrderLineId, c.DeliveryId, c.Delivery?.Reference, c.Order.CustomerId, c.Order.Customer!.Name, c.CustomerPo, c.IssueDate,
            c.InvoiceNumber, c.InvoiceNumber ?? c.Delivery?.InvoiceNumber, c.Quantity, c.Unit, c.ProductId, c.ProductCode, c.Description, c.CustomerPartNumber, c.CustomerPartDescription, c.RawMaterialLot, c.Hardness, c.Finish, c.Notes,
            c.ApprovedBy, c.Status, c.CancelReason, c.CreatedBy, c.CreatedAt, c.IssuedBy, c.IssuedAt, measures);
    }
}
