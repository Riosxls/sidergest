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

/// <summary>Production order process: structure snapshot from the routing, suggested process for products without routing, rewriting the process on the OF, and the admin bulk tools for legacy orders.</summary>
public sealed partial class ProductionService
{
    public async Task SnapshotStructureAsync(ProductionOrder order, CancellationToken ct, bool suggestProcess = false)
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
                SetupHours = op.SetupHours, PiecesPerHour = op.PiecesPerHour, Operators = op.Operators, Tolerance = op.Standard
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
        if (suggestProcess && order.Operations.Count == 0 && order.ParentOrderId is null && order.Kind == ProductionOrderKind.Standard)
        {
            var product = await db.Products.AsNoTracking().FirstOrDefaultAsync(p => p.Id == order.ProductId, ct);
            if (product != null) order.Operations.AddRange(SuggestProcess(product, order.PrimaryTube));
        }
    }

    /// <summary>
    /// Draft process for a product that has no routing, so the OF paper never goes to the shop floor with an empty process:
    /// profile, draw to the final diameter, straighten and cut, final inspection. The planner confirms it on the order.
    /// </summary>
    public static List<ProductionOrderOperation> SuggestProcess(Product product, string? primaryTube)
    {
        string Mm(decimal v, string format = "0.00") => v.ToString(format, System.Globalization.CultureInfo.GetCultureInfo("pt-BR"));
        var ops = new List<string>();
        decimal? profile = null;
        var m = System.Text.RegularExpressions.Regex.Match(primaryTube ?? "", @"\d+(?:[.,]\d+)?");
        if (m.Success && decimal.TryParse(m.Value.Replace(',', '.'), System.Globalization.NumberStyles.Number, System.Globalization.CultureInfo.InvariantCulture, out var d)) profile = d;
        ops.Add(profile is { } p ? $"Perfilar {Mm(p)}mm" : "Perfilar");
        if (product.DiameterMm is { } dia and > 0 && (profile is null || dia < profile)) ops.Add($"Trefilar para {Mm(dia)}mm");
        ops.Add(product.LengthMm is { } len and > 0 ? $"Endireitar e Cortar {Mm(len, "0.##")}" : "Endireitar e Cortar");
        ops.Add("Inspeção Final");
        return ops.Select((text, i) => new ProductionOrderOperation
        {
            Sequence = (i + 1) * 10, Description = text, Tolerance = i == ops.Count - 1 ? "Visual/Dimensional" : null
        }).ToList();
    }

    /// <summary>Rewrites the process written on the OF (description, requirements, measures) in the order given. Rows that come with their sequence keep their data; the sequences are renumbered 10, 20, 30... by position.</summary>
    public async Task<ProductionOrder> ReplaceProcessAsync(int id, IReadOnlyList<ProcessLine> lines, CancellationToken ct = default)
    {
        if (lines.Count == 0) throw ProductionException.Invalid("operations", "Give at least one operation");
        if (lines.Any(l => string.IsNullOrWhiteSpace(l.Description))) throw ProductionException.Invalid("operations", "Every operation needs a description");
        return await InTransaction(async () =>
        {
            var order = await LockAsync(id, ct);
            if (order.Status != ProductionOrderStatus.Created) throw ProductionException.Conflict("The process can only be rewritten before the order is released");
            if (await db.ProductionReports.AnyAsync(r => r.OrderId == id, ct)) throw ProductionException.Conflict("Order has shop-floor reports");
            var kept = lines.Where(l => l.Sequence is not null).Select(l => l.Sequence!.Value).ToHashSet();
            foreach (var op in order.Operations.Where(o => !kept.Contains(o.Sequence)).ToList())
            {
                if (order.Materials.Any(m => m.OperationSequence == op.Sequence)) throw ProductionException.Conflict($"Operation {op.Sequence} has materials; keep it");
                order.Operations.Remove(op);
                db.ProductionOrderOperations.Remove(op);
            }
            foreach (var op in order.Operations) op.Sequence = -op.Sequence;
            await db.SaveChangesAsync(ct);
            var oldToNew = new Dictionary<int, int>();
            for (var i = 0; i < lines.Count; i++)
            {
                var l = lines[i];
                var op = l.Sequence is { } s ? order.Operations.FirstOrDefault(o => o.Sequence == -s) : null;
                if (op is null)
                {
                    op = new ProductionOrderOperation();
                    order.Operations.Add(op);
                }
                else oldToNew[-op.Sequence] = (i + 1) * 10;
                op.Sequence = (i + 1) * 10;
                op.Description = Clean(l.Description);
                op.Tolerance = Clean(l.Tolerance);
                op.MeasureStart = Clean(l.MeasureStart);
                op.MeasureEnd = Clean(l.MeasureEnd);
            }
            foreach (var m in order.Materials.Where(m => oldToNew.ContainsKey(m.OperationSequence))) m.OperationSequence = oldToNew[m.OperationSequence];
            await db.SaveChangesAsync(ct);
            return order;
        }, ct);
    }

    /// <summary>
    /// Writes the suggested process on every OF that is still only created and has none, so the paper is never printed empty.
    /// With <paramref name="apply"/> false it only counts.
    /// </summary>
    public async Task<BulkResult> BulkSuggestProcessAsync(bool apply, CancellationToken ct = default)
    {
        var orders = await db.ProductionOrders.Include(o => o.Product)
            .Where(o => o.Status == ProductionOrderStatus.Created && o.Kind == ProductionOrderKind.Standard && o.ParentOrderId == null && !o.Operations.Any())
            .OrderBy(o => o.DueDate).ToListAsync(ct);
        if (apply)
        {
            foreach (var o in orders.Where(o => o.Product != null))
                o.Operations.AddRange(SuggestProcess(o.Product!, o.PrimaryTube));
            await db.SaveChangesAsync(ct);
        }
        return new BulkResult(orders.Count, apply ? orders.Count : 0, 0, orders.Take(20).Select(o => o.Reference).ToList());
    }

    /// <summary>
    /// Cancels OFs that were created long ago, never released and with no stock movement or shop-floor report (typically imported legacy orders).
    /// Subassemblies go first so a parent is not blocked by its own child.
    /// </summary>
    public async Task<BulkResult> BulkCancelStaleAsync(int olderThanDays, string? reason, bool apply, CancellationToken ct = default)
    {
        if (olderThanDays < 30) throw ProductionException.Invalid("olderThanDays", "At least 30 days");
        if (apply && Clean(reason) is null) throw ProductionException.Invalid("reason", "Required");
        var limit = Ebt.Core.Services.Clock.Today().AddDays(-olderThanDays);
        var candidates = await db.ProductionOrders.AsNoTracking()
            .Where(o => o.Status == ProductionOrderStatus.Created && o.DueDate < limit)
            .OrderByDescending(o => o.ParentOrderId != null).ThenBy(o => o.DueDate).Select(o => new { o.Id, o.Reference }).ToListAsync(ct);
        var done = 0;
        var skipped = 0;
        var sample = new List<string>();
        foreach (var c in candidates)
        {
            if (apply)
            {
                try { await CancelAsync(c.Id, reason, false, ct); done++; }
                catch (ProductionException) { skipped++; continue; }
            }
            if (sample.Count < 20) sample.Add(c.Reference);
        }
        return new BulkResult(candidates.Count, done, skipped, sample);
    }
}
