using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Production;

public sealed partial class ProductionService(EbtDbContext db, StockService stock, BomService bom)
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
            var number = await db.Database.SqlQueryRaw<int>($"SELECT nextval('{sequence}')::int AS \"Value\"").SingleAsync(ct);
            var order = new ProductionOrder
            {
                Kind = i.Kind, Number = number, Reference = ReferenceFor(i.Kind, number), ProductId = product.Id, CustomerId = i.CustomerId, Quantity = i.Quantity,
                DueDate = i.DueDate, Status = ProductionOrderStatus.Created, ParentOrderId = i.ParentOrderId, PreviousOrderId = i.PreviousOrderId, Bales = i.Bales,
                Notes = Clean(i.Notes), CreatedBy = user, CreatedAt = DateTimeOffset.UtcNow
            };
            await SnapshotStructureAsync(order, ct);
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
            await SnapshotStructureAsync(order, ct);
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

    public async Task<IReadOnlyList<ProductionOrder>> CreateChildOrdersAsync(int id, string? user, CancellationToken ct = default)
    {
        var order = await db.ProductionOrders.AsNoTracking().Include(o => o.Materials).FirstOrDefaultAsync(o => o.Id == id, ct) ?? throw ProductionException.NotFound("Order");
        if (!Open.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
        var availability = await AvailabilityAsync(id, ct);
        var children = await db.ProductionOrders.AsNoTracking().Where(o => o.ParentOrderId == id && Open.Contains(o.Status)).ToListAsync(ct);
        var created = new List<ProductionOrder>();
        foreach (var g in availability.Lines.Where(l => l.ProductId is not null).GroupBy(l => l.ProductId!.Value))
        {
            var inProgress = 0m;
            foreach (var c in children.Where(c => c.ProductId == g.Key))
                inProgress += Math.Max(0, c.Quantity - (await ProgressAsync(c.Id, ct)).Received);
            var shortage = g.Sum(l => l.Shortage) - inProgress;
            if (shortage <= 0) continue;
            created.Add(await CreateOrderAsync(new OrderInput(g.Key, Math.Ceiling(shortage), order.PlannedStart ?? order.DueDate, ProductionOrderKind.Standard, order.CustomerId, id), user, ct));
        }
        return created;
    }

    public async Task<AvailabilityResult> AvailabilityAsync(int id, CancellationToken ct = default)
    {
        var order = await db.ProductionOrders.AsNoTracking().Include(o => o.Materials).FirstOrDefaultAsync(o => o.Id == id, ct) ?? throw ProductionException.NotFound("Order");
        var states = await MaterialStatesAsync(order, ct);
        var onOrder = await OnOrderAsync(states.Select(s => s.MaterialId).OfType<int>().ToList(), ct);
        var lines = new List<AvailabilityLine>();
        var free = new Dictionary<StockItem, decimal>();
        foreach (var s in states)
        {
            var item = new StockItem(s.MaterialId, s.ComponentProductId);
            if (!free.TryGetValue(item, out var f)) f = free[item] = Math.Max(0, await stock.FreeQuantityAsync(item, null, ct));
            var covered = Math.Min(s.Remaining, s.Reserved + f);
            free[item] = Math.Max(0, f - Math.Max(0, covered - s.Reserved));
            lines.Add(new AvailabilityLine(s.Id, s.MaterialId, s.ComponentProductId, s.Code, s.Description, s.Unit, s.Required, s.Issued, s.Remaining, s.Reserved, f,
                s.MaterialId is { } m ? onOrder.GetValueOrDefault(m) : 0, Math.Max(0, s.Remaining - covered)));
        }
        return new AvailabilityResult(lines.All(l => l.Shortage == 0), lines);
    }

    public async Task<AvailabilityResult> CheckAvailabilityAsync(int productId, decimal quantity, CancellationToken ct = default)
    {
        if (quantity <= 0) throw ProductionException.Invalid("quantity", "Must be greater than zero");
        BomExplosion? explosion;
        try { explosion = await bom.ExplodeAsync(productId, quantity, ct); }
        catch (BomCycleException e) { throw ProductionException.Conflict(e.Message); }
        if (explosion is null) throw ProductionException.NotFound("Product");
        var onOrder = await OnOrderAsync(explosion.Materials.Select(m => m.MaterialId).ToList(), ct);
        var lines = new List<AvailabilityLine>();
        foreach (var m in explosion.Materials)
        {
            var free = Math.Max(0, await stock.FreeQuantityAsync(new StockItem(m.MaterialId, null), null, ct));
            var req = Round(m.TotalQuantity);
            lines.Add(new AvailabilityLine(null, m.MaterialId, null, m.Code, m.Description, m.Unit, req, 0, req, 0, free, onOrder.GetValueOrDefault(m.MaterialId), Math.Max(0, req - free)));
        }
        return new AvailabilityResult(lines.All(l => l.Shortage == 0), lines);
    }

    public async Task<StockDocument> IssueAsync(int id, IssueInput i, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var order = await LockAsync(id, ct);
            if (!Running.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}; material can only be issued to released orders");
            var locationId = await LocationAsync(i.LocationId, (await SettingsAsync(ct)).IssueLocationId, DefaultIssueLocationCode, "locationId", ct);
            var states = await MaterialStatesAsync(order, ct);
            var requests = i.Lines is { Count: > 0 } ? i.Lines : states.Where(s => s.Remaining > 0).Select(s => new IssueLineInput(s.Id, s.Remaining)).ToList();
            if (requests.Count == 0) throw ProductionException.Conflict("Nothing left to issue");
            var lines = new List<StockLine>();
            var reservationUse = new Dictionary<int, decimal>();
            foreach (var (r, idx) in requests.Select((r, idx) => (r, idx)))
            {
                if (r.Quantity <= 0) throw ProductionException.Invalid($"lines[{idx}].quantity", "Must be greater than zero");
                var line = order.Materials.FirstOrDefault(m => m.Id == r.MaterialLineId) ?? throw ProductionException.Invalid($"lines[{idx}].materialLineId", "Not a material of this order");
                var state = states.First(s => s.Id == line.Id);
                var fromReservation = 0m;
                if (state.ReservationId is { } rid && state.Reserved > 0)
                {
                    fromReservation = Math.Min(r.Quantity, state.Reserved - reservationUse.GetValueOrDefault(rid));
                    reservationUse[rid] = reservationUse.GetValueOrDefault(rid) + fromReservation;
                }
                if (fromReservation > 0) lines.Add(new StockLine(line.MaterialId, line.ComponentProductId, locationId, fromReservation, LotId: r.LotId, ReservationId: state.ReservationId));
                if (r.Quantity - fromReservation > 0) lines.Add(new StockLine(line.MaterialId, line.ComponentProductId, locationId, r.Quantity - fromReservation, LotId: r.LotId));
            }
            var doc = await stock.PostAsync(new StockPost(MovementType.Issue, i.Date, lines, order.Reference, Notes: $"Requisição {order.Reference}"), user ?? "system", ct);
            if (order.Status == ProductionOrderStatus.Released) order.Status = ProductionOrderStatus.InProduction;
            await db.SaveChangesAsync(ct);
            return doc;
        }, ct);
    }

    public async Task<StockDocument> ReturnMaterialAsync(int id, IssueInput i, string? user, CancellationToken ct = default)
    {
        if (i.Lines is not { Count: > 0 }) throw ProductionException.Invalid("lines", "At least one line");
        return await InTransaction(async () =>
        {
            var order = await LockAsync(id, ct);
            if (order.Status is ProductionOrderStatus.Closed or ProductionOrderStatus.Created) throw ProductionException.Conflict($"Order is {order.Status}");
            var locationId = await LocationAsync(i.LocationId, (await SettingsAsync(ct)).IssueLocationId, DefaultIssueLocationCode, "locationId", ct);
            var consumption = await ConsumptionAsync(order.Reference, ct);
            var lines = new List<StockLine>();
            var left = consumption.ToDictionary(c => new StockItem(c.MaterialId, c.ProductId), c => c.Quantity);
            foreach (var (r, idx) in i.Lines.Select((r, idx) => (r, idx)))
            {
                if (r.Quantity <= 0) throw ProductionException.Invalid($"lines[{idx}].quantity", "Must be greater than zero");
                var line = order.Materials.FirstOrDefault(m => m.Id == r.MaterialLineId) ?? throw ProductionException.Invalid($"lines[{idx}].materialLineId", "Not a material of this order");
                var item = new StockItem(line.MaterialId, line.ComponentProductId);
                var issued = left.GetValueOrDefault(item);
                if (r.Quantity > issued) throw ProductionException.Conflict($"Only {issued:0.####} {line.Unit} of this item is issued to {order.Reference}");
                left[item] = issued - r.Quantity;
                var c = consumption.First(x => new StockItem(x.MaterialId, x.ProductId) == item);
                lines.Add(new StockLine(line.MaterialId, line.ComponentProductId, locationId, r.Quantity, LotId: r.LotId, UnitCost: c.Quantity > 0 ? Math.Round(c.Value / c.Quantity, 6) : 0));
            }
            return await stock.PostAsync(new StockPost(MovementType.AdjustmentIn, i.Date, lines, order.Reference, Notes: $"Devolução {order.Reference}"), user ?? "system", ct);
        }, ct);
    }

    public async Task<StockDocument> ReceiveAsync(int id, FinishedGoodsInput i, string? user, CancellationToken ct = default)
    {
        if (i.Quantity <= 0) throw ProductionException.Invalid("quantity", "Must be greater than zero");
        return await InTransaction(async () =>
        {
            var order = await LockAsync(id, ct);
            if (!Running.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
            var locationId = await LocationAsync(i.LocationId, (await SettingsAsync(ct)).ReceiptLocationId, DefaultReceiptLocationCode, "locationId", ct);
            var progress = await ProgressAsync(order, ct);
            if (i.Quantity > progress.Receivable)
                throw ProductionException.Conflict(order.Operations.Count > 0
                    ? $"Only {progress.Receivable:0.####} reported as good at the last operation and not yet in stock"
                    : $"Only {progress.Receivable:0.####} left to receive including tolerance");
            var consumption = await ConsumptionAsync(order.Reference, ct);
            var service = await db.OutsideShipments.Where(s => s.Operation!.OrderId == id).SumAsync(s => s.ServiceValue, ct);
            var basis = Math.Max(order.Quantity, progress.Received + i.Quantity);
            var unitCost = Math.Round((consumption.Sum(c => c.Value) + service) / basis, 6);
            var doc = await stock.PostAsync(new StockPost(MovementType.ProductionReceipt, i.Date,
                [new StockLine(null, order.ProductId, locationId, i.Quantity, LotCode: Clean(i.LotCode) ?? order.Reference.Replace(" ", ""), UnitCost: Math.Max(0, unitCost))],
                order.Reference, CustomerId: order.CustomerId, Notes: $"Entrada PA {order.Reference}"), user ?? "system", ct);
            if (order.Status == ProductionOrderStatus.Released) order.Status = ProductionOrderStatus.InProduction;
            await db.SaveChangesAsync(ct);
            return doc;
        }, ct);
    }

    public async Task<OrderProgress> ProgressAsync(int id, CancellationToken ct = default)
    {
        var order = await db.ProductionOrders.AsNoTracking().Include(o => o.Operations).FirstOrDefaultAsync(o => o.Id == id, ct) ?? throw ProductionException.NotFound("Order");
        return await ProgressAsync(order, ct);
    }

    public async Task<IReadOnlyList<MaterialLineState>> MaterialStatesAsync(int id, CancellationToken ct = default)
    {
        var order = await db.ProductionOrders.AsNoTracking().Include(o => o.Materials).FirstOrDefaultAsync(o => o.Id == id, ct) ?? throw ProductionException.NotFound("Order");
        return await MaterialStatesAsync(order, ct);
    }

    public async Task<Reconciliation> ReconcileAsync(int id, CancellationToken ct = default)
    {
        var order = await db.ProductionOrders.AsNoTracking().Include(o => o.Materials).Include(o => o.Operations).FirstOrDefaultAsync(o => o.Id == id, ct) ?? throw ProductionException.NotFound("Order");
        return await ReconcileAsync(order, ct);
    }

    private async Task<Reconciliation> ReconcileAsync(ProductionOrder order, CancellationToken ct)
    {
        var progress = await ProgressAsync(order, ct);
        var consumption = await ConsumptionAsync(order.Reference, ct);
        var service = await db.OutsideShipments.Where(s => s.Operation!.OrderId == order.Id).SumAsync(s => s.ServiceValue, ct);
        var scrapByOp = progress.Operations.ToDictionary(o => o.Sequence, o => o.Scrap);
        var materialIds = order.Materials.Select(m => m.MaterialId).OfType<int>().Distinct().ToList();
        var prices = await db.SupplierMaterials.AsNoTracking().Where(s => materialIds.Contains(s.MaterialId) && s.LastUnitPrice != null)
            .GroupBy(s => s.MaterialId).Select(g => new { g.Key, Price = g.OrderByDescending(s => s.LastPurchaseDate).Select(s => s.LastUnitPrice!.Value).First() })
            .ToDictionaryAsync(x => x.Key, x => x.Price, ct);
        var codes = await ItemCodesAsync(order.Materials, ct);
        var lines = new List<ReconciliationLine>();
        foreach (var g in order.Materials.GroupBy(m => new StockItem(m.MaterialId, m.ComponentProductId)))
        {
            var perUnit = g.Sum(m => m.QuantityPerUnit);
            var inScrap = Round(g.Sum(m => m.QuantityPerUnit * scrapByOp.Where(s => s.Key >= m.OperationSequence).Sum(s => s.Value)));
            var inFg = Round(perUnit * progress.Received);
            var issued = consumption.FirstOrDefault(c => new StockItem(c.MaterialId, c.ProductId) == g.Key)?.Quantity ?? 0m;
            var price = g.Key.MaterialId is { } mid ? prices.TryGetValue(mid, out var p) ? p : await stock.CurrentAverageAsync(mid, Ebt.Core.Services.Clock.Today(), ct) : 0m;
            var balance = issued - inScrap - inFg;
            lines.Add(new ReconciliationLine(g.Key.MaterialId, g.Key.ProductId, codes[g.Key].Code, g.First().Unit, perUnit, Round(g.Sum(m => m.RequiredQuantity)), issued, inScrap, inFg, balance, price, Math.Round(balance * price, 2)));
        }
        var materialCost = Math.Round(consumption.Sum(c => c.Value), 4);
        var unitCost = progress.Received > 0 ? Math.Round((materialCost + service) / progress.Received, 6) : (decimal?)null;
        return new Reconciliation(order.Id, order.Reference, order.Quantity, progress.Good, progress.Scrap, progress.Received, progress.WorkInProcess, materialCost, service, unitCost, lines);
    }

    private async Task<OrderProgress> ProgressAsync(ProductionOrder order, CancellationToken ct)
    {
        var tolerance = (await SettingsAsync(ct)).OverrunTolerancePercent;
        var reports = await db.ProductionReports.AsNoTracking().Where(r => r.OrderId == order.Id)
            .GroupBy(r => r.OperationId).Select(g => new { g.Key, Good = g.Sum(r => r.GoodQuantity), Scrap = g.Sum(r => r.ScrapQuantity) }).ToDictionaryAsync(x => x.Key, ct);
        var opIds = order.Operations.Select(o => o.Id).ToList();
        var transit = await db.OutsideShipments.AsNoTracking().Where(s => opIds.Contains(s.OperationId))
            .GroupBy(s => s.OperationId).Select(g => new { g.Key, Qty = g.Sum(s => s.Quantity - s.ReturnedQuantity - s.ScrapQuantity) }).ToDictionaryAsync(x => x.Key, x => x.Qty, ct);
        var received = await db.StockMovements.AsNoTracking()
            .Where(m => m.Document!.Reference == order.Reference && m.Type == MovementType.ProductionReceipt && m.ProductId == order.ProductId).SumAsync(m => m.Quantity, ct);
        var withTolerance = Round(order.Quantity * (1 + tolerance / 100m));

        var ops = new List<OperationProgress>();
        decimal? previousGood = null;
        foreach (var op in order.Operations.OrderBy(o => o.Sequence))
        {
            var r = reports.GetValueOrDefault(op.Id);
            var good = r?.Good ?? 0m;
            var scrap = r?.Scrap ?? 0m;
            var inTransit = transit.GetValueOrDefault(op.Id);
            var limit = (previousGood ?? withTolerance) + op.OverrunReleased;
            ops.Add(new OperationProgress(op.Id, op.Sequence, op.External, good, scrap, inTransit, op.OverrunReleased, limit, limit - good - scrap - inTransit));
            previousGood = good;
        }
        var lastGood = ops.Count > 0 ? ops[^1].Good : received;
        var receivable = ops.Count > 0 ? lastGood - received : withTolerance - received;
        var totalScrap = ops.Sum(o => o.Scrap);
        var wip = ops.Count > 0 ? ops[0].Good + ops[0].Scrap + ops[0].InTransit - totalScrap - received : 0m;
        return new OrderProgress(ops, lastGood, totalScrap, received, Math.Max(0, receivable), Math.Max(0, wip));
    }

    private async Task<List<MaterialLineState>> MaterialStatesAsync(ProductionOrder order, CancellationToken ct)
    {
        var consumption = (await ConsumptionAsync(order.Reference, ct)).ToDictionary(c => new StockItem(c.MaterialId, c.ProductId), c => c.Quantity);
        var reservationIds = order.Materials.Select(m => m.ReservationId).OfType<int>().ToList();
        var reservations = await db.StockReservations.AsNoTracking().Where(r => reservationIds.Contains(r.Id))
            .ToDictionaryAsync(r => r.Id, r => r.Status == ReservationStatus.Open ? r.Quantity - r.Consumed : 0m, ct);
        var codes = await ItemCodesAsync(order.Materials, ct);
        var result = new List<MaterialLineState>();
        foreach (var g in order.Materials.GroupBy(m => new StockItem(m.MaterialId, m.ComponentProductId)))
        {
            var issued = consumption.GetValueOrDefault(g.Key);
            var ordered = g.OrderBy(m => m.OperationSequence).ThenBy(m => m.Id).ToList();
            foreach (var (m, idx) in ordered.Select((m, idx) => (m, idx)))
            {
                var share = idx == ordered.Count - 1 ? issued : Math.Min(Math.Max(issued, 0), m.RequiredQuantity);
                issued -= share;
                var reserved = m.ReservationId is { } rid ? reservations.GetValueOrDefault(rid) : 0m;
                var (code, description) = codes[g.Key];
                result.Add(new MaterialLineState(m.Id, m.OperationSequence, m.MaterialId, m.ComponentProductId, code, description, m.Unit, m.QuantityPerUnit, m.RequiredQuantity, share,
                    Math.Max(0, m.RequiredQuantity - share), m.ReservationId, reserved));
            }
        }
        return result.OrderBy(r => r.OperationSequence).ThenBy(r => r.Id).ToList();
    }

    public async Task<List<ItemConsumption>> ConsumptionAsync(string reference, CancellationToken ct) =>
        await db.StockMovements.AsNoTracking()
            .Where(m => m.Document!.Reference == reference && ConsumptionTypes.Contains(m.Type))
            .GroupBy(m => new { m.MaterialId, m.ProductId })
            .Select(g => new ItemConsumption(g.Key.MaterialId, g.Key.ProductId, -g.Sum(m => m.Quantity), -g.Sum(m => m.Quantity * m.UnitCost)))
            .ToListAsync(ct);

    private async Task<Dictionary<StockItem, (string Code, string Description)>> ItemCodesAsync(IEnumerable<ProductionOrderMaterial> lines, CancellationToken ct)
    {
        var list = lines.ToList();
        var mids = list.Select(l => l.MaterialId).OfType<int>().Distinct().ToList();
        var pids = list.Select(l => l.ComponentProductId).OfType<int>().Distinct().ToList();
        var result = new Dictionary<StockItem, (string, string)>();
        foreach (var m in await db.Materials.AsNoTracking().Where(m => mids.Contains(m.Id)).Select(m => new { m.Id, m.Code, m.Description }).ToListAsync(ct))
            result[new StockItem(m.Id, null)] = (m.Code, m.Description);
        foreach (var p in await db.Products.AsNoTracking().Where(p => pids.Contains(p.Id)).Select(p => new { p.Id, p.Code, p.Name }).ToListAsync(ct))
            result[new StockItem(null, p.Id)] = (p.Code, p.Name);
        return result;
    }

    private async Task<Dictionary<int, decimal>> OnOrderAsync(List<int> materialIds, CancellationToken ct) =>
        await db.PurchaseOrderLines.AsNoTracking()
            .Where(l => l.MaterialId != null && materialIds.Contains(l.MaterialId.Value) && !l.Closed && l.ReceivedQuantity < l.Quantity
                        && (l.PurchaseOrder!.Status == PurchaseOrderStatus.Open || l.PurchaseOrder.Status == PurchaseOrderStatus.PartiallyReceived))
            .GroupBy(l => l.MaterialId!.Value)
            .Select(g => new { g.Key, Qty = g.Sum(l => l.Quantity - l.ReceivedQuantity) })
            .ToDictionaryAsync(x => x.Key, x => x.Qty, ct);

    public async Task SnapshotStructureAsync(ProductionOrder order, CancellationToken ct)
    {
        var routing = await db.RoutingOperations.AsNoTracking()
            .Include(o => o.Items).ThenInclude(i => i.Material)
            .Include(o => o.Items).ThenInclude(i => i.ComponentProduct)
            .Where(o => o.ProductId == order.ProductId).OrderBy(o => o.Sequence).ToListAsync(ct);
        foreach (var op in routing)
        {
            order.Operations.Add(new ProductionOrderOperation
            {
                Sequence = op.Sequence, Description = op.Description, MachineId = op.MachineId, WorkCenterId = op.WorkCenterId,
                SetupHours = op.SetupHours, PiecesPerHour = op.PiecesPerHour, Operators = op.Operators
            });
            foreach (var g in op.Items.GroupBy(i => (i.MaterialId, i.ComponentProductId)))
            {
                var perUnit = g.Sum(i => i.Quantity * i.Factor);
                var first = g.First();
                order.Materials.Add(new ProductionOrderMaterial
                {
                    OperationSequence = op.Sequence, MaterialId = first.MaterialId, ComponentProductId = first.ComponentProductId, QuantityPerUnit = perUnit,
                    RequiredQuantity = Round(perUnit * order.Quantity), Unit = first.Material?.StockUnit ?? first.ComponentProduct!.StockUnit
                });
            }
        }
    }

    private async Task ReleaseReservationsAsync(ProductionOrder order, CancellationToken ct)
    {
        var ids = order.Materials.Select(m => m.ReservationId).OfType<int>().ToList();
        foreach (var r in await db.StockReservations.Where(r => ids.Contains(r.Id) && r.Status == ReservationStatus.Open).Select(r => r.Id).ToListAsync(ct))
            await stock.ReleaseAsync(r, ct);
    }

    private async Task<bool> HasActivityAsync(ProductionOrder order, CancellationToken ct) =>
        await db.ProductionReports.AnyAsync(r => r.OrderId == order.Id, ct)
        || await db.StockDocuments.AnyAsync(d => d.Reference == order.Reference, ct)
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

    private async Task<T> InTransaction<T>(Func<Task<T>> work, CancellationToken ct)
    {
        if (db.Database.CurrentTransaction is not null) return await work();
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        try
        {
            var result = await work();
            await tx.CommitAsync(ct);
            return result;
        }
        catch
        {
            await tx.RollbackAsync(CancellationToken.None);
            db.ChangeTracker.Clear();
            throw;
        }
    }

    private static decimal Round(decimal d) => Math.Round(d, 4, MidpointRounding.AwayFromZero);
    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}
