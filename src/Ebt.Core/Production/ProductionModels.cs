using Ebt.Core.Entities;

namespace Ebt.Core.Production;

public sealed class ProductionException(int status, string message, string? field = null) : Exception(message)
{
    public int Status { get; } = status;
    public string? Field { get; } = field;

    public static ProductionException Invalid(string field, string message) => new(400, message, field);
    public static ProductionException Conflict(string message) => new(409, message);
    public static ProductionException NotFound(string what) => new(404, $"{what} not found");
}

public sealed record OrderInput(int ProductId, decimal Quantity, DateOnly DueDate, ProductionOrderKind Kind = ProductionOrderKind.Standard, int? CustomerId = null, int? ParentOrderId = null, int? PreviousOrderId = null, int? Bales = null, string? Notes = null);
public sealed record OrderUpdate(decimal Quantity, DateOnly DueDate, int? CustomerId, int? Bales, string? Notes);
public sealed record IssueLineInput(int MaterialLineId, decimal Quantity, int? LotId = null);
public sealed record IssueInput(DateOnly Date, int? LocationId = null, IReadOnlyList<IssueLineInput>? Lines = null);
public sealed record FinishedGoodsInput(DateOnly Date, decimal Quantity, int? LocationId = null, string? LotCode = null);
public sealed record OutsourceInput(int SupplierId, int? LeadDays);
public sealed record OutsideSendInput(DateOnly Date, decimal Quantity, string? InvoiceNumber, string? Notes);
public sealed record OutsideReturnInput(DateOnly Date, decimal GoodQuantity, decimal ScrapQuantity, decimal ServiceUnitPrice, int? ScrapOccurrenceId, string? InvoiceNumber, string? Notes);
public sealed record ReportInput(int OrderId, int OperationSequence, DateOnly Date, decimal GoodQuantity, decimal ScrapQuantity = 0, int? ScrapOccurrenceId = null, int? ShiftId = null, int? EmployeeId = null, int? MachineId = null,
    TimeOnly? StartTime = null, TimeOnly? EndTime = null, decimal? Hours = null, decimal? SetupHours = null, decimal? Operators = null, decimal? DowntimeHours = null, int? DowntimeOccurrenceId = null, decimal? WeightKg = null, string? Notes = null);

public sealed record OperationProgress(int OperationId, int Sequence, bool External, decimal Good, decimal Scrap, decimal InTransit, decimal OverrunReleased, decimal Limit, decimal Remaining);
public sealed record OrderProgress(IReadOnlyList<OperationProgress> Operations, decimal Good, decimal Scrap, decimal Received, decimal Receivable, decimal WorkInProcess);
public sealed record ItemConsumption(int? MaterialId, int? ProductId, decimal Quantity, decimal Value);
public sealed record MaterialLineState(int Id, int OperationSequence, int? MaterialId, int? ComponentProductId, string Code, string Description, string Unit, decimal QuantityPerUnit, decimal Required, decimal Issued, decimal Remaining, int? ReservationId, decimal Reserved);

public sealed record AvailabilityLine(int? MaterialLineId, int? MaterialId, int? ProductId, string Code, string Description, string Unit, decimal Required, decimal Issued, decimal Remaining, decimal ReservedForOrder, decimal Free, decimal OnOrder, decimal Shortage);
public sealed record AvailabilityResult(bool Complete, IReadOnlyList<AvailabilityLine> Lines);

public sealed record ScheduledOperation(int Sequence, DateOnly? Start, DateOnly? End, decimal Hours);
public sealed record ScheduleResult(int OrderId, string Reference, DateOnly DueDate, DateOnly? PlannedStart, DateOnly? PlannedEnd, DateOnly? AdjustedStart, DateOnly? AdjustedEnd, bool Late, IReadOnlyList<ScheduledOperation> Operations, IReadOnlyList<string> Warnings);
public sealed record LoadRow(int Id, string Code, DateOnly WeekStart, decimal Hours, decimal Capacity, decimal LoadPercent, int Operations);

public sealed record ReconciliationLine(int? MaterialId, int? ProductId, string Code, string Unit, decimal QuantityPerUnit, decimal Planned, decimal Issued, decimal InScrap, decimal InFinishedGoods, decimal Balance, decimal UnitPrice, decimal BalanceValue);
public sealed record Reconciliation(int OrderId, string Reference, decimal Planned, decimal Good, decimal Scrap, decimal Received, decimal WorkInProcess, decimal MaterialCost, decimal ServiceCost, decimal? UnitCost, IReadOnlyList<ReconciliationLine> Lines);
