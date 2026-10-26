using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Services;

public record BomNode(int Level, int ProductId, string ProductCode, int OperationSequence, int? MaterialId, int? ComponentProductId, string Code, string Description, string Unit, decimal QuantityPerUnit, decimal TotalQuantity);
public record MaterialRequirement(int MaterialId, string Code, string Description, string Unit, decimal TotalQuantity);
public record BomExplosion(int ProductId, string ProductCode, decimal Quantity, IReadOnlyList<BomNode> Lines, IReadOnlyList<MaterialRequirement> Materials);
public record WhereUsedEntry(int ProductId, string ProductCode, string ProductName, int OperationSequence, decimal Quantity, string Unit);

public class BomCycleException(string message) : Exception(message);

public class BomService(EbtDbContext db)
{
    public const int MaxDepth = 25;

    public async Task<BomExplosion?> ExplodeAsync(int productId, decimal quantity, CancellationToken ct = default)
    {
        var root = await db.Products.AsNoTracking().FirstOrDefaultAsync(p => p.Id == productId, ct);
        if (root is null) return null;

        var structure = await LoadStructureAsync(productId, ct);
        var lines = new List<BomNode>();
        var totals = new Dictionary<int, (Material Material, decimal Qty)>();

        void Walk(int pid, decimal parentQty, int level, HashSet<int> path)
        {
            if (level > MaxDepth) throw new BomCycleException($"BOM deeper than {MaxDepth} levels at product {pid}");
            if (!structure.TryGetValue(pid, out var items)) return;
            foreach (var (seq, item) in items)
            {
                var perUnit = item.Quantity * item.Factor;
                var total = perUnit * parentQty;
                if (item.Material is { } m)
                {
                    lines.Add(new BomNode(level, pid, item.RoutingOperation!.Product!.Code, seq, m.Id, null, m.Code, m.Description, m.StockUnit, perUnit, total));
                    totals[m.Id] = totals.TryGetValue(m.Id, out var t) ? (m, t.Qty + total) : (m, total);
                }
                else if (item.ComponentProduct is { } c)
                {
                    if (!path.Add(c.Id)) throw new BomCycleException($"Cycle detected: product {c.Code} contains itself");
                    lines.Add(new BomNode(level, pid, item.RoutingOperation!.Product!.Code, seq, null, c.Id, c.Code, c.Name, c.StockUnit, perUnit, total));
                    Walk(c.Id, total, level + 1, path);
                    path.Remove(c.Id);
                }
            }
        }

        Walk(productId, quantity, 1, new HashSet<int> { productId });

        var materials = totals.Values
            .Select(t => new MaterialRequirement(t.Material.Id, t.Material.Code, t.Material.Description, t.Material.StockUnit, t.Qty))
            .OrderBy(m => m.Code)
            .ToList();
        return new BomExplosion(root.Id, root.Code, quantity, lines, materials);
    }

    public async Task<bool> WouldCreateCycleAsync(int parentProductId, int componentProductId, CancellationToken ct = default)
    {
        if (parentProductId == componentProductId) return true;
        var visited = new HashSet<int>();
        var frontier = new List<int> { componentProductId };
        while (frontier.Count > 0)
        {
            var children = await db.BomItems.AsNoTracking()
                .Where(i => frontier.Contains(i.RoutingOperation!.ProductId) && i.ComponentProductId != null)
                .Select(i => i.ComponentProductId!.Value)
                .Distinct()
                .ToListAsync(ct);
            if (children.Contains(parentProductId)) return true;
            frontier = children.Where(visited.Add).ToList();
        }
        return false;
    }

    public async Task<IReadOnlyList<WhereUsedEntry>> WhereUsedAsync(int? materialId, int? componentProductId, CancellationToken ct = default)
    {
        return await db.BomItems.AsNoTracking()
            .Where(i => (materialId != null && i.MaterialId == materialId) || (componentProductId != null && i.ComponentProductId == componentProductId))
            .OrderBy(i => i.RoutingOperation!.Product!.Code).ThenBy(i => i.RoutingOperation!.Sequence)
            .Select(i => new WhereUsedEntry(i.RoutingOperation!.ProductId, i.RoutingOperation.Product!.Code, i.RoutingOperation.Product.Name, i.RoutingOperation.Sequence, i.Quantity, i.Unit))
            .ToListAsync(ct);
    }

    private async Task<Dictionary<int, List<(int Seq, BomItem Item)>>> LoadStructureAsync(int rootId, CancellationToken ct)
    {
        var result = new Dictionary<int, List<(int, BomItem)>>();
        var frontier = new List<int> { rootId };
        var depth = 0;
        while (frontier.Count > 0)
        {
            if (++depth > MaxDepth + 1) throw new BomCycleException($"BOM deeper than {MaxDepth} levels");
            var items = await db.BomItems.AsNoTracking()
                .Include(i => i.RoutingOperation).ThenInclude(o => o!.Product)
                .Include(i => i.Material)
                .Include(i => i.ComponentProduct)
                .Where(i => frontier.Contains(i.RoutingOperation!.ProductId))
                .OrderBy(i => i.RoutingOperation!.Sequence).ThenBy(i => i.Id)
                .ToListAsync(ct);
            foreach (var item in items)
            {
                var pid = item.RoutingOperation!.ProductId;
                if (!result.TryGetValue(pid, out var list)) result[pid] = list = new();
                list.Add((item.RoutingOperation.Sequence, item));
            }
            frontier = items.Where(i => i.ComponentProductId != null)
                .Select(i => i.ComponentProductId!.Value)
                .Distinct()
                .Where(id => !result.ContainsKey(id))
                .ToList();
        }
        return result;
    }
}
