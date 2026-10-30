namespace Ebt.Core.Entities;

public enum QuoteStatus { Draft = 0, PendingApproval = 1, Approved = 2, Sent = 3, Accepted = 4, Rejected = 5, Expired = 6, Cancelled = 7, Converted = 8, PurchaseOrder = 9 }
public enum SalesOrderStatus { Created = 0, Released = 1, PartiallyShipped = 2, Shipped = 3, Delivered = 4, Cancelled = 5 }
public enum DeliveryStatus { Planned = 0, Shipped = 1, Delivered = 2, Cancelled = 3 }
public enum FreightTerms { Cif = 0, Fob = 1, CustomerPickup = 2 }
public enum SalesRecordKind { Quote = 0, Order = 1, Delivery = 2, Feasibility = 3 }
public enum BillTo { Ebt = 0, Bts = 1 }
public enum OrderOrigin { Email = 0, Fax = 1, Verbal = 2, System = 3 }
public enum DeliveryCondition { Bk = 0, Nbk = 1, Gbk = 2 }
public enum LostReason { Price = 0, LeadTime = 1, Competitor = 2, NoLongerNeeded = 3, Specification = 4, Other = 5, CustomerGaveUp = 6 }

public class SalesSettings
{
    public int Id { get; set; }
    public decimal MaxDiscountPercent { get; set; } = 5m;
    public int DefaultValidityDays { get; set; } = 15;
    public decimal MinimumOrderValue { get; set; }
    public int? ShippingLocationId { get; set; }
    public StockLocation? ShippingLocation { get; set; }
    public string? DefaultConditions { get; set; }
    /// <summary>When on, a quote with a price typed by hand for a product that has no price-list entry also needs the manager's approval (no list price means no discount can be measured).</summary>
    public bool OffListNeedsApproval { get; set; }
    /// <summary>A sent quote with no answer after this many days is flagged for follow-up.</summary>
    public int FollowUpDays { get; set; } = 7;
    /// <summary>A manager's discount approval that is still unsent after this many days lapses (the quote goes back to draft).</summary>
    public int ApprovalValidityDays { get; set; } = 30;
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
    /// <summary>Free-text prazo used only on this quote (when no standard prazo fits).</summary>
    public string? CustomPaymentTerm { get; set; }
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
    /// <summary>Why the customer turned the quote down (set by decline).</summary>
    public LostReason? LostReason { get; set; }
    public string? CustomerPo { get; set; }
    public int? SalesOrderId { get; set; }
    public string? CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    /// <summary>Customer's purchase order (Pedido de compra): free text and/or an attached PDF/image/text file (see <see cref="QuoteRequestFile"/>).</summary>
    public string? RequestText { get; set; }
    public string? RequestFileName { get; set; }
    public string? RequestFileType { get; set; }
    public long? RequestFileSize { get; set; }
    public List<QuoteLine> Lines { get; set; } = new();
}

/// <summary>Bytes of the customer's request attached to a quote, kept apart so quote loads stay light.</summary>
public class QuoteRequestFile
{
    public int QuoteId { get; set; }
    public Quote? Quote { get; set; }
    public required byte[] Data { get; set; }
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
    public string Company { get; set; } = "EBT";
    public int? PaymentTermId { get; set; }
    public PaymentTerm? PaymentTerm { get; set; }
    public string? CustomPaymentTerm { get; set; }
    public FreightTerms Freight { get; set; }
    public SalesOrderStatus Status { get; set; }
    public string? Notes { get; set; }
    public BillTo BillTo { get; set; }
    public OrderOrigin Origin { get; set; } = OrderOrigin.System;
    public string? Salesperson { get; set; }
    public string? StatusReason { get; set; }
    /// <summary>True when the customer does not require quality certificates for this order.</summary>
    public bool CertificateWaived { get; set; }
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
    public decimal? OutsideDiameter { get; set; }
    public decimal? Thickness { get; set; }
    public decimal? Length { get; set; }
    public string? Standard { get; set; }
    public DeliveryCondition? Condition { get; set; }
    public string? SaleUnit { get; set; }
    public decimal? PieceWeightKg { get; set; }
    public decimal? MaterialNeedKg { get; set; }
    public decimal? ToleranceDiameter { get; set; }
    public decimal? ToleranceThickness { get; set; }
    public decimal? ToleranceLengthPlus { get; set; }
    public int? FeasibilityStudyId { get; set; }
    public FeasibilityStudy? FeasibilityStudy { get; set; }
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
    public string? LotNumber { get; set; }
    public decimal? InvoicedValue { get; set; }
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
