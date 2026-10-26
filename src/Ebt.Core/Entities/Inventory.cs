namespace Ebt.Core.Entities;

public enum StockLocationKind { Internal = 0, Quarantine = 1, ThirdParty = 2, Shipping = 3 }
public enum LotStatus { Released = 0, Quarantine = 1, Rejected = 2 }
public enum ReservationStatus { Open = 0, Consumed = 1, Released = 2 }

public enum MovementType
{
    OpeningBalance = 0,
    Receipt = 1,
    ThirdPartyReturn = 2,
    ProductionReceipt = 3,
    CustomerReturn = 4,
    AdjustmentIn = 5,
    Issue = 10,
    IndirectIssue = 11,
    Shipment = 12,
    ReturnToSupplier = 13,
    ThirdPartySend = 14,
    AdjustmentOut = 15,
    Transfer = 20,
    InventoryCount = 21,
    Reversal = 30
}

public class StockLocation
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
    public StockLocationKind Kind { get; set; }
    public bool Active { get; set; } = true;
}

public class StockLot
{
    public int Id { get; set; }
    public int? MaterialId { get; set; }
    public Material? Material { get; set; }
    public int? ProductId { get; set; }
    public Product? Product { get; set; }
    public required string Code { get; set; }
    public LotStatus Status { get; set; }
    public int? SupplierId { get; set; }
    public Supplier? Supplier { get; set; }
    public string? InvoiceNumber { get; set; }
    public string? HeatNumber { get; set; }
    public DateOnly ReceivedOn { get; set; }
    public string? InspectionNote { get; set; }
    public string? InspectedBy { get; set; }
    public DateTimeOffset? InspectedAt { get; set; }
}

public class StockDocument
{
    public int Id { get; set; }
    public MovementType Type { get; set; }
    public DateOnly Date { get; set; }
    public string? Reference { get; set; }
    public int? SupplierId { get; set; }
    public Supplier? Supplier { get; set; }
    public int? CustomerId { get; set; }
    public Customer? Customer { get; set; }
    public string? Notes { get; set; }
    public int? ReversalOfId { get; set; }
    public StockDocument? ReversalOf { get; set; }
    public bool Reversed { get; set; }
    public required string CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public List<StockMovement> Movements { get; set; } = new();
}

public class StockMovement
{
    public long Id { get; set; }
    public int DocumentId { get; set; }
    public StockDocument? Document { get; set; }
    public MovementType Type { get; set; }
    public DateOnly Date { get; set; }
    public int? MaterialId { get; set; }
    public Material? Material { get; set; }
    public int? ProductId { get; set; }
    public Product? Product { get; set; }
    public int LocationId { get; set; }
    public StockLocation? Location { get; set; }
    public int? LotId { get; set; }
    public StockLot? Lot { get; set; }
    public decimal Quantity { get; set; }
    public decimal UnitCost { get; set; }
    public decimal IcmsRate { get; set; }
    public int? ReservationId { get; set; }
}

public class StockBalance
{
    public int Id { get; set; }
    public int? MaterialId { get; set; }
    public Material? Material { get; set; }
    public int? ProductId { get; set; }
    public Product? Product { get; set; }
    public int LocationId { get; set; }
    public StockLocation? Location { get; set; }
    public int? LotId { get; set; }
    public StockLot? Lot { get; set; }
    public decimal Quantity { get; set; }
}

public class StockReservation
{
    public int Id { get; set; }
    public int? MaterialId { get; set; }
    public Material? Material { get; set; }
    public int? ProductId { get; set; }
    public Product? Product { get; set; }
    public int? LocationId { get; set; }
    public StockLocation? Location { get; set; }
    public decimal Quantity { get; set; }
    public decimal Consumed { get; set; }
    public ReservationStatus Status { get; set; }
    public required string Reference { get; set; }
    public DateOnly? NeededOn { get; set; }
    public required string CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public class StockSettings
{
    public int Id { get; set; }
    public bool AllowNegativeStock { get; set; }
    public bool DeductIcmsFromAverage { get; set; } = true;
    public decimal CuttingServicePerKg { get; set; }
    public decimal ScrapResalePerKg { get; set; }
    public decimal ScrapPercent { get; set; }
}

public class StockClosing
{
    public int Id { get; set; }
    public int Period { get; set; }
    public required string ClosedBy { get; set; }
    public DateTimeOffset ClosedAt { get; set; }
}

public class AverageCost
{
    public int Id { get; set; }
    public int Period { get; set; }
    public decimal? ThicknessMm { get; set; }
    public int? MaterialId { get; set; }
    public Material? Material { get; set; }
    public decimal OpeningQuantity { get; set; }
    public decimal OpeningAverage { get; set; }
    public decimal PurchaseQuantity { get; set; }
    public decimal PurchaseValue { get; set; }
    public decimal ServiceQuantity { get; set; }
    public decimal ServiceValue { get; set; }
    public decimal MonthAverage { get; set; }
    public decimal Average { get; set; }
    public decimal AverageGross { get; set; }
    public bool Imported { get; set; }
}
