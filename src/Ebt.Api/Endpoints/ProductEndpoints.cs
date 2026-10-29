using System.Security.Claims;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record ProductIn(string Code, string Name, ProductKind Kind, TubeShape? Shape, decimal? DiameterMm, decimal? WidthMm, decimal? HeightMm, decimal? ThicknessMm, decimal? LengthMm, decimal? NetWeightKg, decimal? LossPercent, string Ncm, string StockUnit, int? PiecesPerPackage, bool Blocked, string? DrawingRevision, string? ProcessRevision);
public record ProductOut(int Id, string Code, string Name, ProductKind Kind, TubeShape? Shape, decimal? DiameterMm, decimal? WidthMm, decimal? HeightMm, decimal? ThicknessMm, decimal? LengthMm, decimal? NetWeightKg, decimal? LossPercent, string Ncm, string StockUnit, int? PiecesPerPackage, bool Blocked, string? DrawingRevision, string? ProcessRevision, int OperationCount);
public record ProductCustomerIn(string? CustomerPartNumber, string? CustomerDescription, bool Active = true);
public record ProductCustomerOut(int ProductId, int CustomerId, string CustomerName, string? CustomerPartNumber, string? CustomerDescription, bool Active);
public record RoutingOperationIn(int Sequence, int? StandardOperationId, int? MachineId, int? WorkCenterId, int? ToolId, decimal? SetupHours, decimal? PiecesPerHour, decimal? Operators, string? Description, string? Standard, string? Notes);
public record BomItemOut(int Id, int? MaterialId, int? ComponentProductId, string Code, string Description, decimal Quantity, string Unit, decimal Factor);
public record RoutingOperationOut(int Id, int ProductId, int Sequence, int? StandardOperationId, int? MachineId, string? MachineCode, int? WorkCenterId, int? ToolId, decimal? SetupHours, decimal? PiecesPerHour, decimal? Operators, string? Description, string? Standard, string? Notes, IReadOnlyList<BomItemOut> Items);
public record BomItemIn(int? MaterialId, int? ComponentProductId, decimal Quantity, string Unit, decimal Factor = 1m);
public record RevisionIn(RevisionKind Kind, string Code, string? Reason);
public record RevisionOut(int Id, RevisionKind Kind, string Code, string? Reason, string? User, DateTimeOffset CreatedAt);

public static class ProductEndpoints
{
    public static void MapProducts(this WebApplication app)
    {
        var products = app.MapGroup("/api/products").WithTags("Products");
        products.MapCrud(new CrudSpec<Product, ProductIn, ProductOut>
        {
            Project = p => new ProductOut(p.Id, p.Code, p.Name, p.Kind, p.Shape, p.DiameterMm, p.WidthMm, p.HeightMm, p.ThicknessMm, p.LengthMm, p.NetWeightKg, p.LossPercent, p.Ncm, p.StockUnit, p.PiecesPerPackage, p.Blocked, p.DrawingRevision, p.ProcessRevision, p.Routing.Count),
            Create = i => { var p = new Product { Code = "", Name = "", Ncm = "", StockUnit = "" }; ApplyProduct(i, p); return p; },
            Apply = ApplyProduct,
            Validate = (i, _, _) => Task.FromResult(ValidateProduct(i)),
            Search = (q, s) => q.Where(p => p.Code.StartsWith(s) || EF.Functions.ILike(p.Name, Like(s))),
            Order = q => q.OrderBy(p => p.Code),
            BeforeDelete = async (id, db, ct) => await db.BomItems.AnyAsync(b => b.ComponentProductId == id, ct) ? "Product is used as a component in another bill of materials" : null
        });

        products.MapGet("/{id:int}/customers", async (int id, EbtDbContext db, CancellationToken ct) =>
            await db.ProductCustomers.AsNoTracking().Where(pc => pc.ProductId == id).OrderBy(pc => pc.Customer!.Name)
                .Select(pc => new ProductCustomerOut(pc.ProductId, pc.CustomerId, pc.Customer!.Name, pc.CustomerPartNumber, pc.CustomerDescription, pc.Active))
                .ToListAsync(ct)).RequireAuthorization(Policies.Read);

        products.MapPut("/{id:int}/customers/{customerId:int}", async (int id, int customerId, ProductCustomerIn i, EbtDbContext db, CancellationToken ct) =>
        {
            if (!await db.Products.AnyAsync(p => p.Id == id, ct) || !await db.Customers.AnyAsync(c => c.Id == customerId, ct)) return Results.NotFound();
            var link = await db.ProductCustomers.FindAsync([id, customerId], ct);
            if (link is null) db.ProductCustomers.Add(link = new ProductCustomer { ProductId = id, CustomerId = customerId });
            link.CustomerPartNumber = Clean(i.CustomerPartNumber);
            link.CustomerDescription = Clean(i.CustomerDescription);
            link.Active = i.Active;
            await db.SaveChangesAsync(ct);
            var name = await db.Customers.Where(c => c.Id == customerId).Select(c => c.Name).FirstAsync(ct);
            return Results.Ok(new ProductCustomerOut(id, customerId, name, link.CustomerPartNumber, link.CustomerDescription, link.Active));
        }).RequireAuthorization(Policies.Write);

        products.MapDelete("/{id:int}/customers/{customerId:int}", async (int id, int customerId, EbtDbContext db, CancellationToken ct) =>
            await db.ProductCustomers.Where(pc => pc.ProductId == id && pc.CustomerId == customerId).ExecuteDeleteAsync(ct) == 0 ? Results.NotFound() : Results.NoContent())
            .RequireAuthorization(Policies.Write);

        products.MapGet("/{id:int}/routing", async (int id, EbtDbContext db, CancellationToken ct) =>
            !await db.Products.AnyAsync(p => p.Id == id, ct) ? Results.NotFound() : Results.Ok(await LoadRouting(db, id, null, ct)))
            .RequireAuthorization(Policies.Read);

        products.MapPost("/{id:int}/routing", async (int id, RoutingOperationIn i, EbtDbContext db, CancellationToken ct) =>
        {
            if (!await db.Products.AnyAsync(p => p.Id == id, ct)) return Results.NotFound();
            var errors = ValidateOperation(i);
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var op = new RoutingOperation { ProductId = id };
            ApplyOperation(i, op);
            db.RoutingOperations.Add(op);
            await db.SaveChangesAsync(ct);
            return Results.Created($"/api/routing-operations/{op.Id}", (await LoadRouting(db, id, op.Id, ct)).Single());
        }).RequireAuthorization(Policies.Write);

        var ops = app.MapGroup("/api/routing-operations").WithTags("Products");

        ops.MapPut("/{id:int}", async (int id, RoutingOperationIn i, EbtDbContext db, CancellationToken ct) =>
        {
            var op = await db.RoutingOperations.FindAsync([id], ct);
            if (op is null) return Results.NotFound();
            var errors = ValidateOperation(i);
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            ApplyOperation(i, op);
            await db.SaveChangesAsync(ct);
            return Results.Ok((await LoadRouting(db, op.ProductId, op.Id, ct)).Single());
        }).RequireAuthorization(Policies.Write);

        ops.MapDelete("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
            await db.RoutingOperations.Where(o => o.Id == id).ExecuteDeleteAsync(ct) == 0 ? Results.NotFound() : Results.NoContent())
            .RequireAuthorization(Policies.Write);

        ops.MapPost("/{id:int}/items", async (int id, BomItemIn i, EbtDbContext db, BomService bom, CancellationToken ct) =>
        {
            var op = await db.RoutingOperations.FindAsync([id], ct);
            if (op is null) return Results.NotFound();
            var check = await CheckItem(i, op.ProductId, db, bom, ct);
            if (check is not null) return check;
            var item = new BomItem { RoutingOperationId = id, MaterialId = i.MaterialId, ComponentProductId = i.ComponentProductId, Quantity = i.Quantity, Unit = i.Unit.Trim().ToUpper(), Factor = i.Factor };
            db.BomItems.Add(item);
            await db.SaveChangesAsync(ct);
            return Results.Created($"/api/bom-items/{item.Id}", await ItemOut(db, item.Id, ct));
        }).RequireAuthorization(Policies.Write);

        var items = app.MapGroup("/api/bom-items").WithTags("Products");

        items.MapPut("/{id:int}", async (int id, BomItemIn i, EbtDbContext db, BomService bom, CancellationToken ct) =>
        {
            var item = await db.BomItems.Include(x => x.RoutingOperation).FirstOrDefaultAsync(x => x.Id == id, ct);
            if (item is null) return Results.NotFound();
            var check = await CheckItem(i, item.RoutingOperation!.ProductId, db, bom, ct);
            if (check is not null) return check;
            item.MaterialId = i.MaterialId;
            item.ComponentProductId = i.ComponentProductId;
            item.Quantity = i.Quantity;
            item.Unit = i.Unit.Trim().ToUpper();
            item.Factor = i.Factor;
            await db.SaveChangesAsync(ct);
            return Results.Ok(await ItemOut(db, id, ct));
        }).RequireAuthorization(Policies.Write);

        items.MapDelete("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
            await db.BomItems.Where(x => x.Id == id).ExecuteDeleteAsync(ct) == 0 ? Results.NotFound() : Results.NoContent())
            .RequireAuthorization(Policies.Write);

        products.MapGet("/{id:int}/bom/explode", async (int id, decimal? quantity, BomService bom, CancellationToken ct) =>
        {
            var qty = quantity ?? 1m;
            if (qty <= 0) return Results.ValidationProblem(Errors().Require(false, "quantity", "Must be greater than zero"));
            try
            {
                var result = await bom.ExplodeAsync(id, qty, ct);
                return result is null ? Results.NotFound() : Results.Ok(result);
            }
            catch (BomCycleException ex)
            {
                return Results.Problem(ex.Message, statusCode: StatusCodes.Status409Conflict);
            }
        }).RequireAuthorization(Policies.Read);

        products.MapGet("/{id:int}/where-used", async (int id, BomService bom, CancellationToken ct) =>
            Results.Ok(await bom.WhereUsedAsync(null, id, ct))).RequireAuthorization(Policies.Read);

        app.MapGet("/api/materials/{id:int}/where-used", async (int id, BomService bom, CancellationToken ct) =>
            Results.Ok(await bom.WhereUsedAsync(id, null, ct))).WithTags("Materials").RequireAuthorization(Policies.Read);

        products.MapGet("/{id:int}/revisions", async (int id, EbtDbContext db, CancellationToken ct) =>
            await db.Revisions.AsNoTracking().Where(r => r.ProductId == id).OrderByDescending(r => r.CreatedAt)
                .Select(r => new RevisionOut(r.Id, r.Kind, r.Code, r.Reason, r.User, r.CreatedAt)).ToListAsync(ct))
            .RequireAuthorization(Policies.Read);

        products.MapPost("/{id:int}/revisions", async (int id, RevisionIn i, EbtDbContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var product = await db.Products.FindAsync([id], ct);
            if (product is null) return Results.NotFound();
            if (!Has(i.Code)) return Results.ValidationProblem(Errors().Require(false, "code", "Required"));
            var rev = new Revision { ProductId = id, Kind = i.Kind, Code = i.Code.Trim(), Reason = Clean(i.Reason), User = user.Identity?.Name, CreatedAt = DateTimeOffset.UtcNow };
            if (i.Kind == RevisionKind.Drawing) product.DrawingRevision = rev.Code;
            if (i.Kind == RevisionKind.Process) product.ProcessRevision = rev.Code;
            db.Revisions.Add(rev);
            await db.SaveChangesAsync(ct);
            return Results.Created($"/api/products/{id}/revisions/{rev.Id}", new RevisionOut(rev.Id, rev.Kind, rev.Code, rev.Reason, rev.User, rev.CreatedAt));
        }).RequireAuthorization(Policies.Write);
    }

    private static Dictionary<string, string[]> ValidateProduct(ProductIn i)
    {
        var errors = Errors()
            .Require(Has(i.Code), "code", "Required")
            .Require(Has(i.Name), "name", "Required")
            .Require(Digits(i.Ncm, 8), "ncm", "NCM must have 8 digits")
            .Require(Has(i.StockUnit), "stockUnit", "Required")
            .Require(i.LossPercent is null or >= 0 and < 100, "lossPercent", "Between 0 and 100")
            .Require(i.PiecesPerPackage is null or > 0, "piecesPerPackage", "Must be positive");
        if (i.Shape == TubeShape.Circular)
            errors.Require(i.DiameterMm is > 0, "diameterMm", "Required for circular tubes")
                  .Require(i.ThicknessMm is null || i.DiameterMm is null || i.ThicknessMm * 2 < i.DiameterMm, "thicknessMm", "Wall thickness must be less than half the diameter");
        if (i.Shape == TubeShape.Rectangular)
            errors.Require(i.WidthMm is > 0, "widthMm", "Required for rectangular tubes")
                  .Require(i.HeightMm is > 0, "heightMm", "Required for rectangular tubes");
        return errors;
    }

    private static void ApplyProduct(ProductIn i, Product p)
    {
        p.Code = i.Code.Trim();
        p.Name = i.Name.Trim();
        p.Kind = i.Kind;
        p.Shape = i.Shape;
        p.DiameterMm = i.DiameterMm;
        p.WidthMm = i.WidthMm;
        p.HeightMm = i.HeightMm;
        p.ThicknessMm = i.ThicknessMm;
        p.LengthMm = i.LengthMm;
        p.NetWeightKg = i.NetWeightKg ?? TubeWeight.NetWeightKg(i.Shape, i.DiameterMm, i.WidthMm, i.HeightMm, i.ThicknessMm, i.LengthMm);
        p.LossPercent = i.LossPercent;
        p.Ncm = Numeric(i.Ncm)!;
        p.StockUnit = i.StockUnit.Trim().ToUpper();
        p.PiecesPerPackage = i.PiecesPerPackage;
        p.Blocked = i.Blocked;
        p.DrawingRevision = Clean(i.DrawingRevision);
        p.ProcessRevision = Clean(i.ProcessRevision);
    }

    private static Dictionary<string, string[]> ValidateOperation(RoutingOperationIn i) => Errors()
        .Require(i.Sequence > 0 && i.Sequence % 10 == 0, "sequence", "Must be a positive multiple of 10")
        .Require(i.SetupHours is null or >= 0, "setupHours", "Must not be negative")
        .Require(i.PiecesPerHour is null or > 0, "piecesPerHour", "Must be positive")
        .Require(i.Operators is null or >= 0, "operators", "Must not be negative");

    private static void ApplyOperation(RoutingOperationIn i, RoutingOperation op)
    {
        op.Sequence = i.Sequence;
        op.StandardOperationId = i.StandardOperationId;
        op.MachineId = i.MachineId;
        op.WorkCenterId = i.WorkCenterId;
        op.ToolId = i.ToolId;
        op.SetupHours = i.SetupHours;
        op.PiecesPerHour = i.PiecesPerHour;
        op.Operators = i.Operators;
        op.Description = Clean(i.Description);
        op.Standard = Clean(i.Standard);
        op.Notes = Clean(i.Notes);
    }

    private static async Task<IResult?> CheckItem(BomItemIn i, int parentProductId, EbtDbContext db, BomService bom, CancellationToken ct)
    {
        var errors = Errors()
            .Require((i.MaterialId is null) != (i.ComponentProductId is null), "materialId", "Set exactly one of materialId or componentProductId")
            .Require(i.Quantity > 0, "quantity", "Must be greater than zero")
            .Require(i.Factor > 0, "factor", "Must be greater than zero")
            .Require(Has(i.Unit), "unit", "Required");
        if (errors.Count > 0) return Results.ValidationProblem(errors);
        if (i.MaterialId is { } mid && !await db.Materials.AnyAsync(m => m.Id == mid, ct))
            return Results.ValidationProblem(Errors().Require(false, "materialId", "Material not found"));
        if (i.ComponentProductId is { } cid)
        {
            if (!await db.Products.AnyAsync(p => p.Id == cid, ct))
                return Results.ValidationProblem(Errors().Require(false, "componentProductId", "Product not found"));
            if (await bom.WouldCreateCycleAsync(parentProductId, cid, ct))
                return Results.Problem("Adding this component would make the product contain itself", statusCode: StatusCodes.Status409Conflict);
        }
        return null;
    }

    private static async Task<BomItemOut> ItemOut(EbtDbContext db, int id, CancellationToken ct) =>
        await db.BomItems.AsNoTracking().Where(b => b.Id == id).Select(ItemProjection).FirstAsync(ct);

    private static readonly System.Linq.Expressions.Expression<Func<BomItem, BomItemOut>> ItemProjection = b => new BomItemOut(
        b.Id, b.MaterialId, b.ComponentProductId,
        b.Material != null ? b.Material.Code : b.ComponentProduct!.Code,
        b.Material != null ? b.Material.Description : b.ComponentProduct!.Name,
        b.Quantity, b.Unit, b.Factor);

    private static async Task<List<RoutingOperationOut>> LoadRouting(EbtDbContext db, int productId, int? onlyId, CancellationToken ct)
    {
        var ops = await db.RoutingOperations.AsNoTracking()
            .Where(o => o.ProductId == productId && (onlyId == null || o.Id == onlyId))
            .OrderBy(o => o.Sequence)
            .Select(o => new
            {
                o.Id, o.ProductId, o.Sequence, o.StandardOperationId, o.MachineId, MachineCode = o.Machine != null ? o.Machine.Code : null,
                o.WorkCenterId, o.ToolId, o.SetupHours, o.PiecesPerHour, o.Operators, o.Description, o.Standard, o.Notes
            })
            .ToListAsync(ct);
        var opIds = ops.Select(o => o.Id).ToList();
        var items = await db.BomItems.AsNoTracking().Where(b => opIds.Contains(b.RoutingOperationId)).OrderBy(b => b.Id)
            .Select(b => new { b.RoutingOperationId, Item = new BomItemOut(b.Id, b.MaterialId, b.ComponentProductId,
                b.Material != null ? b.Material.Code : b.ComponentProduct!.Code,
                b.Material != null ? b.Material.Description : b.ComponentProduct!.Name,
                b.Quantity, b.Unit, b.Factor) })
            .ToListAsync(ct);
        return ops.Select(o => new RoutingOperationOut(o.Id, o.ProductId, o.Sequence, o.StandardOperationId, o.MachineId, o.MachineCode, o.WorkCenterId, o.ToolId,
            o.SetupHours, o.PiecesPerHour, o.Operators, o.Description, o.Standard, o.Notes,
            items.Where(i => i.RoutingOperationId == o.Id).Select(i => i.Item).ToList())).ToList();
    }
}
