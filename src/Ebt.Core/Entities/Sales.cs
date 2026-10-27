namespace Ebt.Core.Entities;

public enum QuoteStatus { Draft = 0, PendingApproval = 1, Approved = 2, Sent = 3, Accepted = 4, Rejected = 5, Expired = 6, Cancelled = 7, Converted = 8 }
public enum SalesOrderStatus { Created = 0, Released = 1, PartiallyShipped = 2, Shipped = 3, Delivered = 4, Cancelled = 5 }
public enum DeliveryStatus { Planned = 0, Shipped = 1, Delivered = 2, Cancelled = 3 }
public enum FreightTerms { Cif = 0, Fob = 1, CustomerPickup = 2 }
public enum SalesRecordKind { Quote = 0, Order = 1, Delivery = 2 }

public class SalesSettings
{
    public int Id { get; set; }
    public decimal MaxDiscountPercent { get; set; } = 5m;
    public int DefaultValidityDays { get; set; } = 15;
    public decimal MinimumOrderValue { get; set; }
    public int? ShippingLocationId { get; set; }
    public StockLocation? ShippingLocation { get; set; }
    public string? DefaultConditions { get; set; }
}

public class PaymentTerm
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
    public required string Days { get; set; }
    public decimal? CreditLimit { get; set; }
    public bool Active { get; set; } = true;
}

public class PriceListEntry
{
    public int Id { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }
    public int? CustomerId { get; set; }
    public Customer? Customer { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal? IpiPercent { get; set; }
    public decimal? IcmsPercent { get; set; }
    public DateOnly ValidFrom { get; set; }
    public DateOnly? ValidTo { get; set; }
}

public class Quote
{
    public int Id { get; set; }
    public int Number { get; set; }
    public int Revision { get; set; }
    public required string Reference { get; set; }
    public int CustomerId { get; set; }
    public Customer? Customer { get; set; }
    public int? AddressId { get; set; }
    public CustomerAddress? Address { get; set; }
    public string? ContactName { get; set; }
    public string? ContactEmail { get; set; }
    public string? CustomerReference { get; set; }
    public int? PaymentTermId { get; set; }
    public PaymentTerm? PaymentTerm { get; set; }
    public FreightTerms Freight { get; set; }
    public int ValidityDays { get; set; }
    public DateOnly? ValidUntil { get; set; }
    public string? Conditions { get; set; }
    public string? Notes { get; set; }
    public QuoteStatus Status { get; set; }
    public bool NeedsApproval { get; set; }
    public string? ApprovedBy { get; set; }
    public DateTimeOffset? ApprovedAt { get; set; }
    public DateTimeOffset? SentAt { get; set; }
    public string? SentTo { get; set; }
    public DateTimeOffset? DecidedAt { get; set; }
    public string? DecisionBy { get; set; }
    public string? DecisionNote { get; set; }
    public string? CustomerPo { get; set; }
    public int? SalesOrderId { get; set; }
    public string? CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public List<QuoteLine> Lines { get; set; } = new();
}

public class QuoteLine
{
    public int Id { get; set; }
    public int QuoteId { get; set; }
    public Quote? Quote { get; set; }
    public int Sequence { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }
    public string? CustomerPartNumber { get; set; }
    public required string Description { get; set; }
    public decimal Quantity { get; set; }
    public required string Unit { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal? ListPrice { get; set; }
    public decimal IpiPercent { get; set; }
    public decimal IcmsPercent { get; set; }
    public int? LeadTimeDays { get; set; }
    public DateOnly? DeliveryDate { get; set; }
}

public class SalesOrder
{
    public int Id { get; set; }
    public int Number { get; set; }
    public required string Reference { get; set; }
    public int? QuoteId { get; set; }
    public Quote? Quote { get; set; }
    public int CustomerId { get; set; }
    public Customer? Customer { get; set; }
    public int AddressId { get; set; }
    public CustomerAddress? Address { get; set; }
    public string? CustomerPo { get; set; }
    public int? PaymentTermId { get; set; }
    public PaymentTerm? PaymentTerm { get; set; }
    public FreightTerms Freight { get; set; }
    public SalesOrderStatus Status { get; set; }
    public string? Notes { get; set; }
    public string? StatusReason { get; set; }
    public string? CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public string? ReleasedBy { get; set; }
    public DateTimeOffset? ReleasedAt { get; set; }
    public List<SalesOrderLine> Lines { get; set; } = new();
}

public class SalesOrderLine
{
    public int Id { get; set; }
    public int OrderId { get; set; }
    public SalesOrder? Order { get; set; }
    public int Sequence { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }
    public string? CustomerPartNumber { get; set; }
    public required string Description { get; set; }
    public decimal Quantity { get; set; }
    public required string Unit { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal IpiPercent { get; set; }
    public decimal IcmsPercent { get; set; }
    public DateOnly DueDate { get; set; }
    public decimal FromStock { get; set; }
    public int? ReservationId { get; set; }
    public StockReservation? Reservation { get; set; }
    public int? ProductionOrderId { get; set; }
    public ProductionOrder? ProductionOrder { get; set; }
}

public class Delivery
{
    public int Id { get; set; }
    public int Number { get; set; }
    public required string Reference { get; set; }
    public int OrderId { get; set; }
    public SalesOrder? Order { get; set; }
    public int AddressId { get; set; }
    public CustomerAddress? Address { get; set; }
    public DateOnly PlannedDate { get; set; }
    public DeliveryStatus Status { get; set; }
    public string? Carrier { get; set; }
    public string? VehiclePlate { get; set; }
    public string? InvoiceNumber { get; set; }
    public int Packages { get; set; }
    public decimal? GrossWeightKg { get; set; }
    public int? StockDocumentId { get; set; }
    public StockDocument? StockDocument { get; set; }
    public string? Notes { get; set; }
    public string? CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public string? ShippedBy { get; set; }
    public DateTimeOffset? ShippedAt { get; set; }
    public DateTimeOffset? DeliveredAt { get; set; }
    public string? ReceivedBy { get; set; }
    public List<DeliveryLine> Lines { get; set; } = new();
}

public class DeliveryLine
{
    public int Id { get; set; }
    public int DeliveryId { get; set; }
    public Delivery? Delivery { get; set; }
    public int OrderLineId { get; set; }
    public SalesOrderLine? OrderLine { get; set; }
    public decimal Quantity { get; set; }
    public int Packages { get; set; }
}

public class SalesEvent
{
    public long Id { get; set; }
    public SalesRecordKind Kind { get; set; }
    public int RecordId { get; set; }
    public required string Action { get; set; }
    public string? FromStatus { get; set; }
    public string? ToStatus { get; set; }
    public string? Note { get; set; }
    public string? User { get; set; }
    public DateTimeOffset At { get; set; }
}
