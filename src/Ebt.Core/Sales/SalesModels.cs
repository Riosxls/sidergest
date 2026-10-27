using Ebt.Core.Entities;

namespace Ebt.Core.Sales;

public sealed class SalesException(int status, string message, string? field = null) : Exception(message)
{
    public int Status { get; } = status;
    public string? Field { get; } = field;

    public static SalesException Invalid(string field, string message) => new(400, message, field);
    public static SalesException Conflict(string message) => new(409, message);
    public static SalesException NotFound(string what) => new(404, $"{what} not found");
}

public sealed record LineSpec(decimal? OutsideDiameter = null, decimal? Thickness = null, decimal? Length = null, string? Standard = null, DeliveryCondition? Condition = null, string? SaleUnit = null,
    decimal? PieceWeightKg = null, decimal? MaterialNeedKg = null, decimal? ToleranceDiameter = null, decimal? ToleranceThickness = null, decimal? ToleranceLengthPlus = null);

public sealed record SalesLineInput(int ProductId, decimal Quantity, decimal? UnitPrice = null, decimal? IpiPercent = null, decimal? IcmsPercent = null, int? LeadTimeDays = null, DateOnly? DeliveryDate = null, string? Description = null,
    LineSpec? Spec = null, int? FeasibilityId = null);

public sealed record QuoteInput(int CustomerId, IReadOnlyList<SalesLineInput> Lines, int? AddressId = null, int? PaymentTermId = null, FreightTerms Freight = FreightTerms.Cif, int? ValidityDays = null,
    string? ContactName = null, string? ContactEmail = null, string? CustomerReference = null, string? Conditions = null, string? Notes = null);

public sealed record SalesOrderInput(int CustomerId, int AddressId, IReadOnlyList<SalesLineInput> Lines, string? CustomerPo = null, int? PaymentTermId = null, FreightTerms Freight = FreightTerms.Cif, string? Notes = null,
    BillTo BillTo = BillTo.Ebt, OrderOrigin Origin = OrderOrigin.System, string? Salesperson = null);

public sealed record ConvertInput(int? AddressId = null, string? CustomerPo = null, bool OverrideCredit = false);

public sealed record DeliveryLineInput(int OrderLineId, decimal Quantity);

public sealed record DeliveryInput(DateOnly PlannedDate, int? AddressId = null, string? Carrier = null, IReadOnlyList<DeliveryLineInput>? Lines = null, string? Notes = null);

public sealed record ShipInput(DateOnly Date, string? InvoiceNumber = null, string? Carrier = null, string? VehiclePlate = null, decimal? GrossWeightKg = null, string? LotNumber = null, decimal? InvoicedValue = null);

public sealed record QuoteTotals(decimal Products, decimal Ipi, decimal Total, decimal MaxDiscountPercent);

public sealed record CreditCheck(decimal? Limit, decimal Open, decimal ThisOrder, bool Exceeded);

public sealed record OrderLineProgress(int LineId, decimal Quantity, decimal FromStock, decimal Produced, decimal Shipped, decimal Planned, decimal Remaining, decimal Available, string? ProductionReference, ProductionOrderStatus? ProductionStatus, bool Ready);

public sealed record OrderProgressInfo(IReadOnlyList<OrderLineProgress> Lines, decimal Progress, bool Ready, bool Late);

public static class LineSpecExtensions
{
    public static SalesOrderLine WithSpec(this SalesOrderLine l, LineSpec? s)
    {
        if (s is null) return l;
        foreach (var (name, v) in new[] { ("outsideDiameter", s.OutsideDiameter), ("thickness", s.Thickness), ("length", s.Length), ("pieceWeightKg", s.PieceWeightKg), ("materialNeedKg", s.MaterialNeedKg),
                     ("toleranceDiameter", s.ToleranceDiameter), ("toleranceThickness", s.ToleranceThickness), ("toleranceLengthPlus", s.ToleranceLengthPlus) })
            if (v < 0) throw SalesException.Invalid($"spec.{name}", "Cannot be negative");
        var unit = string.IsNullOrWhiteSpace(s.SaleUnit) ? null : s.SaleUnit.Trim().ToUpperInvariant();
        if (unit is not (null or "KG" or "PC")) throw SalesException.Invalid("spec.saleUnit", "KG or PC");
        l.OutsideDiameter = s.OutsideDiameter;
        l.Thickness = s.Thickness;
        l.Length = s.Length;
        l.Standard = string.IsNullOrWhiteSpace(s.Standard) ? null : s.Standard.Trim();
        l.Condition = s.Condition;
        l.SaleUnit = unit;
        l.PieceWeightKg = s.PieceWeightKg;
        l.MaterialNeedKg = s.MaterialNeedKg ?? unit switch
        {
            "KG" => Math.Round(l.Quantity, 3),
            "PC" when s.PieceWeightKg is { } w => Math.Round(l.Quantity * w, 3),
            _ => null
        };
        l.ToleranceDiameter = s.ToleranceDiameter;
        l.ToleranceThickness = s.ToleranceThickness;
        l.ToleranceLengthPlus = s.ToleranceLengthPlus;
        return l;
    }

    public static LineSpec? ToSpec(this SalesOrderLine l) =>
        l.OutsideDiameter is null && l.Thickness is null && l.Length is null && l.Standard is null && l.Condition is null && l.SaleUnit is null && l.PieceWeightKg is null && l.MaterialNeedKg is null
            && l.ToleranceDiameter is null && l.ToleranceThickness is null && l.ToleranceLengthPlus is null
            ? null
            : new LineSpec(l.OutsideDiameter, l.Thickness, l.Length, l.Standard, l.Condition, l.SaleUnit, l.PieceWeightKg, l.MaterialNeedKg, l.ToleranceDiameter, l.ToleranceThickness, l.ToleranceLengthPlus);
}
