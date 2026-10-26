namespace Ebt.Core.Entities;

public enum RequisitionStatus { PendingApproval = 0, Approved = 1, Rejected = 2, Quoting = 3, QuoteApproved = 4, QuoteRejected = 5, OrderIssued = 6, PartiallyReceived = 7, Received = 8, Cancelled = 9 }
public enum QuotationStatus { Open = 0, Closed = 1, Cancelled = 2 }
public enum BidStatus { Pending = 0, Approved = 1, Rejected = 2 }
public enum PurchaseOrderStatus { Open = 0, PartiallyReceived = 1, Received = 2, Closed = 3, Cancelled = 4 }

public class PurchasingSettings
{
    public int Id { get; set; }
    public decimal ReceivingTolerancePercent { get; set; } = 5m;
    public bool AllowEarlyReceipt { get; set; }
    public int EarlyReceiptGraceDays { get; set; }
    public int? ReceivingLocationId { get; set; }
    public StockLocation? ReceivingLocation { get; set; }
}

public class PurchaseRequisition
{
    public int Id { get; set; }
    public int Number { get; set; }
    public int? MaterialId { get; set; }
    public Material? Material { get; set; }
    public required string Description { get; set; }
    public required string Unit { get; set; }
    public decimal Quantity { get; set; }
    public decimal? ApprovedQuantity { get; set; }
    public string? Department { get; set; }
    public DateOnly? NeededBy { get; set; }
    public string? Application { get; set; }
    public string? Notes { get; set; }
    public RequisitionStatus Status { get; set; }
    public string? RequestedBy { get; set; }
    public DateTimeOffset RequestedAt { get; set; }
    public string? DecidedBy { get; set; }
    public DateTimeOffset? DecidedAt { get; set; }
    public string? DecisionNote { get; set; }
    public int? QuotationItemId { get; set; }
    public QuotationItem? QuotationItem { get; set; }
    public int? PurchaseOrderLineId { get; set; }
    public PurchaseOrderLine? PurchaseOrderLine { get; set; }
}

public class Quotation
{
    public int Id { get; set; }
    public int Number { get; set; }
    public QuotationStatus Status { get; set; }
    public string? Notes { get; set; }
    public string? CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public List<QuotationItem> Items { get; set; } = new();
}

public class QuotationItem
{
    public int Id { get; set; }
    public int QuotationId { get; set; }
    public Quotation? Quotation { get; set; }
    public int Item { get; set; }
    public int? MaterialId { get; set; }
    public Material? Material { get; set; }
    public required string Description { get; set; }
    public required string Unit { get; set; }
    public decimal Quantity { get; set; }
    public List<QuotationBid> Bids { get; set; } = new();
    public List<PurchaseRequisition> Requisitions { get; set; } = new();
}

public class QuotationBid
{
    public int Id { get; set; }
    public int QuotationItemId { get; set; }
    public QuotationItem? QuotationItem { get; set; }
    public int SupplierId { get; set; }
    public Supplier? Supplier { get; set; }
    public decimal? UnitPrice { get; set; }
    public decimal DiscountPercent { get; set; }
    public decimal IcmsPercent { get; set; }
    public decimal IpiPercent { get; set; }
    public int? LeadTimeDays { get; set; }
    public string? PaymentTerms { get; set; }
    public string? Notes { get; set; }
    public BidStatus Status { get; set; }
    public DateTimeOffset? RespondedAt { get; set; }
}

public class PurchaseOrder
{
    public int Id { get; set; }
    public int Number { get; set; }
    public int SupplierId { get; set; }
    public Supplier? Supplier { get; set; }
    public PurchaseOrderStatus Status { get; set; }
    public string? PaymentTerms { get; set; }
    public string? Notes { get; set; }
    public string? IssuedBy { get; set; }
    public DateTimeOffset IssuedAt { get; set; }
    public string? ClosedBy { get; set; }
    public DateTimeOffset? ClosedAt { get; set; }
    public string? CloseReason { get; set; }
    public List<PurchaseOrderLine> Lines { get; set; } = new();
}

public class PurchaseOrderLine
{
    public int Id { get; set; }
    public int PurchaseOrderId { get; set; }
    public PurchaseOrder? PurchaseOrder { get; set; }
    public int LineNumber { get; set; }
    public int? MaterialId { get; set; }
    public Material? Material { get; set; }
    public required string Description { get; set; }
    public required string Unit { get; set; }
    public decimal Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal DiscountPercent { get; set; }
    public decimal IcmsPercent { get; set; }
    public decimal IpiPercent { get; set; }
    public DateOnly DueDate { get; set; }
    public decimal ReceivedQuantity { get; set; }
    public bool Closed { get; set; }
    public int? QuotationBidId { get; set; }
    public QuotationBid? QuotationBid { get; set; }
    public List<PurchaseRequisition> Requisitions { get; set; } = new();
}

public class GoodsReceipt
{
    public int Id { get; set; }
    public int Number { get; set; }
    public int SupplierId { get; set; }
    public Supplier? Supplier { get; set; }
    public required string InvoiceNumber { get; set; }
    public string InvoiceSeries { get; set; } = "";
    public DateOnly InvoiceDate { get; set; }
    public DateTimeOffset ReceivedAt { get; set; }
    public string? ReceivedBy { get; set; }
    public decimal? InvoiceTotal { get; set; }
    public decimal CalculatedTotal { get; set; }
    public string? DivergenceJustification { get; set; }
    public string? Notes { get; set; }
    public List<GoodsReceiptLine> Lines { get; set; } = new();
    public List<PayableInstallment> Installments { get; set; } = new();
}

public class GoodsReceiptLine
{
    public int Id { get; set; }
    public int GoodsReceiptId { get; set; }
    public GoodsReceipt? GoodsReceipt { get; set; }
    public int PurchaseOrderLineId { get; set; }
    public PurchaseOrderLine? PurchaseOrderLine { get; set; }
    public int? MaterialId { get; set; }
    public Material? Material { get; set; }
    public decimal Quantity { get; set; }
    public required string Unit { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal DiscountPercent { get; set; }
    public decimal IcmsPercent { get; set; }
    public decimal IpiPercent { get; set; }
    public decimal Total { get; set; }
    public string? LotCode { get; set; }
}

public class PayableInstallment
{
    public int Id { get; set; }
    public int GoodsReceiptId { get; set; }
    public GoodsReceipt? GoodsReceipt { get; set; }
    public int Sequence { get; set; }
    public DateOnly DueDate { get; set; }
    public decimal Amount { get; set; }
}

public class SupplierMaterial
{
    public int SupplierId { get; set; }
    public Supplier? Supplier { get; set; }
    public int MaterialId { get; set; }
    public Material? Material { get; set; }
    public string? Qualification { get; set; }
    public DateOnly? QualifiedAt { get; set; }
    public decimal? LastUnitPrice { get; set; }
    public DateOnly? LastPurchaseDate { get; set; }
    public string? Notes { get; set; }
}
