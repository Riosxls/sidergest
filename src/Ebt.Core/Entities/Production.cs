namespace Ebt.Core.Entities;

public enum ProductionOrderKind { Standard = 0, Internal = 1 }
public enum ProductionOrderStatus { Created = 0, Released = 1, Stopped = 2, InProduction = 3, Cancelled = 4, Finished = 5, Closed = 6 }
public enum OccurrenceKind { Downtime = 0, Scrap = 1 }

public class ProductionSettings
{
    public int Id { get; set; }
    public decimal OverrunTolerancePercent { get; set; } = 3m;
    public decimal HoursPerDay { get; set; } = 8m;
    public bool WorkSaturdays { get; set; }
    public int? IssueLocationId { get; set; }
    public StockLocation? IssueLocation { get; set; }
    public int? ReceiptLocationId { get; set; }
    public StockLocation? ReceiptLocation { get; set; }
}

public class Shift
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
    public TimeOnly? StartsAt { get; set; }
    public TimeOnly? EndsAt { get; set; }
    public decimal? Hours { get; set; }
}

public class Employee
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
    public string? Nickname { get; set; }
    public string? Function { get; set; }
    public int? WorkCenterId { get; set; }
    public WorkCenter? WorkCenter { get; set; }
    public int? ShiftId { get; set; }
    public Shift? Shift { get; set; }
    public bool Active { get; set; } = true;
}

public class ProductionOccurrence
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Description { get; set; }
    public OccurrenceKind Kind { get; set; }
    public bool StopsOrder { get; set; }
}

public class Holiday
{
    public int Id { get; set; }
    public DateOnly Date { get; set; }
    public required string Name { get; set; }
}

public class ProductionOrder
{
    public int Id { get; set; }
    public ProductionOrderKind Kind { get; set; }
    public int Number { get; set; }
    public required string Reference { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }
    public int? CustomerId { get; set; }
    public Customer? Customer { get; set; }
    public decimal Quantity { get; set; }
    public DateOnly DueDate { get; set; }
    public DateOnly? PlannedStart { get; set; }
    public DateOnly? PlannedEnd { get; set; }
    public DateOnly? AdjustedStart { get; set; }
    public DateOnly? AdjustedEnd { get; set; }
    public ProductionOrderStatus Status { get; set; }
    public int? ParentOrderId { get; set; }
    public ProductionOrder? ParentOrder { get; set; }
    public int? PreviousOrderId { get; set; }
    public ProductionOrder? PreviousOrder { get; set; }
    public int? Bales { get; set; }
    public string? Notes { get; set; }
    public string? StatusReason { get; set; }
    public string? CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? ReleasedAt { get; set; }
    public DateTimeOffset? FinishedAt { get; set; }
    public DateTimeOffset? ClosedAt { get; set; }
    public string? ClosedBy { get; set; }
    public DateTimeOffset? CostClosedAt { get; set; }
    public decimal? MaterialCost { get; set; }
    public decimal? ServiceCost { get; set; }
    public decimal? UnitCost { get; set; }
    public List<ProductionOrderOperation> Operations { get; set; } = new();
    public List<ProductionOrderMaterial> Materials { get; set; } = new();
}

public class ProductionOrderOperation
{
    public int Id { get; set; }
    public int OrderId { get; set; }
    public ProductionOrder? Order { get; set; }
    public int Sequence { get; set; }
    public string? Description { get; set; }
    public int? MachineId { get; set; }
    public Machine? Machine { get; set; }
    public int? WorkCenterId { get; set; }
    public WorkCenter? WorkCenter { get; set; }
    public decimal? SetupHours { get; set; }
    public decimal? PiecesPerHour { get; set; }
    public decimal? Operators { get; set; }
    public bool External { get; set; }
    public int? SupplierId { get; set; }
    public Supplier? Supplier { get; set; }
    public int? ExternalLeadDays { get; set; }
    public decimal OverrunReleased { get; set; }
    public decimal PlannedHours { get; set; }
    public DateOnly? PlannedStart { get; set; }
    public DateOnly? PlannedEnd { get; set; }
}

public class ProductionOrderMaterial
{
    public int Id { get; set; }
    public int OrderId { get; set; }
    public ProductionOrder? Order { get; set; }
    public int OperationSequence { get; set; }
    public int? MaterialId { get; set; }
    public Material? Material { get; set; }
    public int? ComponentProductId { get; set; }
    public Product? ComponentProduct { get; set; }
    public decimal QuantityPerUnit { get; set; }
    public decimal RequiredQuantity { get; set; }
    public required string Unit { get; set; }
    public int? ReservationId { get; set; }
    public StockReservation? Reservation { get; set; }
}

public class OverrunRelease
{
    public int Id { get; set; }
    public int OperationId { get; set; }
    public ProductionOrderOperation? Operation { get; set; }
    public decimal Quantity { get; set; }
    public required string Justification { get; set; }
    public string? ReleasedBy { get; set; }
    public DateTimeOffset ReleasedAt { get; set; }
}

public class OutsideShipment
{
    public int Id { get; set; }
    public int OperationId { get; set; }
    public ProductionOrderOperation? Operation { get; set; }
    public int SupplierId { get; set; }
    public Supplier? Supplier { get; set; }
    public DateOnly SentOn { get; set; }
    public decimal Quantity { get; set; }
    public string? InvoiceNumber { get; set; }
    public decimal ReturnedQuantity { get; set; }
    public decimal ScrapQuantity { get; set; }
    public decimal ServiceValue { get; set; }
    public string? Notes { get; set; }
    public string? CreatedBy { get; set; }
}

public class ProductionReport
{
    public int Id { get; set; }
    public int OrderId { get; set; }
    public ProductionOrder? Order { get; set; }
    public int OperationId { get; set; }
    public ProductionOrderOperation? Operation { get; set; }
    public DateOnly Date { get; set; }
    public int? ShiftId { get; set; }
    public Shift? Shift { get; set; }
    public int? EmployeeId { get; set; }
    public Employee? Employee { get; set; }
    public int? MachineId { get; set; }
    public Machine? Machine { get; set; }
    public TimeOnly? StartTime { get; set; }
    public TimeOnly? EndTime { get; set; }
    public decimal? Hours { get; set; }
    public decimal? SetupHours { get; set; }
    public decimal? Operators { get; set; }
    public decimal? DowntimeHours { get; set; }
    public int? DowntimeOccurrenceId { get; set; }
    public ProductionOccurrence? DowntimeOccurrence { get; set; }
    public decimal GoodQuantity { get; set; }
    public decimal ScrapQuantity { get; set; }
    public int? ScrapOccurrenceId { get; set; }
    public ProductionOccurrence? ScrapOccurrence { get; set; }
    public decimal? WeightKg { get; set; }
    public int? OutsideShipmentId { get; set; }
    public OutsideShipment? OutsideShipment { get; set; }
    public string? Notes { get; set; }
    public string? LegacyKey { get; set; }
    public string? ReportedBy { get; set; }
    public DateTimeOffset ReportedAt { get; set; }
}
