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

/// <summary>Finite scheduling of production orders by working days and capacity, and the work-center load report.</summary>
public sealed partial class ProductionService
{
    public async Task<IReadOnlyList<ScheduleResult>> ScheduleAsync(int? orderId, DateOnly today, CancellationToken ct = default)
    {
        var settings = await SettingsAsync(ct);
        var holidays = (await db.Holidays.AsNoTracking().Where(h => h.Date >= today.AddYears(-2)).Select(h => h.Date).ToListAsync(ct)).ToHashSet();
        var calendar = new WorkCalendar(settings.HoursPerDay, settings.WorkSaturdays, holidays);
        var query = db.ProductionOrders.Include(o => o.Operations).Include(o => o.Materials).Where(o => Open.Contains(o.Status));
        var orders = orderId is { } id
            ? await query.Where(o => o.Id == id).ToListAsync(ct)
            : await query.Where(o => o.ParentOrderId == null || !Open.Contains(o.ParentOrder!.Status)).OrderBy(o => o.DueDate).ToListAsync(ct);
        if (orderId is not null && orders.Count == 0) throw ProductionException.Conflict("Order not found or not open");
        var results = new List<ScheduleResult>();
        foreach (var order in orders) await ScheduleTreeAsync(order, order.DueDate, calendar, today, results, 0, ct);
        await db.SaveChangesAsync(ct);
        return results;
    }

    private async Task ScheduleTreeAsync(ProductionOrder order, DateOnly due, WorkCalendar calendar, DateOnly today, List<ScheduleResult> results, int depth, CancellationToken ct)
    {
        if (depth > Services.BomService.MaxDepth || results.Any(r => r.OrderId == order.Id)) return;
        var progress = await ProgressAsync(order, ct);
        var warnings = new List<string>();
        if (order.Operations.Count == 0) warnings.Add("Sem operação");
        if (order.Materials.Count == 0) warnings.Add("Produto sem materiais");

        var ops = order.Operations.OrderBy(o => o.Sequence).ToList();
        foreach (var op in ops)
        {
            var p = progress.Operations.First(x => x.OperationId == op.Id);
            var left = Math.Max(0, order.Quantity - p.Good - p.Scrap - p.InTransit);
            if (op.External)
                op.PlannedHours = left > 0 || p.InTransit > 0 ? (op.ExternalLeadDays ?? 0) * calendar.HoursPerDay : 0;
            else
            {
                if (op.MachineId is null) warnings.Add($"Operação {op.Sequence} sem máquina");
                if (op.PiecesPerHour is not > 0) warnings.Add($"Operação {op.Sequence} sem peças/hora");
                var setup = p.Good + p.Scrap == 0 ? op.SetupHours ?? 0 : 0;
                op.PlannedHours = left > 0 ? Math.Round(setup + (op.PiecesPerHour is > 0 and var pph ? left / pph : 0), 4) : 0;
            }
        }

        var cursor = calendar.OnOrBefore(due);
        var capacity = calendar.HoursPerDay;
        foreach (var op in ops.AsEnumerable().Reverse())
        {
            if (capacity <= 0) { cursor = calendar.Previous(cursor); capacity = calendar.HoursPerDay; }
            op.PlannedEnd = cursor;
            var need = op.PlannedHours;
            while (need > capacity) { need -= capacity; cursor = calendar.Previous(cursor); capacity = calendar.HoursPerDay; }
            capacity -= need;
            op.PlannedStart = cursor;
        }
        order.PlannedStart = ops.Count > 0 ? ops[0].PlannedStart : calendar.OnOrBefore(due);
        order.PlannedEnd = ops.Count > 0 ? ops[^1].PlannedEnd : order.PlannedStart;

        var start = calendar.OnOrAfter(today);
        var late = order.PlannedStart < start;
        if (late)
        {
            var fwd = start;
            var cap = calendar.HoursPerDay;
            foreach (var op in ops)
            {
                if (cap <= 0) { fwd = calendar.Next(fwd); cap = calendar.HoursPerDay; }
                var need = op.PlannedHours;
                while (need > cap) { need -= cap; fwd = calendar.Next(fwd); cap = calendar.HoursPerDay; }
                cap -= need;
            }
            order.AdjustedStart = start;
            order.AdjustedEnd = fwd;
        }
        else
        {
            order.AdjustedStart = null;
            order.AdjustedEnd = null;
        }
        results.Add(new ScheduleResult(order.Id, order.Reference, order.DueDate, order.PlannedStart, order.PlannedEnd, order.AdjustedStart, order.AdjustedEnd, late,
            ops.Select(o => new ScheduledOperation(o.Sequence, o.PlannedStart, o.PlannedEnd, o.PlannedHours)).ToList(), warnings.Distinct().ToList()));

        var children = await db.ProductionOrders.Include(o => o.Operations).Include(o => o.Materials)
            .Where(o => o.ParentOrderId == order.Id && Open.Contains(o.Status)).ToListAsync(ct);
        foreach (var child in children)
        {
            var seq = order.Materials.Where(m => m.ComponentProductId == child.ProductId).Select(m => (int?)m.OperationSequence).Min();
            var needed = (seq is { } s ? ops.FirstOrDefault(o => o.Sequence == s)?.PlannedStart : null) ?? order.PlannedStart ?? due;
            var childDue = calendar.Previous(needed);
            await ScheduleTreeAsync(child, childDue < child.DueDate ? childDue : child.DueDate, calendar, today, results, depth + 1, ct);
        }
    }

    public async Task<IReadOnlyList<LoadRow>> LoadAsync(DateOnly from, DateOnly to, bool byWorkCenter, CancellationToken ct = default, bool includeTest = false)
    {
        if (to < from) throw ProductionException.Invalid("to", "Must not be before from");
        var settings = await SettingsAsync(ct);
        var holidays = (await db.Holidays.AsNoTracking().Where(h => h.Date >= from && h.Date <= to.AddDays(7)).Select(h => h.Date).ToListAsync(ct)).ToHashSet();
        var calendar = new WorkCalendar(settings.HoursPerDay, settings.WorkSaturdays, holidays);
        var rows = await db.ProductionOrderOperations.AsNoTracking()
            .Where(o => (includeTest || o.Order!.Source != DataSource.Test) && Open.Contains(o.Order!.Status) && !o.External && o.PlannedHours > 0 && o.PlannedStart != null && o.PlannedStart >= from && o.PlannedStart <= to)
            .Where(o => byWorkCenter ? (o.WorkCenterId != null || o.Machine!.WorkCenterId != null) : o.MachineId != null)
            .Select(o => new
            {
                Id = byWorkCenter ? o.WorkCenterId ?? o.Machine!.WorkCenterId!.Value : o.MachineId!.Value,
                Code = byWorkCenter ? (o.WorkCenter != null ? o.WorkCenter.Code : o.Machine!.WorkCenter!.Code) : o.Machine!.Code,
                Start = o.PlannedStart!.Value,
                o.PlannedHours
            }).ToListAsync(ct);
        return rows.GroupBy(r => (r.Id, r.Code, Week: WorkCalendar.WeekStart(r.Start)))
            .Select(g =>
            {
                var capacity = Enumerable.Range(0, 7).Select(d => g.Key.Week.AddDays(d)).Count(calendar.IsWorkingDay) * calendar.HoursPerDay;
                var hours = g.Sum(r => r.PlannedHours);
                return new LoadRow(g.Key.Id, g.Key.Code, g.Key.Week, hours, capacity, capacity > 0 ? Math.Round(hours / capacity * 100, 1) : 0, g.Count());
            })
            .OrderBy(r => r.Code).ThenBy(r => r.WeekStart).ToList();
    }
}
