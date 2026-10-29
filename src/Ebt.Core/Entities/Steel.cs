namespace Ebt.Core.Entities;

public class SteelLot
{
    public int Id { get; set; }
    public required string LotCode { get; set; }
    public int SupplierId { get; set; }
    public Supplier? Supplier { get; set; }
    public string? PurchaseInvoice { get; set; }
    public DateOnly ReceivedDate { get; set; }
    public string? Specification { get; set; }
    public decimal? Thickness { get; set; }
    public decimal? Width { get; set; }
    public decimal WeightKg { get; set; }
    public decimal PricePerKg { get; set; }
    public string? Notes { get; set; }
    public string? CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public List<SlitterJob> SlitterJobs { get; set; } = new();
    public List<SteelUsage> Usages { get; set; } = new();
}

public class SlitterJob
{
    public int Id { get; set; }
    public int LotId { get; set; }
    public SteelLot? Lot { get; set; }
    public int ProcessorId { get; set; }
    public Supplier? Processor { get; set; }
    public string? ShipmentInvoice { get; set; }
    public DateOnly ShipmentDate { get; set; }
    public decimal SentKg { get; set; }
    public string? ReturnInvoice { get; set; }
    public DateOnly? ReturnDate { get; set; }
    public decimal? FinishedKg { get; set; }
    public decimal? ScrapKg { get; set; }
    public decimal? ServiceCost { get; set; }
    public string? Notes { get; set; }
}

public class SteelUsage
{
    public int Id { get; set; }
    public int LotId { get; set; }
    public SteelLot? Lot { get; set; }
    public DateOnly Date { get; set; }
    public decimal Kg { get; set; }
    public decimal LaborCost { get; set; }
    public string? Reference { get; set; }
    public string? Notes { get; set; }
}
