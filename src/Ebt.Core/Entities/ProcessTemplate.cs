namespace Ebt.Core.Entities;

/// <summary>
/// The secondary process (operations with requirements and measures) that the legacy system wrote on the OF of a customer and tube.
/// Reference data for the process suggestion on new OFs: imported from the legacy workbooks (scripts/export-process-templates.ps1), never wiped by the data reset.
/// One row per (customer key, diameter, thickness, length); the latest <see cref="SourceDate"/> wins.
/// </summary>
public class ProcessTemplate
{
    public int Id { get; set; }
    /// <summary>First six letters (A-Z, no accents) of the customer name, upper case; see <c>PriceHistoryImporter.CustomerKey</c>.</summary>
    public string? CustomerKey { get; set; }
    public required string CustomerName { get; set; }
    public decimal DiameterMm { get; set; }
    public decimal? ThicknessMm { get; set; }
    public decimal? LengthMm { get; set; }
    public string? Spec { get; set; }
    /// <summary>Legacy OF number the process was taken from (for example 04679-26).</summary>
    public required string SourceRef { get; set; }
    public DateOnly? SourceDate { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public List<ProcessTemplateOperation> Operations { get; set; } = new();
}

public class ProcessTemplateOperation
{
    public int Id { get; set; }
    public int TemplateId { get; set; }
    public ProcessTemplate? Template { get; set; }
    public int Sequence { get; set; }
    public required string Description { get; set; }
    public string? Tolerance { get; set; }
    public string? MeasureStart { get; set; }
    public string? MeasureEnd { get; set; }
    /// <summary>Machine or tool written on the legacy paper (Perfiladeira, Trefiladeira, Visual/Dimensional...).</summary>
    public string? Resource { get; set; }
}
