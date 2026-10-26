using System.Linq.Expressions;
using System.Security.Claims;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Production;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record ProductionSettingsDto(decimal OverrunTolerancePercent, decimal HoursPerDay, bool WorkSaturdays, int? IssueLocationId, int? ReceiptLocationId);
public record ShiftIn(string Code, string Name, TimeOnly? StartsAt, TimeOnly? EndsAt, decimal? Hours);
public record ShiftOut(int Id, string Code, string Name, TimeOnly? StartsAt, TimeOnly? EndsAt, decimal? Hours);
public record EmployeeIn(string Code, string Name, string? Nickname, string? Function, int? WorkCenterId, int? ShiftId, bool Active = true);
public record EmployeeOut(int Id, string Code, string Name, string? Nickname, string? Function, int? WorkCenterId, int? ShiftId, bool Active);
public record OccurrenceIn(string Code, string Description, OccurrenceKind Kind, bool StopsOrder);
public record OccurrenceOut(int Id, string Code, string Description, OccurrenceKind Kind, bool StopsOrder);
public record HolidayIn(DateOnly Date, string Name);
public record HolidayOut(int Id, DateOnly Date, string Name);

public record ProductionOrderIn(int ProductId, decimal Quantity, DateOnly DueDate, ProductionOrderKind Kind = ProductionOrderKind.Standard, int? CustomerId = null, int? ParentOrderId = null, int? PreviousOrderId = null, int? Bales = null, string? Notes = null);
public record OrderUpdateIn(decimal Quantity, DateOnly DueDate, int? CustomerId, int? Bales, string? Notes);
public record ProductionReasonIn(string? Reason, bool Technical = false);
public record ReleaseIn(bool Force = false);
public record OverrunIn(decimal Quantity, string? Justification);
public record ProductionOrderSummaryOut(int Id, ProductionOrderKind Kind, int Number, string Reference, int ProductId, string ProductCode, string ProductName, int? CustomerId, string? CustomerName, decimal Quantity, DateOnly DueDate,
    DateOnly? PlannedStart, DateOnly? PlannedEnd, DateOnly? AdjustedStart, DateOnly? AdjustedEnd, ProductionOrderStatus Status, int? ParentOrderId, DateTimeOffset CreatedAt);
public record ProductionOperationOut(int Id, int Sequence, string? Description, int? MachineId, string? MachineCode, int? WorkCenterId, decimal? SetupHours, decimal? PiecesPerHour, decimal? Operators, bool External, int? SupplierId, int? ExternalLeadDays,
    decimal PlannedHours, DateOnly? PlannedStart, DateOnly? PlannedEnd, decimal Good, decimal Scrap, decimal InTransit, decimal OverrunReleased, decimal Limit, decimal Remaining);
public record ProductionOrderOut(int Id, ProductionOrderKind Kind, int Number, string Reference, int ProductId, string ProductCode, string ProductName, string ProductUnit, int? CustomerId, decimal Quantity, DateOnly DueDate,
    DateOnly? PlannedStart, DateOnly? PlannedEnd, DateOnly? AdjustedStart, DateOnly? AdjustedEnd, ProductionOrderStatus Status, string? StatusReason, int? ParentOrderId, int? PreviousOrderId, int? Bales, string? Notes,
    string? CreatedBy, DateTimeOffset CreatedAt, DateTimeOffset? ReleasedAt, DateTimeOffset? FinishedAt, DateTimeOffset? ClosedAt, string? ClosedBy, DateTimeOffset? CostClosedAt, decimal? MaterialCost, decimal? ServiceCost, decimal? UnitCost,
    decimal Good, decimal Scrap, decimal Received, decimal Receivable, decimal WorkInProcess, IReadOnlyList<ProductionOperationOut> Operations, IReadOnlyList<MaterialLineState> Materials,
    IReadOnlyList<ProductionOrderSummaryOut> Children, IReadOnlyList<string> Warnings);
public record ReleaseOut(ProductionOrderOut Order, IReadOnlyList<AvailabilityLine> Shortages);
public record AvailabilityCheckIn(int ProductId, decimal Quantity);
public record ProductionReportOut(int Id, int OrderId, string Reference, int OperationSequence, DateOnly Date, int? ShiftId, int? EmployeeId, string? EmployeeName, int? MachineId, string? MachineCode, TimeOnly? StartTime, TimeOnly? EndTime,
    decimal? Hours, decimal? SetupHours, decimal? Operators, decimal? DowntimeHours, int? DowntimeOccurrenceId, decimal GoodQuantity, decimal ScrapQuantity, int? ScrapOccurrenceId, decimal? WeightKg, int? OutsideShipmentId,
    string? Notes, string? ReportedBy, DateTimeOffset ReportedAt);
public record OutsideShipmentOut(int Id, int OrderId, string Reference, int OperationSequence, int SupplierId, string SupplierName, DateOnly SentOn, decimal Quantity, decimal ReturnedQuantity, decimal ScrapQuantity, decimal Open,
    decimal ServiceValue, string? InvoiceNumber, string? Notes);
public record OverrunOut(int Id, int OperationId, decimal Quantity, string Justification, string? ReleasedBy, DateTimeOffset ReleasedAt);

public static class ProductionPolicies
{
    public const string Plan = "production";
    public const string Materials = "production-materials";
}

public sealed class ProductionExceptionHandler : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception exception, CancellationToken ct)
    {
        if (exception is not ProductionException e) return false;
        var result = e.Field is not null && e.Status == StatusCodes.Status400BadRequest
            ? Results.ValidationProblem(new Dictionary<string, string[]> { [e.Field] = [e.Message] })
            : Results.Problem(e.Message, statusCode: e.Status);
        await result.ExecuteAsync(http);
        return true;
    }
}

public static class ProductionEndpoints
{
    public static IServiceCollection AddProduction(this IServiceCollection services)
    {
        services.AddScoped<ProductionService>();
        services.AddExceptionHandler<ProductionExceptionHandler>();
        services.AddAuthorization(o =>
        {
            o.AddPolicy(ProductionPolicies.Plan, p => p.RequireRole(nameof(UserRole.Admin), nameof(UserRole.Production)));
            o.AddPolicy(ProductionPolicies.Materials, p => p.RequireRole(nameof(UserRole.Admin), nameof(UserRole.Production), nameof(UserRole.Stock)));
        });
        return services;
    }

    private static string? Who(ClaimsPrincipal user) => user.Identity?.Name;

    public static void MapProduction(this WebApplication app)
    {
        MapMasters(app);
        MapOrders(app);
        MapShopFloor(app);
        MapPlanning(app);
    }

    private static void MapMasters(WebApplication app)
    {
        var settings = app.MapGroup("/api/production/settings").WithTags("Production");
        settings.MapGet("/", async (ProductionService svc, CancellationToken ct) => ToDto(await svc.SettingsAsync(ct))).RequireAuthorization(Policies.Read);
        settings.MapPut("/", async (ProductionSettingsDto i, EbtDbContext db, ProductionService svc, CancellationToken ct) =>
        {
            var errors = Errors()
                .Require(i.OverrunTolerancePercent is >= 0 and <= 100, "overrunTolerancePercent", "Between 0 and 100")
                .Require(i.HoursPerDay is > 0 and <= 24, "hoursPerDay", "Between 0 and 24");
            foreach (var (lid, f) in new[] { (i.IssueLocationId, "issueLocationId"), (i.ReceiptLocationId, "receiptLocationId") })
                if (lid is { } l) errors.Require(await db.StockLocations.AnyAsync(x => x.Id == l && x.Active && x.Kind != StockLocationKind.ThirdParty, ct), f, "Unknown, inactive or third-party location");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var s = await svc.SettingsAsync(ct);
            s.OverrunTolerancePercent = i.OverrunTolerancePercent;
            s.HoursPerDay = i.HoursPerDay;
            s.WorkSaturdays = i.WorkSaturdays;
            s.IssueLocationId = i.IssueLocationId;
            s.ReceiptLocationId = i.ReceiptLocationId;
            await db.SaveChangesAsync(ct);
            return Results.Ok(ToDto(s));
        }).RequireAuthorization(Policies.Admin);

        app.MapGroup("/api/production/shifts").WithTags("Production").MapCrud(new CrudSpec<Shift, ShiftIn, ShiftOut>
        {
            Project = s => new ShiftOut(s.Id, s.Code, s.Name, s.StartsAt, s.EndsAt, s.Hours),
            Create = i => new Shift { Code = i.Code.Trim().ToUpper(), Name = i.Name.Trim(), StartsAt = i.StartsAt, EndsAt = i.EndsAt, Hours = i.Hours },
            Apply = (i, s) => { s.Code = i.Code.Trim().ToUpper(); s.Name = i.Name.Trim(); s.StartsAt = i.StartsAt; s.EndsAt = i.EndsAt; s.Hours = i.Hours; },
            Validate = (i, _, _) => Task.FromResult(Errors().Require(Has(i.Code), "code", "Required").Require(Has(i.Name), "name", "Required").Require(i.Hours is null or (> 0 and <= 24), "hours", "Between 0 and 24")),
            Order = q => q.OrderBy(s => s.Code),
            BeforeDelete = async (id, db, ct) => await db.Employees.AnyAsync(e => e.ShiftId == id, ct) || await db.ProductionReports.AnyAsync(r => r.ShiftId == id, ct) ? "Shift is in use" : null,
            WritePolicy = ProductionPolicies.Plan
        });

        app.MapGroup("/api/production/employees").WithTags("Production").MapCrud(new CrudSpec<Employee, EmployeeIn, EmployeeOut>
        {
            Project = e => new EmployeeOut(e.Id, e.Code, e.Name, e.Nickname, e.Function, e.WorkCenterId, e.ShiftId, e.Active),
            Create = i => new Employee { Code = i.Code.Trim().ToUpper(), Name = i.Name.Trim(), Nickname = Clean(i.Nickname), Function = Clean(i.Function), WorkCenterId = i.WorkCenterId, ShiftId = i.ShiftId, Active = i.Active },
            Apply = (i, e) => { e.Code = i.Code.Trim().ToUpper(); e.Name = i.Name.Trim(); e.Nickname = Clean(i.Nickname); e.Function = Clean(i.Function); e.WorkCenterId = i.WorkCenterId; e.ShiftId = i.ShiftId; e.Active = i.Active; },
            Validate = async (i, db, ct) => Errors().Require(Has(i.Code), "code", "Required").Require(Has(i.Name), "name", "Required")
                .Require(i.WorkCenterId is null || await db.WorkCenters.AnyAsync(w => w.Id == i.WorkCenterId, ct), "workCenterId", "Not found")
                .Require(i.ShiftId is null || await db.Shifts.AnyAsync(s => s.Id == i.ShiftId, ct), "shiftId", "Not found"),
            Search = (q, s) => q.Where(e => EF.Functions.ILike(e.Code, $"%{s}%") || EF.Functions.ILike(e.Name, $"%{s}%") || EF.Functions.ILike(e.Nickname ?? "", $"%{s}%")),
            Order = q => q.OrderBy(e => e.Name),
            BeforeDelete = async (id, db, ct) => await db.ProductionReports.AnyAsync(r => r.EmployeeId == id, ct) ? "Employee has reports; deactivate instead" : null,
            WritePolicy = ProductionPolicies.Plan
        });

        app.MapGroup("/api/production/occurrences").WithTags("Production").MapCrud(new CrudSpec<ProductionOccurrence, OccurrenceIn, OccurrenceOut>
        {
            Project = o => new OccurrenceOut(o.Id, o.Code, o.Description, o.Kind, o.StopsOrder),
            Create = i => new ProductionOccurrence { Code = i.Code.Trim().ToUpper(), Description = i.Description.Trim(), Kind = i.Kind, StopsOrder = i.StopsOrder },
            Apply = (i, o) => { o.Code = i.Code.Trim().ToUpper(); o.Description = i.Description.Trim(); o.Kind = i.Kind; o.StopsOrder = i.StopsOrder; },
            Validate = (i, _, _) => Task.FromResult(Errors().Require(Has(i.Code), "code", "Required").Require(Has(i.Description), "description", "Required")),
            Order = q => q.OrderBy(o => o.Code),
            BeforeDelete = async (id, db, ct) => await db.ProductionReports.AnyAsync(r => r.ScrapOccurrenceId == id || r.DowntimeOccurrenceId == id, ct) ? "Occurrence is in use" : null,
            WritePolicy = ProductionPolicies.Plan
        });

        app.MapGroup("/api/production/holidays").WithTags("Production").MapCrud(new CrudSpec<Holiday, HolidayIn, HolidayOut>
        {
            Project = h => new HolidayOut(h.Id, h.Date, h.Name),
            Create = i => new Holiday { Date = i.Date, Name = i.Name.Trim() },
            Apply = (i, h) => { h.Date = i.Date; h.Name = i.Name.Trim(); },
            Validate = (i, _, _) => Task.FromResult(Errors().Require(Has(i.Name), "name", "Required")),
            Order = q => q.OrderBy(h => h.Date),
            WritePolicy = ProductionPolicies.Plan
        });
    }

    private static void MapOrders(WebApplication app)
    {
        var g = app.MapGroup("/api/production/orders").WithTags("Production").RequireAuthorization(Policies.Read);

        g.MapGet("/", async (EbtDbContext db, ProductionOrderStatus? status, ProductionOrderKind? kind, int? productId, int? parentOrderId, DateOnly? dueFrom, DateOnly? dueTo, bool? open, string? q, int? skip, int? take, CancellationToken ct) =>
        {
            var o = db.ProductionOrders.AsNoTracking();
            if (status is { } st) o = o.Where(x => x.Status == st);
            if (open == true) o = o.Where(x => ProductionService.Open.Contains(x.Status));
            if (kind is { } k) o = o.Where(x => x.Kind == k);
            if (productId is { } p) o = o.Where(x => x.ProductId == p);
            if (parentOrderId is { } par) o = o.Where(x => x.ParentOrderId == par);
            if (dueFrom is { } f) o = o.Where(x => x.DueDate >= f);
            if (dueTo is { } t) o = o.Where(x => x.DueDate <= t);
            if (Has(q)) o = o.Where(x => EF.Functions.ILike(x.Reference, $"%{q!.Trim()}%") || EF.Functions.ILike(x.Product!.Code, $"%{q.Trim()}%"));
            var total = await o.CountAsync(ct);
            var (s, n) = Paging(skip, take);
            var items = await o.OrderBy(x => x.DueDate).ThenBy(x => x.Number).Skip(s).Take(n).Select(Summary).ToListAsync(ct);
            return Results.Ok(new Page<ProductionOrderSummaryOut>(items, total, s, n));
        });

        g.MapGet("/{id:int}", async (int id, EbtDbContext db, ProductionService svc, CancellationToken ct) =>
            await db.ProductionOrders.AnyAsync(o => o.Id == id, ct) ? Results.Ok(await Load(db, svc, id, ct)) : Results.NotFound());

        g.MapPost("/", async (ProductionOrderIn i, EbtDbContext db, ProductionService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var o = await svc.CreateOrderAsync(new OrderInput(i.ProductId, i.Quantity, i.DueDate, i.Kind, i.CustomerId, i.ParentOrderId, i.PreviousOrderId, i.Bales, i.Notes), Who(user), ct);
            return Results.Created($"/api/production/orders/{o.Id}", await Load(db, svc, o.Id, ct));
        }).RequireAuthorization(ProductionPolicies.Plan);

        g.MapPut("/{id:int}", async (int id, OrderUpdateIn i, EbtDbContext db, ProductionService svc, CancellationToken ct) =>
        {
            await svc.UpdateOrderAsync(id, new OrderUpdate(i.Quantity, i.DueDate, i.CustomerId, i.Bales, i.Notes), ct);
            return Results.Ok(await Load(db, svc, id, ct));
        }).RequireAuthorization(ProductionPolicies.Plan);

        g.MapDelete("/{id:int}", async (int id, ProductionService svc, CancellationToken ct) =>
        {
            await svc.DeleteOrderAsync(id, ct);
            return Results.NoContent();
        }).RequireAuthorization(ProductionPolicies.Plan);

        g.MapPost("/{id:int}/refresh-structure", async (int id, EbtDbContext db, ProductionService svc, CancellationToken ct) =>
        {
            await svc.RefreshStructureAsync(id, ct);
            return Results.Ok(await Load(db, svc, id, ct));
        }).RequireAuthorization(ProductionPolicies.Plan);

        g.MapPost("/{id:int}/release", async (int id, ReleaseIn? i, EbtDbContext db, ProductionService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var (_, shortages) = await svc.ReleaseAsync(id, i?.Force ?? false, Who(user), ct);
            return Results.Ok(new ReleaseOut(await Load(db, svc, id, ct), shortages));
        }).RequireAuthorization(ProductionPolicies.Plan);

        void Transition(string path, Func<int, ProductionService, ClaimsPrincipal, ProductionReasonIn?, CancellationToken, Task> action) =>
            g.MapPost($"/{{id:int}}/{path}", async (int id, ProductionReasonIn? i, EbtDbContext db, ProductionService svc, ClaimsPrincipal user, CancellationToken ct) =>
            {
                await action(id, svc, user, i, ct);
                return Results.Ok(await Load(db, svc, id, ct));
            }).RequireAuthorization(ProductionPolicies.Plan);

        Transition("stop", (id, svc, _, i, ct) => svc.StopAsync(id, i?.Reason, ct));
        Transition("resume", (id, svc, _, _, ct) => svc.ResumeAsync(id, ct));
        Transition("finish", (id, svc, _, _, ct) => svc.FinishAsync(id, ct));
        Transition("reopen", (id, svc, _, _, ct) => svc.ReopenAsync(id, ct));
        Transition("close", (id, svc, user, _, ct) => svc.CloseAsync(id, Who(user), ct));
        Transition("close-cost", (id, svc, _, _, ct) => svc.CloseCostAsync(id, ct));
        Transition("cancel", (id, svc, _, i, ct) => svc.CancelAsync(id, i?.Reason, i?.Technical ?? false, ct));

        g.MapPost("/{id:int}/child-orders", async (int id, EbtDbContext db, ProductionService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var created = await svc.CreateChildOrdersAsync(id, Who(user), ct);
            var ids = created.Select(c => c.Id).ToList();
            return Results.Ok(await db.ProductionOrders.AsNoTracking().Where(o => ids.Contains(o.Id)).OrderBy(o => o.Number).Select(Summary).ToListAsync(ct));
        }).RequireAuthorization(ProductionPolicies.Plan);

        g.MapGet("/{id:int}/availability", async (int id, ProductionService svc, CancellationToken ct) => Results.Ok(await svc.AvailabilityAsync(id, ct)));
        g.MapGet("/{id:int}/reconciliation", async (int id, ProductionService svc, CancellationToken ct) => Results.Ok(await svc.ReconcileAsync(id, ct)));

        g.MapPost("/{id:int}/schedule", async (int id, ProductionService svc, CancellationToken ct) =>
            Results.Ok(await svc.ScheduleAsync(id, DateOnly.FromDateTime(DateTime.Today), ct))).RequireAuthorization(ProductionPolicies.Plan);

        g.MapPost("/{id:int}/issues", async (int id, IssueInput i, EbtDbContext db, ProductionService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Created(await svc.IssueAsync(id, i, Who(user), ct))).RequireAuthorization(ProductionPolicies.Materials);

        g.MapPost("/{id:int}/material-returns", async (int id, IssueInput i, ProductionService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Created(await svc.ReturnMaterialAsync(id, i, Who(user), ct))).RequireAuthorization(ProductionPolicies.Materials);

        g.MapPost("/{id:int}/receipts", async (int id, FinishedGoodsInput i, ProductionService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Created(await svc.ReceiveAsync(id, i, Who(user), ct))).RequireAuthorization(ProductionPolicies.Materials);

        g.MapGet("/{id:int}/stock-documents", async (int id, EbtDbContext db, CancellationToken ct) =>
        {
            var reference = await db.ProductionOrders.Where(o => o.Id == id).Select(o => o.Reference).FirstOrDefaultAsync(ct);
            if (reference is null) return Results.NotFound();
            return Results.Ok(await db.StockDocuments.AsNoTracking().Where(d => d.Reference == reference).OrderBy(d => d.Id)
                .Select(d => new StockDocumentSummary(d.Id, d.Type, d.Date, d.Reference, d.SupplierId, d.CustomerId, d.ReversalOfId, d.Reversed, d.CreatedBy, d.CreatedAt, d.Movements.Count)).ToListAsync(ct));
        });

        g.MapPut("/{id:int}/operations/{seq:int}/outsource", async (int id, int seq, OutsourceInput i, EbtDbContext db, ProductionService svc, CancellationToken ct) =>
        {
            await svc.OutsourceAsync(id, seq, i, ct);
            return Results.Ok(await Load(db, svc, id, ct));
        }).RequireAuthorization(ProductionPolicies.Plan);

        g.MapDelete("/{id:int}/operations/{seq:int}/outsource", async (int id, int seq, EbtDbContext db, ProductionService svc, CancellationToken ct) =>
        {
            await svc.OutsourceAsync(id, seq, null, ct);
            return Results.Ok(await Load(db, svc, id, ct));
        }).RequireAuthorization(ProductionPolicies.Plan);

        g.MapPost("/{id:int}/operations/{seq:int}/overrun-releases", async (int id, int seq, OverrunIn i, ProductionService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var r = await svc.ReleaseOverrunAsync(id, seq, i.Quantity, i.Justification, Who(user), ct);
            return Results.Created($"/api/production/orders/{id}", new OverrunOut(r.Id, r.OperationId, r.Quantity, r.Justification, r.ReleasedBy, r.ReleasedAt));
        }).RequireAuthorization(ProductionPolicies.Plan);

        g.MapGet("/{id:int}/overrun-releases", async (int id, EbtDbContext db, CancellationToken ct) =>
            await db.OverrunReleases.AsNoTracking().Where(r => r.Operation!.OrderId == id).OrderBy(r => r.Id)
                .Select(r => new OverrunOut(r.Id, r.OperationId, r.Quantity, r.Justification, r.ReleasedBy, r.ReleasedAt)).ToListAsync(ct));

        g.MapPost("/{id:int}/operations/{seq:int}/outside-shipments", async (int id, int seq, OutsideSendInput i, EbtDbContext db, ProductionService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var s = await svc.SendOutsideAsync(id, seq, i, Who(user), ct);
            return Results.Created($"/api/production/outside-shipments/{s.Id}", await db.OutsideShipments.AsNoTracking().Where(x => x.Id == s.Id).Select(ShipmentProjection).FirstAsync(ct));
        }).RequireAuthorization(ProductionPolicies.Plan);
    }

    private static void MapShopFloor(WebApplication app)
    {
        var shipments = app.MapGroup("/api/production/outside-shipments").WithTags("Production").RequireAuthorization(Policies.Read);

        shipments.MapGet("/", async (EbtDbContext db, int? orderId, int? supplierId, bool? open, CancellationToken ct) =>
        {
            var q = db.OutsideShipments.AsNoTracking();
            if (orderId is { } o) q = q.Where(s => s.Operation!.OrderId == o);
            if (supplierId is { } sp) q = q.Where(s => s.SupplierId == sp);
            if (open == true) q = q.Where(s => s.ReturnedQuantity + s.ScrapQuantity < s.Quantity);
            return await q.OrderBy(s => s.SentOn).ThenBy(s => s.Id).Take(500).Select(ShipmentProjection).ToListAsync(ct);
        });

        shipments.MapGet("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
            await db.OutsideShipments.AsNoTracking().Where(s => s.Id == id).Select(ShipmentProjection).FirstOrDefaultAsync(ct) is { } s ? Results.Ok(s) : Results.NotFound());

        shipments.MapPost("/{id:int}/returns", async (int id, OutsideReturnInput i, EbtDbContext db, ProductionService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var r = await svc.ReturnOutsideAsync(id, i, Who(user), ct);
            return Results.Created($"/api/production/reports/{r.Id}", await db.ProductionReports.AsNoTracking().Where(x => x.Id == r.Id).Select(ReportProjection).FirstAsync(ct));
        }).RequireAuthorization(ProductionPolicies.Plan);

        var reports = app.MapGroup("/api/production/reports").WithTags("Production").RequireAuthorization(Policies.Read);

        reports.MapGet("/", async (EbtDbContext db, int? orderId, int? employeeId, int? machineId, DateOnly? from, DateOnly? to, int? skip, int? take, CancellationToken ct) =>
        {
            var q = db.ProductionReports.AsNoTracking();
            if (orderId is { } o) q = q.Where(r => r.OrderId == o);
            if (employeeId is { } e) q = q.Where(r => r.EmployeeId == e);
            if (machineId is { } m) q = q.Where(r => r.MachineId == m);
            if (from is { } f) q = q.Where(r => r.Date >= f);
            if (to is { } t) q = q.Where(r => r.Date <= t);
            var total = await q.CountAsync(ct);
            var (s, n) = Paging(skip, take);
            var items = await q.OrderByDescending(r => r.Date).ThenByDescending(r => r.Id).Skip(s).Take(n).Select(ReportProjection).ToListAsync(ct);
            return Results.Ok(new Page<ProductionReportOut>(items, total, s, n));
        });

        reports.MapGet("/{id:int}", async (int id, EbtDbContext db, CancellationToken ct) =>
            await db.ProductionReports.AsNoTracking().Where(r => r.Id == id).Select(ReportProjection).FirstOrDefaultAsync(ct) is { } r ? Results.Ok(r) : Results.NotFound());

        reports.MapPost("/", async (ReportInput i, EbtDbContext db, ProductionService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var r = await svc.ReportAsync(i, Who(user), ct);
            return Results.Created($"/api/production/reports/{r.Id}", await db.ProductionReports.AsNoTracking().Where(x => x.Id == r.Id).Select(ReportProjection).FirstAsync(ct));
        }).RequireAuthorization(ProductionPolicies.Plan);

        reports.MapDelete("/{id:int}", async (int id, ProductionService svc, CancellationToken ct) =>
        {
            await svc.DeleteReportAsync(id, ct);
            return Results.NoContent();
        }).RequireAuthorization(ProductionPolicies.Plan);
    }

    private static void MapPlanning(WebApplication app)
    {
        var g = app.MapGroup("/api/production").WithTags("Production").RequireAuthorization(Policies.Read);

        g.MapPost("/availability", async (AvailabilityCheckIn i, ProductionService svc, CancellationToken ct) => Results.Ok(await svc.CheckAvailabilityAsync(i.ProductId, i.Quantity, ct)));

        g.MapPost("/schedule", async (ProductionService svc, CancellationToken ct) =>
            Results.Ok(await svc.ScheduleAsync(null, DateOnly.FromDateTime(DateTime.Today), ct))).RequireAuthorization(ProductionPolicies.Plan);

        g.MapGet("/load", async (ProductionService svc, DateOnly? from, DateOnly? to, string? groupBy, CancellationToken ct) =>
        {
            var start = from ?? DateOnly.FromDateTime(DateTime.Today);
            var byWorkCenter = string.Equals(groupBy, "workCenter", StringComparison.OrdinalIgnoreCase);
            if (groupBy is not null && !byWorkCenter && !string.Equals(groupBy, "machine", StringComparison.OrdinalIgnoreCase))
                return Results.ValidationProblem(Errors().Require(false, "groupBy", "machine or workCenter"));
            return Results.Ok(await svc.LoadAsync(start, to ?? start.AddDays(55), byWorkCenter, ct));
        });
    }

    private static IResult Created(StockDocument doc) =>
        Results.Created($"/api/stock/documents/{doc.Id}", new StockDocumentSummary(doc.Id, doc.Type, doc.Date, doc.Reference, doc.SupplierId, doc.CustomerId, doc.ReversalOfId, doc.Reversed, doc.CreatedBy, doc.CreatedAt, doc.Movements.Count));

    private static async Task<ProductionOrderOut> Load(EbtDbContext db, ProductionService svc, int id, CancellationToken ct)
    {
        var o = await db.ProductionOrders.AsNoTracking().Include(x => x.Product).Include(x => x.Operations).ThenInclude(x => x.Machine).FirstAsync(x => x.Id == id, ct);
        var progress = await svc.ProgressAsync(id, ct);
        var materials = await svc.MaterialStatesAsync(id, ct);
        var children = await db.ProductionOrders.AsNoTracking().Where(x => x.ParentOrderId == id).OrderBy(x => x.Number).Select(Summary).ToListAsync(ct);
        var warnings = new List<string>();
        if (o.Operations.Count == 0) warnings.Add("Sem operação");
        if (materials.Count == 0) warnings.Add("Produto sem materiais");
        foreach (var op in o.Operations.Where(x => !x.External).OrderBy(x => x.Sequence))
        {
            if (op.MachineId is null) warnings.Add($"Operação {op.Sequence} sem máquina");
            if (op.PiecesPerHour is not > 0) warnings.Add($"Operação {op.Sequence} sem peças/hora");
        }
        var ops = o.Operations.OrderBy(x => x.Sequence).Select(op =>
        {
            var p = progress.Operations.First(x => x.OperationId == op.Id);
            return new ProductionOperationOut(op.Id, op.Sequence, op.Description, op.MachineId, op.Machine?.Code, op.WorkCenterId, op.SetupHours, op.PiecesPerHour, op.Operators, op.External, op.SupplierId, op.ExternalLeadDays,
                op.PlannedHours, op.PlannedStart, op.PlannedEnd, p.Good, p.Scrap, p.InTransit, p.OverrunReleased, p.Limit, p.Remaining);
        }).ToList();
        return new ProductionOrderOut(o.Id, o.Kind, o.Number, o.Reference, o.ProductId, o.Product!.Code, o.Product.Name, o.Product.StockUnit, o.CustomerId, o.Quantity, o.DueDate, o.PlannedStart, o.PlannedEnd, o.AdjustedStart, o.AdjustedEnd,
            o.Status, o.StatusReason, o.ParentOrderId, o.PreviousOrderId, o.Bales, o.Notes, o.CreatedBy, o.CreatedAt, o.ReleasedAt, o.FinishedAt, o.ClosedAt, o.ClosedBy, o.CostClosedAt, o.MaterialCost, o.ServiceCost, o.UnitCost,
            progress.Good, progress.Scrap, progress.Received, progress.Receivable, progress.WorkInProcess, ops, materials, children, warnings);
    }

    private static readonly Expression<Func<ProductionOrder, ProductionOrderSummaryOut>> Summary = o =>
        new ProductionOrderSummaryOut(o.Id, o.Kind, o.Number, o.Reference, o.ProductId, o.Product!.Code, o.Product.Name, o.CustomerId, o.Customer != null ? o.Customer.Name : null, o.Quantity, o.DueDate,
            o.PlannedStart, o.PlannedEnd, o.AdjustedStart, o.AdjustedEnd, o.Status, o.ParentOrderId, o.CreatedAt);

    private static readonly Expression<Func<ProductionReport, ProductionReportOut>> ReportProjection = r =>
        new ProductionReportOut(r.Id, r.OrderId, r.Order!.Reference, r.Operation!.Sequence, r.Date, r.ShiftId, r.EmployeeId, r.Employee != null ? r.Employee.Name : null, r.MachineId, r.Machine != null ? r.Machine.Code : null,
            r.StartTime, r.EndTime, r.Hours, r.SetupHours, r.Operators, r.DowntimeHours, r.DowntimeOccurrenceId, r.GoodQuantity, r.ScrapQuantity, r.ScrapOccurrenceId, r.WeightKg, r.OutsideShipmentId, r.Notes, r.ReportedBy, r.ReportedAt);

    private static readonly Expression<Func<OutsideShipment, OutsideShipmentOut>> ShipmentProjection = s =>
        new OutsideShipmentOut(s.Id, s.Operation!.OrderId, s.Operation.Order!.Reference, s.Operation.Sequence, s.SupplierId, s.Supplier!.Name, s.SentOn, s.Quantity, s.ReturnedQuantity, s.ScrapQuantity,
            s.Quantity - s.ReturnedQuantity - s.ScrapQuantity, s.ServiceValue, s.InvoiceNumber, s.Notes);

    private static ProductionSettingsDto ToDto(ProductionSettings s) => new(s.OverrunTolerancePercent, s.HoursPerDay, s.WorkSaturdays, s.IssueLocationId, s.ReceiptLocationId);
    private static (int, int) Paging(int? skip, int? take) => (Math.Max(skip ?? 0, 0), Math.Clamp(take ?? 50, 1, 500));
}
