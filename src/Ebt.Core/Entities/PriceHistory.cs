namespace Ebt.Core.Entities;

/// <summary>
/// One past sale of a circular tube (imported from the legacy sales workbook). Reference data for the price suggestion: never wiped by the data reset.
/// <see cref="PricePerKg"/> is the unit price converted to R$/kg with the net weight of the dimensions.
/// </summary>
public class PriceHistory
{
    public int Id { get; set; }
    public DateOnly Date { get; set; }
    public required string CustomerName { get; set; }
    public decimal DiameterMm { get; set; }
    public decimal ThicknessMm { get; set; }
    public decimal LengthMm { get; set; }
    /// <summary>"KG" or "PC".</summary>
    public required string Unit { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal WeightKg { get; set; }
    public decimal PricePerKg { get; set; }
    /// <summary>Material specification class (EN10305, NBK, BK, NBR, SAE, other) or null when unknown; see <c>PriceSpec</c>.</summary>
    public string? Spec { get; set; }
    /// <summary>Dedupe key (first 6 letters of the customer|diameter|thickness|length|unit|price); unique. A re-import with the same key keeps the latest date and any spec.</summary>
    public required string ImportKey { get; set; }
    public string Source { get; set; } = "Import";
}
