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
        if (!suggestProcess) return;
        var product = await db.Products.AsNoTracking().FirstOrDefaultAsync(p => p.Id == order.ProductId, ct);
        if (product is null) return;
        var machines = await MachineIndex.LoadAsync(db, ct);
        if (order.Operations.Count == 0 && order.ParentOrderId is null && order.Kind == ProductionOrderKind.Standard)
        {
            var (name, trade) = await CustomerOfAsync(order.CustomerId, null, ct);
            var suggestion = await Suggester.SuggestAsync(product, order.PrimaryTube, name, ct, null, trade, machines);
            order.Operations.AddRange(suggestion.Operations.Select(ToOperation));
        }
        else
        {
            // The routing came with its own data: only the empty requirement and machine are filled, by the rule of the operation type.
            foreach (var op in order.Operations) FillGaps(op, product.LengthMm, machines);
        }
    }

    private ProcessSuggester? suggesterInstance;
    private ProcessSuggester Suggester => suggesterInstance ??= suggester ?? new ProcessSuggester(db);

    private static ProductionOrderOperation ToOperation(SuggestedOperation s) =>
        new() { Sequence = s.Sequence, Description = s.Description, Tolerance = s.Tolerance, MeasureStart = s.MeasureStart, MeasureEnd = s.MeasureEnd, MachineId = s.MachineId };

    /// <summary>Fills only the empty requirement and the missing machine of an operation from the rules of its type. Returns whether something changed.</summary>
    private static bool FillGaps(ProductionOrderOperation op, decimal? lengthMm, MachineIndex machines)
    {
        var kind = ProcessSuggester.KindOf(op.Description);
        var changed = false;
        if (string.IsNullOrWhiteSpace(op.Tolerance) && ProcessSuggester.RuleTolerance(kind, lengthMm) is { } t) { op.Tolerance = t; changed = true; }
        if (op.MachineId is null && !op.External && machines.For(kind) is { } m) { op.MachineId = m.Id; changed = true; }
        return changed;
    }

    /// <summary>Name and trade name of the customer of an order: the customer on the OF, else the one of the sales order that generated it.</summary>
    private async Task<(string? Name, string? Trade)> CustomerOfAsync(int? customerId, int? orderId, CancellationToken ct)
    {
        if (customerId is { } c && await db.Customers.AsNoTracking().Where(x => x.Id == c).Select(x => new { x.Name, x.TradeName }).FirstOrDefaultAsync(ct) is { } cu) return (cu.Name, cu.TradeName);
        if (orderId is { } o && await db.SalesOrderLines.AsNoTracking().Where(l => l.ProductionOrderId == o).Select(l => new { l.Order!.Customer!.Name, l.Order.Customer.TradeName }).FirstOrDefaultAsync(ct) is { } s) return (s.Name, s.TradeName);
        return (null, null);
    }

    /// <summary>The process the system would write on this order now (nothing is saved): the last OF of the same customer and product, the legacy process of the customer and tube, the usual process of the tube, or the rules.</summary>
    public async Task<ProcessSuggestion> SuggestForOrderAsync(int id, CancellationToken ct = default)
    {
        var order = await db.ProductionOrders.AsNoTracking().Include(o => o.Product).FirstOrDefaultAsync(o => o.Id == id, ct) ?? throw ProductionException.NotFound("Order");
        if (order.Status != ProductionOrderStatus.Created) throw ProductionException.Conflict("The process can only be suggested before the order is released");
        var (name, trade) = await CustomerOfAsync(order.CustomerId, order.Id, ct);
        return await Suggester.SuggestAsync(order.Product!, order.PrimaryTube, name, ct, order.Id, trade);
    }

    /// <summary>Rewrites the process written on the OF (description, requirements, measures, machine) in the order given. Rows that come with their sequence keep their data; the sequences are renumbered 10, 20, 30... by position. A line without a machine keeps the one the operation has.</summary>
    public async Task<ProductionOrder> ReplaceProcessAsync(int id, IReadOnlyList<ProcessLine> lines, CancellationToken ct = default)
    {
        if (lines.Count == 0) throw ProductionException.Invalid("operations", "Give at least one operation");
        if (lines.Any(l => string.IsNullOrWhiteSpace(l.Description))) throw ProductionException.Invalid("operations", "Every operation needs a description");
        var machineIds = lines.Where(l => l.MachineId is not null).Select(l => l.MachineId!.Value).Distinct().ToList();
        if (machineIds.Count > 0 && await db.Machines.CountAsync(m => machineIds.Contains(m.Id), ct) != machineIds.Count) throw ProductionException.Invalid("machineId", "Machine not found");
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
                if (l.MachineId is { } machineId) op.MachineId = machineId;
            }
            foreach (var m in order.Materials.Where(m => oldToNew.ContainsKey(m.OperationSequence))) m.OperationSequence = oldToNew[m.OperationSequence];
            await db.SaveChangesAsync(ct);
            return order;
        }, ct);
    }

    /// <summary>
    /// Writes the suggested process on every OF that is still only created and has none, so the paper is never printed empty.
    /// With <paramref name="apply"/> false it only counts. Each process comes from <see cref="ProcessSuggester"/> (last OF of the customer, legacy template, rules).
    /// </summary>
    public async Task<BulkResult> BulkSuggestProcessAsync(bool apply, CancellationToken ct = default)
    {
        var orders = await db.ProductionOrders.Include(o => o.Product)
            .Where(o => o.Status == ProductionOrderStatus.Created && o.Kind == ProductionOrderKind.Standard && o.ParentOrderId == null && !o.Operations.Any())
            .OrderBy(o => o.DueDate).ToListAsync(ct);
        if (apply)
        {
            var machines = await MachineIndex.LoadAsync(db, ct);
            foreach (var o in orders.Where(o => o.Product != null))
            {
                var (name, trade) = await CustomerOfAsync(o.CustomerId, o.Id, ct);
                var suggestion = await Suggester.SuggestAsync(o.Product!, o.PrimaryTube, name, ct, o.Id, trade, machines);
                o.Operations.AddRange(suggestion.Operations.Select(ToOperation));
            }
            await db.SaveChangesAsync(ct);
        }
        return new BulkResult(orders.Count, apply ? orders.Count : 0, 0, orders.Take(20).Select(o => o.Reference).ToList());
    }

    /// <summary>
    /// Completes the process of OFs that are still only created, have no shop-floor reports and miss a requirement or a machine on some operation, and fixes the legacy swap
    /// (the text "Visual/Dimensional" written as the inspection requirement instead of "-"). Only empty fields are filled, from the suggestion for the order's customer and product
    /// (the operation of the same type; the rules of the type when the suggestion has none); descriptions, sequences and anything already written stay. Preview (<paramref name="apply"/> false) counts without writing.
    /// </summary>
    public async Task<BulkRequirementsResult> BulkCompleteRequirementsAsync(bool apply, CancellationToken ct = default)
    {
        var query = db.ProductionOrders.Include(o => o.Product).Include(o => o.Operations)
            .Where(o => o.Status == ProductionOrderStatus.Created && o.Kind == ProductionOrderKind.Standard && o.ParentOrderId == null
                && !db.ProductionReports.Any(r => r.OrderId == o.Id)
                && o.Operations.Any(op => op.Tolerance == null || op.Tolerance.Trim() == "" || op.Tolerance == ProcessSuggester.LegacyInspectionResource || (op.MachineId == null && !op.External)));
        if (!apply) query = query.AsNoTracking();
        var orders = await query.OrderBy(o => o.DueDate).ThenBy(o => o.Id).ToListAsync(ct);
        var machines = await MachineIndex.LoadAsync(db, ct);
        int changed = 0, filled = 0;
        var sample = new List<string>();
        foreach (var o in orders)
        {
            var (name, trade) = await CustomerOfAsync(o.CustomerId, o.Id, ct);
            var suggestion = await Suggester.SuggestAsync(o.Product!, o.PrimaryTube, name, ct, o.Id, trade, machines);
            var byKind = suggestion.Operations.GroupBy(s => ProcessSuggester.KindOf(s.Description)).ToDictionary(g => g.Key, g => g.ToList());
            var seen = new Dictionary<OperationKind, int>();
            var n = 0;
            foreach (var op in o.Operations.OrderBy(x => x.Sequence))
            {
                var kind = ProcessSuggester.KindOf(op.Description);
                var ordinal = seen.GetValueOrDefault(kind);
                seen[kind] = ordinal + 1;
                SuggestedOperation? s = kind != OperationKind.Other && byKind.TryGetValue(kind, out var same) ? same[Math.Min(ordinal, same.Count - 1)] : null;
                var touched = false;
                if (ProcessSuggester.IsLegacySwap(op.Tolerance))
                {
                    op.Tolerance = ProcessSuggester.Dash;
                    if (op.MachineId is null && machines.For(OperationKind.Inspection) is { } insp) op.MachineId = insp.Id;
                    touched = true;
                }
                else if (string.IsNullOrWhiteSpace(op.Tolerance))
                {
                    var tolerance = s is not null ? s.Tolerance : ProcessSuggester.RuleTolerance(kind, o.Product!.LengthMm);
                    if (!string.IsNullOrWhiteSpace(tolerance)) { op.Tolerance = tolerance; touched = true; }
                }
                if (op.MachineId is null && !op.External)
                {
                    var machineId = s?.MachineId ?? machines.For(kind)?.Id;
                    if (machineId is not null) { op.MachineId = machineId; touched = true; }
                }
                if (touched) n++;
            }
            if (n == 0) continue;
            changed++;
            filled += n;
            if (sample.Count < 20) sample.Add(o.Reference);
        }
        if (apply && changed > 0) await db.SaveChangesAsync(ct);
        return new BulkRequirementsResult(orders.Count, apply ? changed : 0, orders.Count - changed, sample, filled);
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
