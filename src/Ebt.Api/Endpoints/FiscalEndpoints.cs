using System.Security.Claims;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Sales;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record FiscalSettingsDto(bool Enabled, SefazEnvironment Environment, string? CompanyName, string? TradeName, string? Cnpj, string? StateRegistration, int TaxRegime, string? Street, string? Number, string? Complement,
    string? District, string? City, string? CityIbgeCode, string Uf, string? ZipCode, string? Phone, int Series, int NextNumber, int CancelWindowHours);
public record CfopIn(string Code, string Description, FiscalKind Kind, bool Taxed, string IcmsCst, string IpiCst, string PisCst, string CofinsCst, decimal DefaultPisPercent, decimal DefaultCofinsPercent,
    string? IpiFramingCode, bool GeneratesInstallments, bool Active = true, string? LegalText = null);
public record CfopOut(string Code, string Description, FiscalKind Kind, bool Taxed, string IcmsCst, string IpiCst, string PisCst, string CofinsCst, decimal DefaultPisPercent, decimal DefaultCofinsPercent,
    string IpiFramingCode, bool GeneratesInstallments, bool Active, string? LegalText);
public record TaxRuleIn(int ProductId, int? CustomerId, string CfopCode, string? IcmsCst, decimal IcmsPercent, decimal IcmsBaseReductionPercent, string? IpiCst, decimal IpiPercent, decimal? PisPercent, decimal? CofinsPercent);
public record TaxRuleOut(int Id, int ProductId, string ProductCode, int? CustomerId, string? CustomerName, string CfopCode, string? IcmsCst, decimal IcmsPercent, decimal IcmsBaseReductionPercent, string? IpiCst, decimal IpiPercent, decimal? PisPercent, decimal? CofinsPercent);
public record MonthlyPriceIn(int ProductId, int CustomerId, string CfopCode, int Year, int Month, decimal UnitPrice);
public record MonthlyPriceOut(int Id, int ProductId, string ProductCode, string ProductName, int CustomerId, string CustomerName, string CfopCode, int Year, int Month, decimal UnitPrice);
public record FiscalLineOut(int Id, int Sequence, int? ProductId, int? ProductionOrderId, string Code, string Description, string Ncm, string Unit, decimal Quantity, decimal UnitPrice, decimal Total, decimal Freight,
    string IcmsCst, decimal IcmsBase, decimal IcmsPercent, decimal IcmsValue, string IpiCst, decimal IpiPercent, decimal IpiValue, string PisCst, decimal PisPercent, decimal PisValue, string CofinsCst, decimal CofinsPercent, decimal CofinsValue);
public record FiscalInstallmentOut(int Sequence, DateOnly DueDate, decimal Amount);
public record FiscalDocumentOut(int Id, FiscalKind Kind, FiscalStatus Status, string CfopCode, int Series, int Number, string AccessKey, string Protocol, SefazEnvironment Environment, bool Simulated, DateTimeOffset IssuedAt, string? IssuedBy,
    int? DeliveryId, string? DeliveryReference, int? OutsideShipmentId, int? CustomerId, int? SupplierId, string RecipientName, string RecipientDocument, string RecipientUf, decimal ProductsTotal, decimal FreightTotal, decimal IcmsBase,
    decimal IcmsTotal, decimal IpiTotal, decimal PisTotal, decimal CofinsTotal, decimal InvoiceTotal, string? AdditionalInfo, DateTimeOffset? CancelledAt, string? CancelledBy, string? CancelReason, string? CancelProtocol,
    IReadOnlyList<FiscalLineOut> Lines, IReadOnlyList<FiscalInstallmentOut> Installments);
public record CancelInvoiceIn(string? Reason, string? Password);

public sealed class FiscalExceptionHandler : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception exception, CancellationToken ct)
    {
        if (exception is not FiscalException e) return false;
        var result = e.Field is not null && e.Status == StatusCodes.Status400BadRequest
            ? Results.ValidationProblem(new Dictionary<string, string[]> { [e.Field] = [e.Message] })
            : Results.Problem(e.Message, statusCode: e.Status);
        await result.ExecuteAsync(http);
        return true;
    }
}

public static class FiscalPolicies
{
    public const string Prices = "fiscal-prices";
    public const string Cancel = "fiscal-cancel";
}

public static class FiscalEndpoints
{
    public static IServiceCollection AddFiscal(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddScoped<FiscalService>();
        var sefaz = configuration.GetSection("Fiscal:Sefaz").Get<SefazOptions>() ?? new SefazOptions();
        if (sefaz.IsReal)
            services.AddSingleton<ISefazClient>(new SefazSpClient(sefaz, sefaz.LoadCertificate())); // Fiscal:Sefaz:Mode = Sp
        else
            services.AddSingleton<ISefazClient, StubSefazClient>(); // simulated authorization, see FISCAL.md
        services.AddExceptionHandler<FiscalExceptionHandler>();
        return services;
    }

    public static void MapFiscal(this WebApplication app)
    {
        MapSettings(app);
        MapRules(app);
        MapDocuments(app);
    }

    private static void MapSettings(WebApplication app)
    {
        var g = app.MapGroup("/api/fiscal/settings").WithTags("Fiscal");
        g.MapGet("/", async (FiscalService svc, CancellationToken ct) => ToDto(await svc.SettingsAsync(ct))).RequireAuthorization(Policies.Read);
        g.MapPut("/", async (FiscalSettingsDto i, EbtDbContext db, FiscalService svc, CancellationToken ct) =>
        {
            var uf = i.Uf?.Trim().ToUpperInvariant() ?? "";
            var maxNumber = await db.FiscalDocuments.Where(d => d.Series == i.Series).Select(d => (int?)d.Number).MaxAsync(ct) ?? 0;
            var errors = Errors()
                .Require(NfeKey.UfCodes.ContainsKey(uf), "uf", "Unknown UF")
                .Require(i.Series is > 0 and <= 999, "series", "Between 1 and 999")
                .Require(i.NextNumber > maxNumber, "nextNumber", $"Must be greater than the last issued number ({maxNumber})")
                .Require(i.TaxRegime is >= 1 and <= 3, "taxRegime", "1, 2 or 3")
                .Require(i.CancelWindowHours >= 0, "cancelWindowHours", "Cannot be negative")
                .Require(!Has(i.Cnpj) || Digits(i.Cnpj, 14), "cnpj", "14 digits")
                .Require(!Has(i.CityIbgeCode) || Digits(i.CityIbgeCode, 7), "cityIbgeCode", "7 digits");
            if (i.Enabled)
            {
                errors.Require(Digits(i.Cnpj, 14), "cnpj", "Required to enable fiscal emission").Require(Has(i.StateRegistration), "stateRegistration", "Required to enable fiscal emission")
                    .Require(Has(i.CompanyName), "companyName", "Required to enable fiscal emission").Require(Has(i.Street) && Has(i.District) && Has(i.City), "street", "Full address required to enable fiscal emission")
                    .Require(Digits(i.CityIbgeCode, 7), "cityIbgeCode", "Required to enable fiscal emission").Require(Digits(i.ZipCode, 8), "zipCode", "8 digits, required to enable fiscal emission");
            }
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var s = await svc.SettingsAsync(ct);
            s.Enabled = i.Enabled;
            s.Environment = i.Environment;
            s.CompanyName = Clean(i.CompanyName);
            s.TradeName = Clean(i.TradeName);
            s.Cnpj = Numeric(i.Cnpj);
            s.StateRegistration = Numeric(i.StateRegistration);
            s.TaxRegime = i.TaxRegime;
            s.Street = Clean(i.Street);
            s.Number = Clean(i.Number);
            s.Complement = Clean(i.Complement);
            s.District = Clean(i.District);
            s.City = Clean(i.City);
            s.CityIbgeCode = Numeric(i.CityIbgeCode);
            s.Uf = uf;
            s.ZipCode = Numeric(i.ZipCode);
            s.Phone = Clean(i.Phone);
            s.Series = i.Series;
            s.NextNumber = i.NextNumber;
            s.CancelWindowHours = i.CancelWindowHours;
            await db.SaveChangesAsync(ct);
            return Results.Ok(ToDto(s));
        }).RequireAuthorization(Policies.Admin);
    }

    private static void MapRules(WebApplication app)
    {
        var cfops = app.MapGroup("/api/fiscal/cfops").WithTags("Fiscal");
        cfops.MapGet("/", async (EbtDbContext db, CancellationToken ct) =>
            await db.Cfops.AsNoTracking().OrderBy(c => c.Code).Select(c => new CfopOut(c.Code, c.Description, c.Kind, c.Taxed, c.IcmsCst, c.IpiCst, c.PisCst, c.CofinsCst, c.DefaultPisPercent, c.DefaultCofinsPercent, c.IpiFramingCode,
                c.GeneratesInstallments, c.Active, c.LegalText)).ToListAsync(ct)).RequireAuthorization(Policies.Read);
        cfops.MapPut("/{code}", async (string code, CfopIn i, EbtDbContext db, CancellationToken ct) =>
        {
            var errors = Errors()
                .Require(code.Length == 4 && code.All(char.IsDigit) && code == i.Code, "code", "4 digits, same as the route")
                .Require(Has(i.Description), "description", "Required")
                .Require(i.IcmsCst is { Length: 2 or 3 } && i.IcmsCst.All(char.IsDigit), "icmsCst", "2 digits")
                .Require(i.IpiCst is { Length: 2 } && i.IpiCst.All(char.IsDigit), "ipiCst", "2 digits")
                .Require(i.PisCst is { Length: 2 } && i.PisCst.All(char.IsDigit), "pisCst", "2 digits")
                .Require(i.CofinsCst is { Length: 2 } && i.CofinsCst.All(char.IsDigit), "cofinsCst", "2 digits")
                .Require(i.DefaultPisPercent is >= 0 and <= 100 && i.DefaultCofinsPercent is >= 0 and <= 100, "defaultPisPercent", "Rates between 0 and 100")
                .Require(i.IpiFramingCode is null || Digits(i.IpiFramingCode, 3), "ipiFramingCode", "3 digits");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var c = await db.Cfops.FindAsync([code], ct);
            if (c is null) db.Cfops.Add(c = new Cfop { Code = code, Description = "", IcmsCst = "", IpiCst = "", PisCst = "", CofinsCst = "" });
            c.Description = i.Description.Trim();
            c.Kind = i.Kind;
            c.Taxed = i.Taxed;
            c.IcmsCst = i.IcmsCst;
            c.IpiCst = i.IpiCst;
            c.PisCst = i.PisCst;
            c.CofinsCst = i.CofinsCst;
            c.DefaultPisPercent = i.DefaultPisPercent;
            c.DefaultCofinsPercent = i.DefaultCofinsPercent;
            c.IpiFramingCode = i.IpiFramingCode ?? "999";
            c.GeneratesInstallments = i.GeneratesInstallments;
            c.Active = i.Active;
            c.LegalText = Clean(i.LegalText);
            await db.SaveChangesAsync(ct);
            return Results.Ok(new CfopOut(c.Code, c.Description, c.Kind, c.Taxed, c.IcmsCst, c.IpiCst, c.PisCst, c.CofinsCst, c.DefaultPisPercent, c.DefaultCofinsPercent, c.IpiFramingCode, c.GeneratesInstallments, c.Active, c.LegalText));
        }).RequireAuthorization(Policies.Admin);

        app.MapGroup("/api/fiscal/tax-rules").WithTags("Fiscal").MapCrud(new CrudSpec<TaxRule, TaxRuleIn, TaxRuleOut>
        {
            Project = r => new TaxRuleOut(r.Id, r.ProductId, r.Product!.Code, r.CustomerId, r.Customer != null ? r.Customer.Name : null, r.CfopCode, r.IcmsCst, r.IcmsPercent, r.IcmsBaseReductionPercent, r.IpiCst, r.IpiPercent, r.PisPercent, r.CofinsPercent),
            Create = i => Apply(new TaxRule { ProductId = i.ProductId, CfopCode = i.CfopCode }, i),
            Apply = (i, r) => Apply(r, i),
            Validate = async (i, db, ct) => Errors()
                .Require(await db.Products.AnyAsync(p => p.Id == i.ProductId, ct), "productId", "Not found")
                .Require(i.CustomerId is null || await db.Customers.AnyAsync(c => c.Id == i.CustomerId, ct), "customerId", "Not found")
                .Require(await db.Cfops.AnyAsync(c => c.Code == i.CfopCode, ct), "cfopCode", "Not found")
                .Require(i.IcmsPercent is >= 0 and <= 100 && i.IcmsBaseReductionPercent is >= 0 and <= 100 && i.IpiPercent is >= 0 and <= 100, "icmsPercent", "Rates between 0 and 100")
                .Require(i.PisPercent is null or (>= 0 and <= 100) && i.CofinsPercent is null or (>= 0 and <= 100), "pisPercent", "Rates between 0 and 100"),
            Search = (q, s) => q.Where(r => EF.Functions.ILike(r.Product!.Code, Like(s)) || EF.Functions.ILike(r.CfopCode, Like(s)) || EF.Functions.ILike(r.Customer!.Name, Like(s))),
            Order = q => q.OrderBy(r => r.Product!.Code).ThenBy(r => r.CfopCode).ThenBy(r => r.CustomerId),
            WritePolicy = FiscalPolicies.Prices
        });

        app.MapGroup("/api/fiscal/monthly-prices").WithTags("Fiscal").MapCrud(new CrudSpec<MonthlyPrice, MonthlyPriceIn, MonthlyPriceOut>
        {
            Project = p => new MonthlyPriceOut(p.Id, p.ProductId, p.Product!.Code, p.Product.Name, p.CustomerId, p.Customer!.Name, p.CfopCode, p.Year, p.Month, p.UnitPrice),
            Create = i => new MonthlyPrice { ProductId = i.ProductId, CustomerId = i.CustomerId, CfopCode = i.CfopCode, Year = i.Year, Month = i.Month, UnitPrice = i.UnitPrice },
            Apply = (i, p) => { p.ProductId = i.ProductId; p.CustomerId = i.CustomerId; p.CfopCode = i.CfopCode; p.Year = i.Year; p.Month = i.Month; p.UnitPrice = i.UnitPrice; },
            Validate = async (i, db, ct) => Errors()
                .Require(await db.Products.AnyAsync(p => p.Id == i.ProductId, ct), "productId", "Not found")
                .Require(await db.Customers.AnyAsync(c => c.Id == i.CustomerId, ct), "customerId", "Not found")
                .Require(await db.Cfops.AnyAsync(c => c.Code == i.CfopCode, ct), "cfopCode", "Not found")
                .Require(i.Year is >= 2000 and <= 2100, "year", "Between 2000 and 2100")
                .Require(i.Month is >= 1 and <= 12, "month", "Between 1 and 12")
                .Require(i.UnitPrice > 0, "unitPrice", "Must be greater than zero"),
            Search = (q, s) => q.Where(p => EF.Functions.ILike(p.Product!.Code, Like(s)) || EF.Functions.ILike(p.Product.Name, Like(s)) || EF.Functions.ILike(p.Customer!.Name, Like(s))),
            Filter = (q, query) =>
            {
                if (int.TryParse(query["year"], out var y)) q = q.Where(p => p.Year == y);
                if (int.TryParse(query["month"], out var m)) q = q.Where(p => p.Month == m);
                if (int.TryParse(query["customerId"], out var c)) q = q.Where(p => p.CustomerId == c);
                return q;
            },
            Order = q => q.OrderByDescending(p => p.Year).ThenByDescending(p => p.Month).ThenBy(p => p.Product!.Code),
            WritePolicy = FiscalPolicies.Prices
        });
    }

    private static TaxRule Apply(TaxRule r, TaxRuleIn i)
    {
        r.ProductId = i.ProductId;
        r.CustomerId = i.CustomerId;
        r.CfopCode = i.CfopCode;
        r.IcmsCst = Clean(i.IcmsCst);
        r.IcmsPercent = i.IcmsPercent;
        r.IcmsBaseReductionPercent = i.IcmsBaseReductionPercent;
        r.IpiCst = Clean(i.IpiCst);
        r.IpiPercent = i.IpiPercent;
        r.PisPercent = i.PisPercent;
        r.CofinsPercent = i.CofinsPercent;
        return r;
    }

    private static void MapDocuments(WebApplication app)
    {
        var g = app.MapGroup("/api/fiscal/documents").WithTags("Fiscal").RequireAuthorization(Policies.Read).AddEndpointFilter(new RowVersionFilter<FiscalDocument>());

        g.MapGet("/", async (EbtDbContext db, FiscalKind? kind, FiscalStatus? status, int? deliveryId, int? outsideShipmentId, string? q, int? skip, int? take, CancellationToken ct) =>
        {
            var x = db.FiscalDocuments.AsNoTracking();
            if (kind is { } k) x = x.Where(d => d.Kind == k);
            if (status is { } s) x = x.Where(d => d.Status == s);
            if (deliveryId is { } di) x = x.Where(d => d.DeliveryId == di);
            if (outsideShipmentId is { } si) x = x.Where(d => d.OutsideShipmentId == si);
            if (Has(q)) x = x.Where(d => EF.Functions.ILike(d.RecipientName!, Like(q!)) || d.AccessKey == q.Trim() || d.Number.ToString() == q.Trim());
            var total = await x.CountAsync(ct);
            var sk = Math.Max(skip ?? 0, 0);
            var tk = Math.Clamp(take ?? 50, 1, 200);
            var items = await x.OrderByDescending(d => d.Series).ThenByDescending(d => d.Number).Skip(sk).Take(tk)
                .Select(d => new FiscalDocumentSummary(d.Id, d.Kind, d.Status, d.CfopCode, d.Series, d.Number, d.AccessKey, d.RecipientName, d.InvoiceTotal, d.IssuedAt, d.Simulated)).ToListAsync(ct);
            return Results.Ok(new Page<FiscalDocumentSummary>(items, total, sk, tk));
        });

        g.MapGet("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) => await Load(db, id, ct) is { } d ? Results.Ok(d) : Results.NotFound());

        g.MapGet("/{id:int}/xml", async (int id, EbtDbContext db, CancellationToken ct) =>
            await db.FiscalDocuments.AsNoTracking().Where(d => d.Id == id).Select(d => d.Xml).FirstOrDefaultAsync(ct) is { } xml ? Results.Content(xml, "application/xml") : Results.NotFound());

        g.MapPost("/{id:int}/cancel", async (int id, CancelInvoiceIn i, EbtDbContext db, FiscalService fiscal, SalesService sales, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            var kind = await db.FiscalDocuments.AsNoTracking().Where(d => d.Id == id).Select(d => (FiscalKind?)d.Kind).FirstOrDefaultAsync(ct);
            if (kind is null) return Results.NotFound();
            var errors = Errors().Require(Has(i.Reason), "reason", "Required").Require(Has(i.Password), "password", "Type your password to confirm the cancellation");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var who = principal.Identity?.Name;
            var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Username == who && u.Active, ct);
            if (user is null || !AuthEndpoints.VerifyPassword(user, i.Password!)) return Results.Problem("Wrong password", statusCode: StatusCodes.Status403Forbidden);
            if (kind == FiscalKind.Sale) await sales.CancelInvoiceAsync(id, i.Reason, who, ct);
            else await fiscal.CancelAsync(id, i.Reason, who, ct);
            return Results.Ok(await Load(db, id, ct));
        }).RequireAuthorization(FiscalPolicies.Cancel);
    }

    private static async Task<FiscalDocumentOut?> Load(EbtDbContext db, int id, CancellationToken ct)
    {
        var d = await db.FiscalDocuments.AsNoTracking().Include(x => x.Lines).Include(x => x.Installments).Include(x => x.Delivery).AsSplitQuery().FirstOrDefaultAsync(x => x.Id == id, ct);
        if (d is null) return null;
        return new FiscalDocumentOut(d.Id, d.Kind, d.Status, d.CfopCode, d.Series, d.Number, d.AccessKey, d.Protocol, d.Environment, d.Simulated, d.IssuedAt, d.IssuedBy, d.DeliveryId, d.Delivery?.Reference, d.OutsideShipmentId, d.CustomerId,
            d.SupplierId, d.RecipientName, d.RecipientDocument, d.RecipientUf, d.ProductsTotal, d.FreightTotal, d.IcmsBase, d.IcmsTotal, d.IpiTotal, d.PisTotal, d.CofinsTotal, d.InvoiceTotal, d.AdditionalInfo, d.CancelledAt, d.CancelledBy,
            d.CancelReason, d.CancelProtocol,
            d.Lines.OrderBy(l => l.Sequence).Select(l => new FiscalLineOut(l.Id, l.Sequence, l.ProductId, l.ProductionOrderId, l.Code, l.Description, l.Ncm, l.Unit, l.Quantity, l.UnitPrice, l.Total, l.Freight, l.IcmsCst, l.IcmsBase, l.IcmsPercent,
                l.IcmsValue, l.IpiCst, l.IpiPercent, l.IpiValue, l.PisCst, l.PisPercent, l.PisValue, l.CofinsCst, l.CofinsPercent, l.CofinsValue)).ToList(),
            d.Installments.OrderBy(i => i.Sequence).Select(i => new FiscalInstallmentOut(i.Sequence, i.DueDate, i.Amount)).ToList());
    }

    private static FiscalSettingsDto ToDto(FiscalSettings s) => new(s.Enabled, s.Environment, s.CompanyName, s.TradeName, s.Cnpj, s.StateRegistration, s.TaxRegime, s.Street, s.Number, s.Complement, s.District, s.City, s.CityIbgeCode, s.Uf,
        s.ZipCode, s.Phone, s.Series, s.NextNumber, s.CancelWindowHours);
}
