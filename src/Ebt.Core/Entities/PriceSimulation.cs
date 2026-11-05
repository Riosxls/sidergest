namespace Ebt.Core.Entities;

/// <summary>
/// A price simulation a salesperson saved from the simulator (what was asked, what the system suggested and what was decided).
/// Reference data like <see cref="PriceHistory"/>: never wiped by the data reset. <see cref="CustomerId"/> is a plain number, not a foreign key,
/// so deleting customers or sales data never touches it.
/// </summary>
public class PriceSimulation
{
    public int Id { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public string? CreatedBy { get; set; }
    /// <summary>"Round", "Oblong" or "Rectangular".</summary>
    public required string Shape { get; set; }
    public decimal? DiameterMm { get; set; }
    public decimal? WidthMm { get; set; }
    public decimal? HeightMm { get; set; }
    public decimal? ThicknessMm { get; set; }
    public decimal? LengthMm { get; set; }
    public string? Spec { get; set; }
    public decimal? Quantity { get; set; }
    public int? CustomerId { get; set; }
    public string? CustomerName { get; set; }
    public decimal? MarkupPercent { get; set; }
    public decimal? CostPerKg { get; set; }
    public decimal PricePerKg { get; set; }
    public decimal? PricePerPiece { get; set; }
    public required string Basis { get; set; }
    public required string Confidence { get; set; }
    public string? Reason { get; set; }
    public string? Note { get; set; }
    public bool UsedInQuote { get; set; }
}
