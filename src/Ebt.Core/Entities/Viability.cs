namespace Ebt.Core.Entities;

public enum FeasibilityStatus { Draft = 0, InReview = 1, Approved = 2, Rejected = 3 }
public enum SignoffArea { Quality = 0, Production = 1, Commercial = 2 }

public class FeasibilityStudy
{
    public const int DefaultOrdersAllowed = 3;

    public int Id { get; set; }
    public int Number { get; set; }
    public required string Reference { get; set; }
    public int? QuoteId { get; set; }
    public Quote? Quote { get; set; }
    public int CustomerId { get; set; }
    public Customer? Customer { get; set; }
    public int? ProductId { get; set; }
    public Product? Product { get; set; }
    public required string Title { get; set; }
    public string? Characteristics { get; set; }
    public string? Transformations { get; set; }
    public string? Finishing { get; set; }
    public string? Packaging { get; set; }
    public decimal? MonthlyConsumptionKg { get; set; }
    public int OrdersAllowed { get; set; } = DefaultOrdersAllowed;
    public FeasibilityStatus Status { get; set; }
    public string? RejectionReason { get; set; }
    public string? QualityBy { get; set; }
    public DateTimeOffset? QualityAt { get; set; }
    public string? QualityNote { get; set; }
    public string? ProductionBy { get; set; }
    public DateTimeOffset? ProductionAt { get; set; }
    public string? ProductionNote { get; set; }
    public string? CommercialBy { get; set; }
    public DateTimeOffset? CommercialAt { get; set; }
    public string? CommercialNote { get; set; }
    public string? CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}
