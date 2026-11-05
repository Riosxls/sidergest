using static Ebt.Core.Services.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Inventory;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Production;

public sealed partial class ProductionService(EbtDbContext db, StockService stock, BomService bom, FiscalService? fiscal = null, ProcessSuggester? suggester = null)
{
    public const string DefaultIssueLocationCode = "ALM";
    public const string DefaultReceiptLocationCode = "PA";

    public static readonly ProductionOrderStatus[] Open = [ProductionOrderStatus.Created, ProductionOrderStatus.Released, ProductionOrderStatus.Stopped, ProductionOrderStatus.InProduction];
    private static readonly ProductionOrderStatus[] Running = [ProductionOrderStatus.Released, ProductionOrderStatus.InProduction];
    private static readonly MovementType[] ConsumptionTypes = [MovementType.Issue, MovementType.AdjustmentIn];

    public static string ReferenceFor(ProductionOrderKind kind, int number) => kind == ProductionOrderKind.Internal ? $"OPI {number}" : $"OF {number}";

    public async Task<ProductionSettings> SettingsAsync(CancellationToken ct = default) =>
        await db.ProductionSettings.FirstOrDefaultAsync(ct) ?? throw new InvalidOperationException("production_settings row missing");

    public async Task<ProductionOrder> CreateOrderAsync(OrderInput i, string? user, CancellationToken ct = default)
    {
        if (i.Quantity <= 0) throw ProductionException.Invalid("quantity", "Must be greater than zero");
        if (i.Bales is < 0) throw ProductionException.Invalid("bales", "Must not be negative");
        var product = await db.Products.AsNoTracking().FirstOrDefaultAsync(p => p.Id == i.ProductId, ct) ?? throw ProductionException.Invalid("productId", "Product not found");
        if (product.Blocked) throw ProductionException.Conflict($"Product {product.Code} is blocked");
        if (i.CustomerId is { } cid && !await db.Customers.AnyAsync(c => c.Id == cid, ct)) throw ProductionException.Invalid("customerId", "Customer not found");
        if (i.ParentOrderId is { } pid)
        {
            var parent = await db.ProductionOrders.AsNoTracking().FirstOrDefaultAsync(o => o.Id == pid, ct) ?? throw ProductionException.Invalid("parentOrderId", "Order not found");
            if (!Open.Contains(parent.Status)) throw ProductionException.Conflict($"Parent order {parent.Reference} is {parent.Status}");
        }
        if (i.PreviousOrderId is { } prev && !await db.ProductionOrders.AnyAsync(o => o.Id == prev, ct)) throw ProductionException.Invalid("previousOrderId", "Order not found");

        return await InTransaction(async () =>
        {
            var sequence = i.Kind == ProductionOrderKind.Internal ? EbtDbContext.InternalOrderNumbers : EbtDbContext.ProductionOrderNumbers;
            #pragma warning disable EF1003 // identifier sanitized by SqlIdentifier.Safe
            var number = await db.Database.SqlQueryRaw<int>("SELECT nextval('" + SqlIdentifier.Safe(sequence) + "')::int AS \"Value\"").SingleAsync(ct);
            #pragma warning restore EF1003
            var order = new ProductionOrder
            {
                Kind = i.Kind, Number = number, Reference = ReferenceFor(i.Kind, number), ProductId = product.Id, CustomerId = i.CustomerId, Quantity = i.Quantity,
                DueDate = i.DueDate, Status = ProductionOrderStatus.Created, ParentOrderId = i.ParentOrderId, PreviousOrderId = i.PreviousOrderId, Bales = i.Bales,
                Notes = Clean(i.Notes), PrimaryTube = Clean(i.PrimaryTube), CreatedBy = user, CreatedAt = DateTimeOffset.UtcNow
            };
            await SnapshotStructureAsync(order, ct, suggestProcess: true);
            db.ProductionOrders.Add(order);
            await db.SaveChangesAsync(ct);
            return order;
        }, ct);
    }

    public async Task<ProductionOrder> UpdateOrderAsync(int id, OrderUpdate i, CancellationToken ct = default)
    {
        if (i.Quantity <= 0) throw ProductionException.Invalid("quantity", "Must be greater than zero");
        return await InTransaction(async () =>
        {
            var order = await LockAsync(id, ct);
            if (!Open.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
            if (i.Quantity != order.Quantity)
            {
                if (order.Status != ProductionOrderStatus.Created) throw ProductionException.Conflict("Quantity can only change before the order is released");
                order.Quantity = i.Quantity;
                foreach (var m in order.Materials) m.RequiredQuantity = Round(m.QuantityPerUnit * i.Quantity);
            }
            if (i.CustomerId is { } cid && !await db.Customers.AnyAsync(c => c.Id == cid, ct)) throw ProductionException.Invalid("customerId", "Customer not found");
            order.DueDate = i.DueDate;
            order.CustomerId = i.CustomerId;
            order.Bales = i.Bales;
            order.Notes = Clean(i.Notes);
            order.PrimaryTube = Clean(i.PrimaryTube);
            await db.SaveChangesAsync(ct);
            return order;
        }, ct);
    }

    public async Task DeleteOrderAsync(int id, CancellationToken ct = default)
    {
        await InTransaction(async () =>
        {
            var order = await LockAsync(id, ct);
            if (order.Status != ProductionOrderStatus.Created) throw ProductionException.Conflict("Only orders that were never released can be deleted; cancel it instead");
            if (await HasActivityAsync(order, ct)) throw ProductionException.Conflict("Order has stock movements or shop-floor reports");
            if (await db.ProductionOrders.AnyAsync(o => o.ParentOrderId == id || o.PreviousOrderId == id, ct)) throw ProductionException.Conflict("Other orders refer to this order");
            db.ProductionOrders.Remove(order);
            await db.SaveChangesAsync(ct);
            return 0;
        }, ct);
    }

    public async Task<ProductionOrder> RefreshStructureAsync(int id, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var order = await LockAsync(id, ct);
            if (order.Status != ProductionOrderStatus.Created) throw ProductionException.Conflict("Structure can only be refreshed before release");
            if (await db.ProductionReports.AnyAsync(r => r.OrderId == id, ct)) throw ProductionException.Conflict("Order has shop-floor reports");
            db.ProductionOrderMaterials.RemoveRange(order.Materials);
            db.ProductionOrderOperations.RemoveRange(order.Operations);
            await db.SaveChangesAsync(ct);
            order.Materials = new();
            order.Operations = new();
            await SnapshotStructureAsync(order, ct, suggestProcess: true);
            await db.SaveChangesAsync(ct);
            return order;
        }, ct);
    }

    public async Task<(ProductionOrder Order, IReadOnlyList<AvailabilityLine> Shortages)> ReleaseAsync(int id, bool force, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var order = await LockAsync(id, ct);
            if (order.Status != ProductionOrderStatus.Created) throw ProductionException.Conflict($"Order is {order.Status}; only created orders can be released");
            if (order.ParentOrderId is { } pid && await db.ProductionOrders.Where(o => o.Id == pid).Select(o => o.Status).FirstAsync(ct) is var ps && !Open.Contains(ps))
                throw ProductionException.Conflict($"Parent order is {ps}");
            var settings = await stock.SettingsAsync(ct);
            var shortages = new List<AvailabilityLine>();
            var states = await MaterialStatesAsync(order, ct);
            foreach (var line in order.Materials.OrderBy(m => m.OperationSequence).ThenBy(m => m.Id))
            {
                var state = states.First(s => s.Id == line.Id);
                if (state.Remaining <= 0) continue;
                var item = new StockItem(line.MaterialId, line.ComponentProductId);
                var free = settings.AllowNegativeStock ? state.Remaining : Math.Max(0, await stock.FreeQuantityAsync(item, null, ct));
                var reserve = Math.Min(free, state.Remaining);
                if (reserve < state.Remaining) shortages.Add(new AvailabilityLine(line.Id, line.MaterialId, line.ComponentProductId, state.Code, state.Description, line.Unit, line.RequiredQuantity, state.Issued, state.Remaining, 0, free, 0, state.Remaining - reserve));
                if (reserve <= 0 || !force && shortages.Count > 0) continue;
                var r = await stock.ReserveAsync(item, null, reserve, order.Reference, order.PlannedStart ?? order.DueDate, user ?? "system", ct);
                line.ReservationId = r.Id;
            }
            if (shortages.Count > 0 && !force)
                throw ProductionException.Conflict("Missing material: " + string.Join("; ", shortages.Select(s => $"{s.Code} short by {s.Shortage:0.####} {s.Unit}")));
            order.Status = ProductionOrderStatus.Released;
            order.ReleasedAt = DateTimeOffset.UtcNow;
            order.StatusReason = null;
            await db.SaveChangesAsync(ct);
            return (order, (IReadOnlyList<AvailabilityLine>)shortages);
        }, ct);
    }

    public Task<ProductionOrder> StopAsync(int id, string? reason, CancellationToken ct = default) => ChangeStatusAsync(id, ct, order =>
    {
        if (!Running.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
        if (Clean(reason) is null) throw ProductionException.Invalid("reason", "Required");
        order.StatusReason = Clean(reason);
        order.Status = ProductionOrderStatus.Stopped;
        return Task.CompletedTask;
    });

    public Task<ProductionOrder> ResumeAsync(int id, CancellationToken ct = default) => ChangeStatusAsync(id, ct, async order =>
    {
        if (order.Status != ProductionOrderStatus.Stopped) throw ProductionException.Conflict($"Order is {order.Status}");
        order.Status = await HasActivityAsync(order, ct) ? ProductionOrderStatus.InProduction : ProductionOrderStatus.Released;
        order.StatusReason = null;
    });

    public Task<ProductionOrder> FinishAsync(int id, CancellationToken ct = default) => ChangeStatusAsync(id, ct, async order =>
    {
        if (!Running.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
        await ReleaseReservationsAsync(order, ct);
        order.Status = ProductionOrderStatus.Finished;
        order.FinishedAt = DateTimeOffset.UtcNow;
    });

    public Task<ProductionOrder> ReopenAsync(int id, CancellationToken ct = default) => ChangeStatusAsync(id, ct, order =>
    {
        if (order.Status != ProductionOrderStatus.Finished) throw ProductionException.Conflict("Only finished orders can be reopened");
        order.Status = ProductionOrderStatus.InProduction;
        order.FinishedAt = null;
        return Task.CompletedTask;
    });

    public Task<ProductionOrder> CloseAsync(int id, string? user, CancellationToken ct = default) => ChangeStatusAsync(id, ct, async order =>
    {
        if (order.Status != ProductionOrderStatus.Finished) throw ProductionException.Conflict("Finish the order before closing it");
        if (await db.ProductionOrders.Where(o => o.ParentOrderId == order.Id && Open.Contains(o.Status)).Select(o => o.Reference).FirstOrDefaultAsync(ct) is { } child)
            throw ProductionException.Conflict($"Subassembly order {child} is still open");
        if (await db.OutsideShipments.AnyAsync(s => s.Operation!.OrderId == order.Id && s.ReturnedQuantity + s.ScrapQuantity < s.Quantity, ct))
            throw ProductionException.Conflict("Material is still at a third party for this order");
        order.Status = ProductionOrderStatus.Closed;
        order.ClosedAt = DateTimeOffset.UtcNow;
        order.ClosedBy = user;
    });

    public Task<ProductionOrder> CloseCostAsync(int id, CancellationToken ct = default) => ChangeStatusAsync(id, ct, async order =>
    {
        if (order.Status != ProductionOrderStatus.Closed) throw ProductionException.Conflict("Close the order before closing its cost");
        if (order.CostClosedAt is not null) throw ProductionException.Conflict("Cost is already closed");
        var rec = await ReconcileAsync(order, ct);
        order.MaterialCost = rec.MaterialCost;
        order.ServiceCost = rec.ServiceCost;
        order.UnitCost = rec.UnitCost;
        // True-up: the receipts were costed with what had been issued at the time (a partial receipt sees a fraction of the final cost), so they take the final unit cost.
        if (rec.UnitCost is > 0 and var final)
        {
            var receipts = await db.StockMovements.AsNoTracking()
                .Where(m => m.ProductId == order.ProductId && m.Type == MovementType.ProductionReceipt && (m.Document!.OrderId == order.Id || (m.Document.OrderId == null && m.Document.Reference == order.Reference)))
                .Select(m => m.Id).ToListAsync(ct);
            await stock.RestateCostAsync(receipts, final, ct);
        }
        order.CostClosedAt = DateTimeOffset.UtcNow;
    });

    public Task<ProductionOrder> CancelAsync(int id, string? reason, bool technical, CancellationToken ct = default) => ChangeStatusAsync(id, ct, async order =>
    {
        if (!Open.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
        if (Clean(reason) is null) throw ProductionException.Invalid("reason", "Required");
        if (!technical && await HasActivityAsync(order, ct)) throw ProductionException.Conflict("Order has stock movements or shop-floor reports; use a technical cancel");
        if (await db.ProductionOrders.Where(o => o.ParentOrderId == order.Id && Open.Contains(o.Status)).Select(o => o.Reference).FirstOrDefaultAsync(ct) is { } child)
            throw ProductionException.Conflict($"Cancel subassembly order {child} first");
        await ReleaseReservationsAsync(order, ct);
        order.Status = ProductionOrderStatus.Cancelled;
        order.StatusReason = (technical ? "Technical: " : "") + Clean(reason);
    });

    private async Task ReleaseReservationsAsync(ProductionOrder order, CancellationToken ct)
    {
        var ids = order.Materials.Select(m => m.ReservationId).OfType<int>().ToList();
        foreach (var r in await db.StockReservations.Where(r => ids.Contains(r.Id) && r.Status == ReservationStatus.Open).Select(r => r.Id).ToListAsync(ct))
            await stock.ReleaseAsync(r, ct);
    }

    private async Task<bool> HasActivityAsync(ProductionOrder order, CancellationToken ct) =>
        await db.ProductionReports.AnyAsync(r => r.OrderId == order.Id, ct)
        || await db.StockDocuments.AnyAsync(d => d.OrderId == order.Id || (d.OrderId == null && d.Reference == order.Reference), ct)
        || await db.OutsideShipments.AnyAsync(s => s.Operation!.OrderId == order.Id, ct);

    private async Task<int> LocationAsync(int? requested, int? configured, string fallbackCode, string field, CancellationToken ct)
    {
        if (requested is { } id)
        {
            if (!await db.StockLocations.AnyAsync(l => l.Id == id && l.Active && l.Kind != StockLocationKind.ThirdParty, ct)) throw ProductionException.Invalid(field, "Unknown, inactive or third-party location");
            return id;
        }
        if (configured is { } c) return c;
        return await db.StockLocations.Where(l => l.Code == fallbackCode && l.Active).Select(l => (int?)l.Id).FirstOrDefaultAsync(ct)
               ?? throw ProductionException.Invalid(field, $"Give a location, set one in /api/production/settings or create stock location {fallbackCode}");
    }

    private async Task<ProductionOrder> ChangeStatusAsync(int id, CancellationToken ct, Func<ProductionOrder, Task> change) =>
        await InTransaction(async () =>
        {
            var order = await LockAsync(id, ct);
            await change(order);
            await db.SaveChangesAsync(ct);
            return order;
        }, ct);

    private async Task<ProductionOrder> LockAsync(int id, CancellationToken ct)
    {
        var found = await db.Database.SqlQuery<int>($"SELECT id AS \"Value\" FROM production_orders WHERE id = {id} FOR UPDATE").ToListAsync(ct);
        if (found.Count == 0) throw ProductionException.NotFound("Order");
        var order = await db.ProductionOrders.Include(o => o.Operations).Include(o => o.Materials).FirstAsync(o => o.Id == id, ct);
        await db.Entry(order).ReloadAsync(ct);
        return order;
    }

    private Task<T> InTransaction<T>(Func<Task<T>> work, CancellationToken ct) => db.InTransactionAsync(work, ct);

    private static decimal Round(decimal d) => Math.Round(d, 4, MidpointRounding.AwayFromZero);
}
