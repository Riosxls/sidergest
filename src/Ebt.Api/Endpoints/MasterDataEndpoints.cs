using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record CustomerIn(string Name, string? TradeName, string? LegacyCode, ConsumerType ConsumerType, bool Active = true);
public record CustomerOut(int Id, string Name, string? TradeName, string? LegacyCode, ConsumerType ConsumerType, bool Active, int AddressCount);
public record CustomerAddressIn(string Document, string Uf, string? LegacyCode, string? StateRegistration, bool IcmsContributor, string? Street, string? Number, string? Complement, string? District, string? City, string? CityIbgeCode, string? ZipCode, string? DefaultCfop, string? Buyer, string? Email, string? Phone);
public record CustomerAddressOut(int Id, int CustomerId, string Document, string Uf, string? LegacyCode, string? StateRegistration, bool IcmsContributor, string? Street, string? Number, string? Complement, string? District, string? City, string? CityIbgeCode, string? ZipCode, string? DefaultCfop, string? Buyer, string? Email, string? Phone);

public record SupplierIn(string Name, string? TradeName, string? LegacyCode, string? GroupCode, bool Active = true);
public record SupplierOut(int Id, string Name, string? TradeName, string? LegacyCode, string? GroupCode, bool Active, int AddressCount);
public record SupplierAddressIn(string Uf, string? Document, string? LegacyCode, string? StateRegistration, string? Street, string? Number, string? District, string? City, string? CityIbgeCode, string? ZipCode, string? Email, string? Phone);
public record SupplierAddressOut(int Id, int SupplierId, string Uf, string? Document, string? LegacyCode, string? StateRegistration, string? Street, string? Number, string? District, string? City, string? CityIbgeCode, string? ZipCode, string? Email, string? Phone);

public record CodeNameIn(string Code, string Name);
public record CodeNameOut(int Id, string Code, string Name);
public record SubgroupIn(string Code, string Name, string? Standard);
public record SubgroupOut(int Id, string Code, string Name, string? Standard);

public record MaterialIn(string Code, string Description, int? ClassId, int? GroupId, int? SubgroupId, string StockUnit, string PurchaseUnit, decimal PurchaseFactor, decimal? ThicknessMm, decimal? WidthMm, string? Ncm, int? LeadTimeDays, decimal? PurchaseLot, decimal? MinStock, decimal? MaxStock, bool RequiresInspection, bool GeneratesPurchaseOrder, bool ExternalProcessing, bool Active = true);
public record MaterialOut(int Id, string Code, string Description, int? ClassId, int? GroupId, int? SubgroupId, string? SubgroupName, string StockUnit, string PurchaseUnit, decimal PurchaseFactor, decimal? ThicknessMm, decimal? WidthMm, string? Ncm, int? LeadTimeDays, decimal? PurchaseLot, decimal? MinStock, decimal? MaxStock, bool RequiresInspection, bool GeneratesPurchaseOrder, bool ExternalProcessing, bool Active);

public record WorkCenterIn(string Code, string Name, string? CostCenter);
public record WorkCenterOut(int Id, string Code, string Name, string? CostCenter);
public record MachineIn(string Code, string Name, int? WorkCenterId, string? Family);
public record MachineOut(int Id, string Code, string Name, int? WorkCenterId, string? WorkCenterName, string? Family);
public record ToolIn(string Code, string Name, int? WarningLimit, int? InspectionLimit);
public record ToolOut(int Id, string Code, string Name, int? WarningLimit, int? InspectionLimit);

public static class MasterDataEndpoints
{
    public static void MapMasterData(this WebApplication app)
    {
        app.MapGroup("/api/customers").WithTags("Customers").MapCrud(new CrudSpec<Customer, CustomerIn, CustomerOut>
        {
            Project = c => new CustomerOut(c.Id, c.Name, c.TradeName, c.LegacyCode, c.ConsumerType, c.Active, c.Addresses.Count),
            Create = i => new Customer { Name = i.Name.Trim(), TradeName = Clean(i.TradeName), LegacyCode = Clean(i.LegacyCode), ConsumerType = i.ConsumerType, Active = i.Active },
            Apply = (i, c) => { c.Name = i.Name.Trim(); c.TradeName = Clean(i.TradeName); c.LegacyCode = Clean(i.LegacyCode); c.ConsumerType = i.ConsumerType; c.Active = i.Active; },
            Validate = (i, _, _) => Task.FromResult(Errors().Require(Has(i.Name), "name", "Required")),
            Search = (q, s) => q.Where(c => EF.Functions.ILike(c.Name, $"%{s}%") || EF.Functions.ILike(c.TradeName ?? "", $"%{s}%") || c.LegacyCode == s),
            Order = q => q.OrderBy(c => c.Name),
            BeforeDelete = async (id, db, ct) => await db.ProductCustomers.AnyAsync(pc => pc.CustomerId == id, ct) ? "Customer is linked to products" : null
        });
        MapCustomerAddresses(app);

        app.MapGroup("/api/suppliers").WithTags("Suppliers").MapCrud(new CrudSpec<Supplier, SupplierIn, SupplierOut>
        {
            Project = s => new SupplierOut(s.Id, s.Name, s.TradeName, s.LegacyCode, s.GroupCode, s.Active, s.Addresses.Count),
            Create = i => new Supplier { Name = i.Name.Trim(), TradeName = Clean(i.TradeName), LegacyCode = Clean(i.LegacyCode), GroupCode = Clean(i.GroupCode), Active = i.Active },
            Apply = (i, s) => { s.Name = i.Name.Trim(); s.TradeName = Clean(i.TradeName); s.LegacyCode = Clean(i.LegacyCode); s.GroupCode = Clean(i.GroupCode); s.Active = i.Active; },
            Validate = (i, _, _) => Task.FromResult(Errors().Require(Has(i.Name), "name", "Required")),
            Search = (q, s) => q.Where(x => EF.Functions.ILike(x.Name, $"%{s}%") || EF.Functions.ILike(x.TradeName ?? "", $"%{s}%") || x.LegacyCode == s),
            Order = q => q.OrderBy(x => x.Name)
        });
        MapSupplierAddresses(app);

        app.MapGroup("/api/material-classes").WithTags("Materials").MapCrud(CodeName<MaterialClass>(
            (i) => new MaterialClass { Code = i.Code.Trim(), Name = i.Name.Trim() },
            async (id, db, ct) => await db.Materials.AnyAsync(m => m.ClassId == id, ct) ? "Class is used by materials" : null));
        app.MapGroup("/api/material-groups").WithTags("Materials").MapCrud(CodeName<MaterialGroup>(
            (i) => new MaterialGroup { Code = i.Code.Trim(), Name = i.Name.Trim() },
            async (id, db, ct) => await db.Materials.AnyAsync(m => m.GroupId == id, ct) ? "Group is used by materials" : null));
        app.MapGroup("/api/material-subgroups").WithTags("Materials").MapCrud(new CrudSpec<MaterialSubgroup, SubgroupIn, SubgroupOut>
        {
            Project = s => new SubgroupOut(s.Id, s.Code, s.Name, s.Standard),
            Create = i => new MaterialSubgroup { Code = i.Code.Trim(), Name = i.Name.Trim(), Standard = Clean(i.Standard) },
            Apply = (i, s) => { s.Code = i.Code.Trim(); s.Name = i.Name.Trim(); s.Standard = Clean(i.Standard); },
            Validate = (i, _, _) => Task.FromResult(Errors().Require(Has(i.Code), "code", "Required").Require(Has(i.Name), "name", "Required")),
            Order = q => q.OrderBy(s => s.Code),
            BeforeDelete = async (id, db, ct) => await db.Materials.AnyAsync(m => m.SubgroupId == id, ct) ? "Subgroup is used by materials" : null
        });

        app.MapGroup("/api/materials").WithTags("Materials").MapCrud(new CrudSpec<Material, MaterialIn, MaterialOut>
        {
            Project = m => new MaterialOut(m.Id, m.Code, m.Description, m.ClassId, m.GroupId, m.SubgroupId, m.Subgroup != null ? m.Subgroup.Name : null, m.StockUnit, m.PurchaseUnit, m.PurchaseFactor, m.ThicknessMm, m.WidthMm, m.Ncm, m.LeadTimeDays, m.PurchaseLot, m.MinStock, m.MaxStock, m.RequiresInspection, m.GeneratesPurchaseOrder, m.ExternalProcessing, m.Active),
            Create = i => { var m = new Material { Code = i.Code.Trim(), Description = i.Description.Trim(), StockUnit = i.StockUnit.Trim().ToUpper(), PurchaseUnit = i.PurchaseUnit.Trim().ToUpper() }; ApplyMaterial(i, m); return m; },
            Apply = ApplyMaterial,
            Validate = (i, _, _) => Task.FromResult(Errors()
                .Require(Has(i.Code), "code", "Required")
                .Require(Has(i.Description), "description", "Required")
                .Require(Has(i.StockUnit), "stockUnit", "Required")
                .Require(Has(i.PurchaseUnit), "purchaseUnit", "Required")
                .Require(i.PurchaseFactor > 0, "purchaseFactor", "Must be greater than zero")
                .Require(i.Ncm is null || Digits(i.Ncm, 8), "ncm", "NCM must have 8 digits")
                .Require(i.MinStock is null || i.MaxStock is null || i.MinStock <= i.MaxStock, "minStock", "Must not exceed maxStock")),
            Search = (q, s) => q.Where(m => m.Code.StartsWith(s) || EF.Functions.ILike(m.Description, $"%{s}%")),
            Order = q => q.OrderBy(m => m.Code),
            BeforeDelete = async (id, db, ct) => await db.BomItems.AnyAsync(b => b.MaterialId == id, ct) ? "Material is used in a bill of materials" : null
        });

        app.MapGroup("/api/work-centers").WithTags("Shop floor").MapCrud(new CrudSpec<WorkCenter, WorkCenterIn, WorkCenterOut>
        {
            Project = w => new WorkCenterOut(w.Id, w.Code, w.Name, w.CostCenter),
            Create = i => new WorkCenter { Code = i.Code.Trim(), Name = i.Name.Trim(), CostCenter = Clean(i.CostCenter) },
            Apply = (i, w) => { w.Code = i.Code.Trim(); w.Name = i.Name.Trim(); w.CostCenter = Clean(i.CostCenter); },
            Validate = (i, _, _) => Task.FromResult(Errors().Require(Has(i.Code), "code", "Required").Require(Has(i.Name), "name", "Required")),
            Order = q => q.OrderBy(w => w.Code),
            BeforeDelete = async (id, db, ct) => await db.Machines.AnyAsync(m => m.WorkCenterId == id, ct) || await db.RoutingOperations.AnyAsync(o => o.WorkCenterId == id, ct) ? "Work center is in use" : null
        });

        app.MapGroup("/api/machines").WithTags("Shop floor").MapCrud(new CrudSpec<Machine, MachineIn, MachineOut>
        {
            Project = m => new MachineOut(m.Id, m.Code, m.Name, m.WorkCenterId, m.WorkCenter != null ? m.WorkCenter.Name : null, m.Family),
            Create = i => new Machine { Code = i.Code.Trim(), Name = i.Name.Trim(), WorkCenterId = i.WorkCenterId, Family = Clean(i.Family) },
            Apply = (i, m) => { m.Code = i.Code.Trim(); m.Name = i.Name.Trim(); m.WorkCenterId = i.WorkCenterId; m.Family = Clean(i.Family); },
            Validate = (i, _, _) => Task.FromResult(Errors().Require(Has(i.Code), "code", "Required").Require(Has(i.Name), "name", "Required")),
            Search = (q, s) => q.Where(m => m.Code.StartsWith(s) || EF.Functions.ILike(m.Name, $"%{s}%")),
            Order = q => q.OrderBy(m => m.Code),
            BeforeDelete = async (id, db, ct) => await db.RoutingOperations.AnyAsync(o => o.MachineId == id, ct) ? "Machine is used in routings" : null
        });

        app.MapGroup("/api/tools").WithTags("Shop floor").MapCrud(new CrudSpec<Tool, ToolIn, ToolOut>
        {
            Project = t => new ToolOut(t.Id, t.Code, t.Name, t.WarningLimit, t.InspectionLimit),
            Create = i => new Tool { Code = i.Code.Trim(), Name = i.Name.Trim(), WarningLimit = i.WarningLimit, InspectionLimit = i.InspectionLimit },
            Apply = (i, t) => { t.Code = i.Code.Trim(); t.Name = i.Name.Trim(); t.WarningLimit = i.WarningLimit; t.InspectionLimit = i.InspectionLimit; },
            Validate = (i, _, _) => Task.FromResult(Errors().Require(Has(i.Code), "code", "Required").Require(Has(i.Name), "name", "Required")),
            Order = q => q.OrderBy(t => t.Code),
            BeforeDelete = async (id, db, ct) => await db.RoutingOperations.AnyAsync(o => o.ToolId == id, ct) ? "Tool is used in routings" : null
        });

        app.MapGroup("/api/standard-operations").WithTags("Shop floor").MapCrud(CodeName<StandardOperation>(
            (i) => new StandardOperation { Code = i.Code.Trim(), Name = i.Name.Trim() },
            async (id, db, ct) => await db.RoutingOperations.AnyAsync(o => o.StandardOperationId == id, ct) ? "Operation is used in routings" : null));
    }

    private static void ApplyMaterial(MaterialIn i, Material m)
    {
        m.Code = i.Code.Trim();
        m.Description = i.Description.Trim();
        m.ClassId = i.ClassId;
        m.GroupId = i.GroupId;
        m.SubgroupId = i.SubgroupId;
        m.StockUnit = i.StockUnit.Trim().ToUpper();
        m.PurchaseUnit = i.PurchaseUnit.Trim().ToUpper();
        m.PurchaseFactor = i.PurchaseFactor;
        m.ThicknessMm = i.ThicknessMm;
        m.WidthMm = i.WidthMm;
        m.Ncm = Numeric(i.Ncm);
        m.LeadTimeDays = i.LeadTimeDays;
        m.PurchaseLot = i.PurchaseLot;
        m.MinStock = i.MinStock;
        m.MaxStock = i.MaxStock;
        m.RequiresInspection = i.RequiresInspection;
        m.GeneratesPurchaseOrder = i.GeneratesPurchaseOrder;
        m.ExternalProcessing = i.ExternalProcessing;
        m.Active = i.Active;
    }

    private static CrudSpec<T, CodeNameIn, CodeNameOut> CodeName<T>(Func<CodeNameIn, T> create, Func<int, EbtDbContext, CancellationToken, Task<string?>> beforeDelete) where T : class => new()
    {
        Project = e => new CodeNameOut(EF.Property<int>(e, "Id"), EF.Property<string>(e, "Code"), EF.Property<string>(e, "Name")),
        Create = create,
        Apply = (i, e) =>
        {
            typeof(T).GetProperty("Code")!.SetValue(e, i.Code.Trim());
            typeof(T).GetProperty("Name")!.SetValue(e, i.Name.Trim());
        },
        Validate = (i, _, _) => Task.FromResult(Errors().Require(Has(i.Code), "code", "Required").Require(Has(i.Name), "name", "Required")),
        Order = q => q.OrderBy(e => EF.Property<string>(e, "Code")),
        BeforeDelete = beforeDelete
    };

    private static void MapCustomerAddresses(WebApplication app)
    {
        var g = app.MapGroup("/api/customers/{customerId:int}/addresses").WithTags("Customers");

        g.MapGet("/", async (int customerId, EbtDbContext db, CancellationToken ct) =>
            await db.CustomerAddresses.AsNoTracking().Where(a => a.CustomerId == customerId).OrderBy(a => a.LegacyCode).ThenBy(a => a.Id)
                .Select(a => ToOut(a)).ToListAsync(ct)).RequireAuthorization(Policies.Read);

        g.MapPost("/", async (int customerId, CustomerAddressIn i, EbtDbContext db, CancellationToken ct) =>
        {
            if (!await db.Customers.AnyAsync(c => c.Id == customerId, ct)) return Results.NotFound();
            var errors = ValidateAddress(i);
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var a = new CustomerAddress { CustomerId = customerId, Document = "", Uf = "" };
            ApplyAddress(i, a);
            db.CustomerAddresses.Add(a);
            await db.SaveChangesAsync(ct);
            return Results.Created($"/api/customers/{customerId}/addresses/{a.Id}", ToOut(a));
        }).RequireAuthorization(Policies.Write);

        g.MapPut("/{id:int}", async (int customerId, int id, CustomerAddressIn i, EbtDbContext db, CancellationToken ct) =>
        {
            var a = await db.CustomerAddresses.FirstOrDefaultAsync(x => x.Id == id && x.CustomerId == customerId, ct);
            if (a is null) return Results.NotFound();
            var errors = ValidateAddress(i);
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            ApplyAddress(i, a);
            await db.SaveChangesAsync(ct);
            return Results.Ok(ToOut(a));
        }).RequireAuthorization(Policies.Write);

        g.MapDelete("/{id:int}", async (int customerId, int id, EbtDbContext db, CancellationToken ct) =>
        {
            var deleted = await db.CustomerAddresses.Where(x => x.Id == id && x.CustomerId == customerId).ExecuteDeleteAsync(ct);
            return deleted == 0 ? Results.NotFound() : Results.NoContent();
        }).RequireAuthorization(Policies.Write);
    }

    private static Dictionary<string, string[]> ValidateAddress(CustomerAddressIn i) => Errors()
        .Require(Digits(i.Document, 11, 14), "document", "CPF (11) or CNPJ (14) digits")
        .Require(Has(i.Uf) && i.Uf.Trim().Length == 2, "uf", "Two-letter state")
        .Require(i.CityIbgeCode is null || Digits(i.CityIbgeCode, 7), "cityIbgeCode", "7 digits")
        .Require(i.ZipCode is null || Digits(i.ZipCode, 8), "zipCode", "8 digits")
        .Require(!i.IcmsContributor || Has(i.StateRegistration), "stateRegistration", "Required for ICMS contributors");

    private static void ApplyAddress(CustomerAddressIn i, CustomerAddress a)
    {
        a.Document = Numeric(i.Document)!;
        a.Uf = i.Uf.Trim().ToUpper();
        a.LegacyCode = Clean(i.LegacyCode);
        a.StateRegistration = Clean(i.StateRegistration);
        a.IcmsContributor = i.IcmsContributor;
        a.Street = Clean(i.Street);
        a.Number = Clean(i.Number);
        a.Complement = Clean(i.Complement);
        a.District = Clean(i.District);
        a.City = Clean(i.City);
        a.CityIbgeCode = Numeric(i.CityIbgeCode);
        a.ZipCode = Numeric(i.ZipCode);
        a.DefaultCfop = Clean(i.DefaultCfop);
        a.Buyer = Clean(i.Buyer);
        a.Email = Clean(i.Email);
        a.Phone = Clean(i.Phone);
    }

    private static CustomerAddressOut ToOut(CustomerAddress a) => new(a.Id, a.CustomerId, a.Document, a.Uf, a.LegacyCode, a.StateRegistration, a.IcmsContributor, a.Street, a.Number, a.Complement, a.District, a.City, a.CityIbgeCode, a.ZipCode, a.DefaultCfop, a.Buyer, a.Email, a.Phone);

    private static void MapSupplierAddresses(WebApplication app)
    {
        var g = app.MapGroup("/api/suppliers/{supplierId:int}/addresses").WithTags("Suppliers");

        g.MapGet("/", async (int supplierId, EbtDbContext db, CancellationToken ct) =>
            await db.SupplierAddresses.AsNoTracking().Where(a => a.SupplierId == supplierId).OrderBy(a => a.LegacyCode).ThenBy(a => a.Id)
                .Select(a => ToOut(a)).ToListAsync(ct)).RequireAuthorization(Policies.Read);

        g.MapPost("/", async (int supplierId, SupplierAddressIn i, EbtDbContext db, CancellationToken ct) =>
        {
            if (!await db.Suppliers.AnyAsync(s => s.Id == supplierId, ct)) return Results.NotFound();
            var errors = ValidateAddress(i);
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var a = new SupplierAddress { SupplierId = supplierId, Uf = "" };
            ApplyAddress(i, a);
            db.SupplierAddresses.Add(a);
            await db.SaveChangesAsync(ct);
            return Results.Created($"/api/suppliers/{supplierId}/addresses/{a.Id}", ToOut(a));
        }).RequireAuthorization(Policies.Write);

        g.MapPut("/{id:int}", async (int supplierId, int id, SupplierAddressIn i, EbtDbContext db, CancellationToken ct) =>
        {
            var a = await db.SupplierAddresses.FirstOrDefaultAsync(x => x.Id == id && x.SupplierId == supplierId, ct);
            if (a is null) return Results.NotFound();
            var errors = ValidateAddress(i);
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            ApplyAddress(i, a);
            await db.SaveChangesAsync(ct);
            return Results.Ok(ToOut(a));
        }).RequireAuthorization(Policies.Write);

        g.MapDelete("/{id:int}", async (int supplierId, int id, EbtDbContext db, CancellationToken ct) =>
        {
            var deleted = await db.SupplierAddresses.Where(x => x.Id == id && x.SupplierId == supplierId).ExecuteDeleteAsync(ct);
            return deleted == 0 ? Results.NotFound() : Results.NoContent();
        }).RequireAuthorization(Policies.Write);
    }

    private static Dictionary<string, string[]> ValidateAddress(SupplierAddressIn i) => Errors()
        .Require(i.Document is null || Digits(i.Document, 11, 14), "document", "CPF (11) or CNPJ (14) digits")
        .Require(Has(i.Uf) && i.Uf.Trim().Length == 2, "uf", "Two-letter state")
        .Require(i.ZipCode is null || Digits(i.ZipCode, 8), "zipCode", "8 digits");

    private static void ApplyAddress(SupplierAddressIn i, SupplierAddress a)
    {
        a.Document = Numeric(i.Document);
        a.Uf = i.Uf.Trim().ToUpper();
        a.LegacyCode = Clean(i.LegacyCode);
        a.StateRegistration = Clean(i.StateRegistration);
        a.Street = Clean(i.Street);
        a.Number = Clean(i.Number);
        a.District = Clean(i.District);
        a.City = Clean(i.City);
        a.CityIbgeCode = Numeric(i.CityIbgeCode);
        a.ZipCode = Numeric(i.ZipCode);
        a.Email = Clean(i.Email);
        a.Phone = Clean(i.Phone);
    }

    private static SupplierAddressOut ToOut(SupplierAddress a) => new(a.Id, a.SupplierId, a.Uf, a.Document, a.LegacyCode, a.StateRegistration, a.Street, a.Number, a.District, a.City, a.CityIbgeCode, a.ZipCode, a.Email, a.Phone);
}
