using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Production;

public sealed partial class ProductionService
{
    private static readonly ProductionOrderStatus[] Reportable = [ProductionOrderStatus.Released, ProductionOrderStatus.InProduction];

    public async Task<ProductionOrderOperation> UpdateOperationDetailsAsync(int orderId, int sequence, OperationDetailsInput i, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var order = await LockAsync(orderId, ct);
            if (!Open.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
            var op = Operation(order, sequence);
            op.Tolerance = Clean(i.Tolerance);
            op.MeasureStart = Clean(i.MeasureStart);
            op.MeasureEnd = Clean(i.MeasureEnd);
            await db.SaveChangesAsync(ct);
            return op;
        }, ct);
    }

    public async Task<ProductionOrderOperation> OutsourceAsync(int orderId, int sequence, OutsourceInput? i, CancellationToken ct = default)
    {
        if (i is { LeadDays: < 0 }) throw ProductionException.Invalid("leadDays", "Must not be negative");
        return await InTransaction(async () =>
        {
            var order = await LockAsync(orderId, ct);
            if (!Open.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
            var op = Operation(order, sequence);
            var used = await db.ProductionReports.AnyAsync(r => r.OperationId == op.Id, ct) || await db.OutsideShipments.AnyAsync(s => s.OperationId == op.Id, ct);
            if (used) throw ProductionException.Conflict($"Operation {sequence} already has production recorded");
            if (i is null)
            {
                op.External = false;
                op.SupplierId = null;
                op.ExternalLeadDays = null;
            }
            else
            {
                if (!await db.Suppliers.AnyAsync(s => s.Id == i.SupplierId && s.Active, ct)) throw ProductionException.Invalid("supplierId", "Unknown or inactive supplier");
                op.External = true;
                op.SupplierId = i.SupplierId;
                op.ExternalLeadDays = i.LeadDays;
            }
            await db.SaveChangesAsync(ct);
            return op;
        }, ct);
    }

    public async Task<OutsideShipment> SendOutsideAsync(int orderId, int sequence, OutsideSendInput i, string? user, CancellationToken ct = default)
    {
        if (i.Quantity <= 0) throw ProductionException.Invalid("quantity", "Must be greater than zero");
        return await InTransaction(async () =>
        {
            var order = await LockAsync(orderId, ct);
            if (!Reportable.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
            var op = Operation(order, sequence);
            if (!op.External) throw ProductionException.Conflict($"Operation {sequence} is not an outside-processing operation");
            var progress = (await ProgressAsync(order, ct)).Operations.First(o => o.OperationId == op.Id);
            if (i.Quantity > progress.Remaining) throw ProductionException.Conflict($"Only {progress.Remaining:0.####} available to send for operation {sequence}");
            var shipment = new OutsideShipment
            {
                OperationId = op.Id, SupplierId = op.SupplierId!.Value, SentOn = i.Date, Quantity = i.Quantity, InvoiceNumber = Clean(i.InvoiceNumber), Notes = Clean(i.Notes), CreatedBy = user
            };
            db.OutsideShipments.Add(shipment);
            if (order.Status == ProductionOrderStatus.Released) order.Status = ProductionOrderStatus.InProduction;
            await db.SaveChangesAsync(ct);
            // Remessa para industrialização (5901): the NF is authorized by SEFAZ before the shipment is kept; a rejection rolls the whole send back.
            if (fiscal is not null && shipment.InvoiceNumber is null && await fiscal.EnabledAsync(ct))
            {
                var nf = await fiscal.IssueOutsideShipmentAsync(shipment, order, op, new OutsideInvoiceOptions(i.UnitValue ?? 0m, i.Cfop), user, ct);
                shipment.InvoiceNumber = nf.Number.ToString();
                await db.SaveChangesAsync(ct);
            }
            return shipment;
        }, ct);
    }

    public async Task<ProductionReport> ReturnOutsideAsync(int shipmentId, OutsideReturnInput i, string? user, CancellationToken ct = default)
    {
        if (i.GoodQuantity < 0) throw ProductionException.Invalid("goodQuantity", "Must not be negative");
        if (i.ScrapQuantity < 0) throw ProductionException.Invalid("scrapQuantity", "Must not be negative");
        if (i.GoodQuantity + i.ScrapQuantity <= 0) throw ProductionException.Invalid("goodQuantity", "Nothing returned");
        if (i.ServiceUnitPrice < 0) throw ProductionException.Invalid("serviceUnitPrice", "Must not be negative");
        var orderId = await db.OutsideShipments.Where(s => s.Id == shipmentId).Select(s => (int?)s.Operation!.OrderId).FirstOrDefaultAsync(ct) ?? throw ProductionException.NotFound("Shipment");
        return await InTransaction(async () =>
        {
            var order = await LockAsync(orderId, ct);
            if (!Reportable.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
            var shipment = await db.OutsideShipments.FirstAsync(s => s.Id == shipmentId, ct);
            var open = shipment.Quantity - shipment.ReturnedQuantity - shipment.ScrapQuantity;
            if (i.GoodQuantity + i.ScrapQuantity > open) throw ProductionException.Conflict($"Only {open:0.####} still at the supplier for this shipment");
            await CheckOccurrenceAsync(i.ScrapOccurrenceId, OccurrenceKind.Scrap, "scrapOccurrenceId", ct);
            shipment.ReturnedQuantity += i.GoodQuantity;
            shipment.ScrapQuantity += i.ScrapQuantity;
            shipment.ServiceValue += Math.Round(i.GoodQuantity * i.ServiceUnitPrice, 4);
            var report = new ProductionReport
            {
                OrderId = order.Id, OperationId = shipment.OperationId, Date = i.Date, GoodQuantity = i.GoodQuantity, ScrapQuantity = i.ScrapQuantity, ScrapOccurrenceId = i.ScrapOccurrenceId,
                OutsideShipment = shipment, Notes = Clean(string.Join(" ", new[] { i.InvoiceNumber is { } nf ? $"NF retorno {nf.Trim()}" : null, i.Notes }.Where(x => x is not null))),
                ReportedBy = user, ReportedAt = DateTimeOffset.UtcNow
            };
            db.ProductionReports.Add(report);
            await db.SaveChangesAsync(ct);
            return report;
        }, ct);
    }

    public async Task<OverrunRelease> ReleaseOverrunAsync(int orderId, int sequence, decimal quantity, string? justification, string? user, CancellationToken ct = default)
    {
        if (quantity <= 0) throw ProductionException.Invalid("quantity", "Must be greater than zero");
        if (Clean(justification) is null) throw ProductionException.Invalid("justification", "Required");
        return await InTransaction(async () =>
        {
            var order = await LockAsync(orderId, ct);
            if (!Open.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
            var op = Operation(order, sequence);
            var release = new OverrunRelease { OperationId = op.Id, Quantity = quantity, Justification = Clean(justification)!, ReleasedBy = user, ReleasedAt = DateTimeOffset.UtcNow };
            op.OverrunReleased += quantity;
            db.OverrunReleases.Add(release);
            await db.SaveChangesAsync(ct);
            return release;
        }, ct);
    }

    public async Task<ProductionReport> ReportAsync(ReportInput i, string? user, CancellationToken ct = default)
    {
        if (i.GoodQuantity < 0) throw ProductionException.Invalid("goodQuantity", "Must not be negative");
        if (i.ScrapQuantity < 0) throw ProductionException.Invalid("scrapQuantity", "Must not be negative");
        if (i.GoodQuantity + i.ScrapQuantity <= 0 && i.DowntimeHours is not > 0) throw ProductionException.Invalid("goodQuantity", "Report a quantity or downtime");
        if (i.ScrapQuantity > 0 && i.ScrapOccurrenceId is null) throw ProductionException.Invalid("scrapOccurrenceId", "Give the scrap reason");
        if (i.DowntimeHours > 0 && i.DowntimeOccurrenceId is null) throw ProductionException.Invalid("downtimeOccurrenceId", "Give the downtime reason");
        foreach (var (v, f) in new[] { (i.Hours, "hours"), (i.SetupHours, "setupHours"), (i.Operators, "operators"), (i.DowntimeHours, "downtimeHours"), (i.WeightKg, "weightKg") })
            if (v < 0) throw ProductionException.Invalid(f, "Must not be negative");
        var hours = i.Hours;
        if (i.StartTime is { } s && i.EndTime is { } e)
        {
            var span = e - s;
            hours ??= Math.Round((decimal)span.TotalHours, 4);
        }

        return await InTransaction(async () =>
        {
            var order = await LockAsync(i.OrderId, ct);
            if (order.Status == ProductionOrderStatus.Created) throw ProductionException.Conflict("Release the order before reporting production");
            if (!Reportable.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
            var op = Operation(order, i.OperationSequence);
            if (op.External && i.GoodQuantity + i.ScrapQuantity > 0) throw ProductionException.Conflict($"Operation {op.Sequence} is done by a third party; record it as an outside-processing return");
            await CheckOccurrenceAsync(i.ScrapOccurrenceId, OccurrenceKind.Scrap, "scrapOccurrenceId", ct);
            var downtime = await CheckOccurrenceAsync(i.DowntimeOccurrenceId, OccurrenceKind.Downtime, "downtimeOccurrenceId", ct);
            if (i.ShiftId is { } sid && !await db.Shifts.AnyAsync(x => x.Id == sid, ct)) throw ProductionException.Invalid("shiftId", "Shift not found");
            if (i.EmployeeId is { } eid && !await db.Employees.AnyAsync(x => x.Id == eid && x.Active, ct)) throw ProductionException.Invalid("employeeId", "Unknown or inactive employee");
            if (i.MachineId is { } mid && !await db.Machines.AnyAsync(x => x.Id == mid, ct)) throw ProductionException.Invalid("machineId", "Machine not found");

            var progress = (await ProgressAsync(order, ct)).Operations.First(o => o.OperationId == op.Id);
            var qty = i.GoodQuantity + i.ScrapQuantity;
            if (qty > progress.Remaining)
                throw ProductionException.Conflict(progress.Remaining < 0 || op.Sequence != order.Operations.Min(o => o.Sequence)
                    ? $"Operation {op.Sequence} can take at most {Math.Max(0, progress.Remaining):0.####} more (limited by the previous operation and released overruns)"
                    : $"Reporting {qty:0.####} exceeds the order plus tolerance by {qty - progress.Remaining:0.####}; an overrun release is needed");

            var report = new ProductionReport
            {
                OrderId = order.Id, OperationId = op.Id, Date = i.Date, ShiftId = i.ShiftId, EmployeeId = i.EmployeeId, MachineId = i.MachineId ?? op.MachineId,
                StartTime = i.StartTime, EndTime = i.EndTime, Hours = hours, SetupHours = i.SetupHours, Operators = i.Operators, DowntimeHours = i.DowntimeHours,
                DowntimeOccurrenceId = i.DowntimeOccurrenceId, GoodQuantity = i.GoodQuantity, ScrapQuantity = i.ScrapQuantity, ScrapOccurrenceId = i.ScrapOccurrenceId,
                WeightKg = i.WeightKg, Notes = Clean(i.Notes), ReportedBy = user, ReportedAt = DateTimeOffset.UtcNow
            };
            db.ProductionReports.Add(report);
            if (order.Status == ProductionOrderStatus.Released) order.Status = ProductionOrderStatus.InProduction;
            if (downtime is { StopsOrder: true })
            {
                order.Status = ProductionOrderStatus.Stopped;
                order.StatusReason = downtime.Description;
            }
            await db.SaveChangesAsync(ct);
            return report;
        }, ct);
    }

    public async Task DeleteReportAsync(int reportId, CancellationToken ct = default)
    {
        var orderId = await db.ProductionReports.Where(r => r.Id == reportId).Select(r => (int?)r.OrderId).FirstOrDefaultAsync(ct) ?? throw ProductionException.NotFound("Report");
        await InTransaction(async () =>
        {
            var order = await LockAsync(orderId, ct);
            if (!Open.Contains(order.Status)) throw ProductionException.Conflict($"Order is {order.Status}");
            var report = await db.ProductionReports.Include(r => r.OutsideShipment).FirstAsync(r => r.Id == reportId, ct);
            if (report.OutsideShipment is { } shipment)
            {
                shipment.ReturnedQuantity -= report.GoodQuantity;
                shipment.ScrapQuantity -= report.ScrapQuantity;
                shipment.ServiceValue = shipment.ReturnedQuantity == 0 ? 0 : shipment.ServiceValue * shipment.ReturnedQuantity / (shipment.ReturnedQuantity + report.GoodQuantity);
            }
            db.ProductionReports.Remove(report);
            await db.SaveChangesAsync(ct);
            var progress = await ProgressAsync(order, ct);
            if (progress.Operations.FirstOrDefault(o => o.Remaining < 0) is { } bad)
                throw ProductionException.Conflict($"Operation {bad.Sequence} already used this quantity; delete its reports first");
            var lastGood = progress.Operations.Count > 0 ? progress.Operations[^1].Good : decimal.MaxValue;
            if (progress.Received > lastGood) throw ProductionException.Conflict("This quantity is already received into stock");
            return 0;
        }, ct);
    }

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

    public async Task<IReadOnlyList<LoadRow>> LoadAsync(DateOnly from, DateOnly to, bool byWorkCenter, CancellationToken ct = default)
    {
        if (to < from) throw ProductionException.Invalid("to", "Must not be before from");
        var settings = await SettingsAsync(ct);
        var holidays = (await db.Holidays.AsNoTracking().Where(h => h.Date >= from && h.Date <= to.AddDays(7)).Select(h => h.Date).ToListAsync(ct)).ToHashSet();
        var calendar = new WorkCalendar(settings.HoursPerDay, settings.WorkSaturdays, holidays);
        var rows = await db.ProductionOrderOperations.AsNoTracking()
            .Where(o => Open.Contains(o.Order!.Status) && !o.External && o.PlannedHours > 0 && o.PlannedStart != null && o.PlannedStart >= from && o.PlannedStart <= to)
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

    private async Task<ProductionOccurrence?> CheckOccurrenceAsync(int? id, OccurrenceKind kind, string field, CancellationToken ct)
    {
        if (id is null) return null;
        var o = await db.ProductionOccurrences.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw ProductionException.Invalid(field, "Occurrence not found");
        if (o.Kind != kind) throw ProductionException.Invalid(field, $"Occurrence {o.Code} is not a {kind.ToString().ToLower()} reason");
        return o;
    }

    private static ProductionOrderOperation Operation(ProductionOrder order, int sequence) =>
        order.Operations.FirstOrDefault(o => o.Sequence == sequence) ?? throw ProductionException.Invalid("operationSequence", $"Order {order.Reference} has no operation {sequence}");
}

public sealed class WorkCalendar(decimal hoursPerDay, bool workSaturdays, IReadOnlySet<DateOnly> holidays)
{
    public decimal HoursPerDay { get; } = hoursPerDay;

    public bool IsWorkingDay(DateOnly d) => d.DayOfWeek != DayOfWeek.Sunday && (workSaturdays || d.DayOfWeek != DayOfWeek.Saturday) && !holidays.Contains(d);

    public DateOnly OnOrBefore(DateOnly d)
    {
        for (var i = 0; i < 400 && !IsWorkingDay(d); i++) d = d.AddDays(-1);
        return d;
    }

    public DateOnly OnOrAfter(DateOnly d)
    {
        for (var i = 0; i < 400 && !IsWorkingDay(d); i++) d = d.AddDays(1);
        return d;
    }

    public DateOnly Previous(DateOnly d) => OnOrBefore(d.AddDays(-1));
    public DateOnly Next(DateOnly d) => OnOrAfter(d.AddDays(1));

    public static DateOnly WeekStart(DateOnly d) => d.AddDays(-(((int)d.DayOfWeek + 6) % 7));
}
