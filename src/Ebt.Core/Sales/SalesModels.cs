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

public sealed record SalesLineInput(int ProductId, decimal Quantity, decimal? UnitPrice = null, decimal? IpiPercent = null, decimal? IcmsPercent = null, int? LeadTimeDays = null, DateOnly? DeliveryDate = null, string? Description = null);

public sealed record QuoteInput(int CustomerId, IReadOnlyList<SalesLineInput> Lines, int? AddressId = null, int? PaymentTermId = null, FreightTerms Freight = FreightTerms.Cif, int? ValidityDays = null,
    string? ContactName = null, string? ContactEmail = null, string? CustomerReference = null, string? Conditions = null, string? Notes = null, string? CustomPaymentTerm = null);

public sealed record SalesOrderInput(int CustomerId, int AddressId, IReadOnlyList<SalesLineInput> Lines, string? CustomerPo = null, int? PaymentTermId = null, FreightTerms Freight = FreightTerms.Cif, string? Notes = null, string? Company = null, string? CustomPaymentTerm = null);

public sealed record ConvertInput(int? AddressId = null, string? CustomerPo = null, bool OverrideCredit = false);

public sealed record DeliveryLineInput(int OrderLineId, decimal Quantity);

public sealed record DeliveryInput(DateOnly PlannedDate, int? AddressId = null, string? Carrier = null, IReadOnlyList<DeliveryLineInput>? Lines = null, string? Notes = null);

public sealed record ShipInput(DateOnly Date, string? InvoiceNumber = null, string? Carrier = null, string? VehiclePlate = null, decimal? GrossWeightKg = null, string? Cfop = null, decimal? Freight = null);

public sealed record QuoteTotals(decimal Products, decimal Ipi, decimal Total, decimal MaxDiscountPercent);

public sealed record CreditCheck(decimal? Limit, decimal Open, decimal ThisOrder, bool Exceeded);

public sealed record OrderLineProgress(int LineId, decimal Quantity, decimal FromStock, decimal Produced, decimal Shipped, decimal Planned, decimal Remaining, decimal Available, string? ProductionReference, ProductionOrderStatus? ProductionStatus, bool Ready);

public sealed record OrderProgressInfo(IReadOnlyList<OrderLineProgress> Lines, decimal Progress, bool Ready, bool Late);
