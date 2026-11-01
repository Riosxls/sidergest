using static Ebt.Core.Services.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Inventory;
using Ebt.Core.Services;
using Ebt.Core.Production;
using Ebt.Core.Viability;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Production;

/// <summary>Material availability for production orders: subassembly orders and shortage checks.</summary>
public sealed partial class ProductionService
{
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
}
