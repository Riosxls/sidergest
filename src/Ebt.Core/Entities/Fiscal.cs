namespace Ebt.Core.Entities;

public enum FiscalKind { Sale = 0, OutsideShipment = 1 }
public enum FiscalStatus { Authorized = 0, Cancelled = 1 }
/// <summary>NF-e tpAmb values.</summary>
public enum SefazEnvironment { Production = 1, Homologation = 2 }

/// <summary>Issuer data and numbering for NF-e. One row. Fiscal emission only runs when <see cref="Enabled"/> is set.</summary>
public class FiscalSettings
{
    public int Id { get; set; }
    public bool Enabled { get; set; }
    public SefazEnvironment Environment { get; set; } = SefazEnvironment.Homologation;
    public string? CompanyName { get; set; }
    public string? TradeName { get; set; }
    public string? Cnpj { get; set; }
    public string? StateRegistration { get; set; }
    /// <summary>CRT: 1 Simples, 2 Simples excess, 3 regime normal (EBT is 3).</summary>
    public int TaxRegime { get; set; } = 3;
    public string? Street { get; set; }
    public string? Number { get; set; }
    public string? Complement { get; set; }
    public string? District { get; set; }
    public string? City { get; set; }
    public string? CityIbgeCode { get; set; }
    public string Uf { get; set; } = "SP";
    public string? ZipCode { get; set; }
    public string? Phone { get; set; }
    public int Series { get; set; } = 1;
    /// <summary>Next NF number. Only advances when SEFAZ authorizes, so rejections never burn a number.</summary>
    public int NextNumber { get; set; } = 2581;
    public int CancelWindowHours { get; set; } = 24;
}

/// <summary>Fiscal rules of a CFOP: CSTs, legal text and what the operation triggers.</summary>
public class Cfop
{
    public required string Code { get; set; }
    public required string Description { get; set; }
    public FiscalKind Kind { get; set; }
    public bool Taxed { get; set; }
    public required string IcmsCst { get; set; }
    public required string IpiCst { get; set; }
    public required string PisCst { get; set; }
    public required string CofinsCst { get; set; }
    public decimal DefaultPisPercent { get; set; }
    public decimal DefaultCofinsPercent { get; set; }
    /// <summary>IPI legal framing code (cEnq).</summary>
    public string IpiFramingCode { get; set; } = "999";
    public bool GeneratesInstallments { get; set; }
    public bool Active { get; set; } = true;
    public string? LegalText { get; set; }
}

/// <summary>Tax rates for product x customer x CFOP. A rule with no customer applies to every customer.</summary>
public class TaxRule
{
    public int Id { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }
    public int? CustomerId { get; set; }
    public Customer? Customer { get; set; }
    public required string CfopCode { get; set; }
    public Cfop? Cfop { get; set; }
    public string? IcmsCst { get; set; }
    public decimal IcmsPercent { get; set; }
    public decimal IcmsBaseReductionPercent { get; set; }
    public string? IpiCst { get; set; }
    public decimal IpiPercent { get; set; }
    public decimal? PisPercent { get; set; }
    public decimal? CofinsPercent { get; set; }
}

/// <summary>Monthly price table (legacy PRECOPECA): the NF price of product x customer x CFOP for one month. Emission is blocked without it.</summary>
public class MonthlyPrice
{
    public int Id { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }
    public int CustomerId { get; set; }
    public Customer? Customer { get; set; }
    public required string CfopCode { get; set; }
    public int Year { get; set; }
    public int Month { get; set; }
    public decimal UnitPrice { get; set; }
}

/// <summary>An NF-e authorized by SEFAZ. Rows exist only after authorization; a rejected NF leaves nothing behind.</summary>
public class FiscalDocument
{
    public int Id { get; set; }
    public FiscalKind Kind { get; set; }
    public FiscalStatus Status { get; set; }
    public required string CfopCode { get; set; }
    public int Series { get; set; }
    public int Number { get; set; }
    public required string AccessKey { get; set; }
    public SefazEnvironment Environment { get; set; }
    /// <summary>True when the authorization came from the local stub, not from SEFAZ.</summary>
    public bool Simulated { get; set; }
    public required string Protocol { get; set; }
    public DateTimeOffset IssuedAt { get; set; }
    public string? IssuedBy { get; set; }
    public int? DeliveryId { get; set; }
    public Delivery? Delivery { get; set; }
    public int? OutsideShipmentId { get; set; }
    public OutsideShipment? OutsideShipment { get; set; }
    public int? CustomerId { get; set; }
    public Customer? Customer { get; set; }
    public int? SupplierId { get; set; }
    public Supplier? Supplier { get; set; }
    public required string RecipientName { get; set; }
    public required string RecipientDocument { get; set; }
    public required string RecipientUf { get; set; }
    public decimal ProductsTotal { get; set; }
    public decimal FreightTotal { get; set; }
    public decimal IcmsBase { get; set; }
    public decimal IcmsTotal { get; set; }
    public decimal IpiTotal { get; set; }
    public decimal PisTotal { get; set; }
    public decimal CofinsTotal { get; set; }
    public decimal InvoiceTotal { get; set; }
    public string? AdditionalInfo { get; set; }
    public required string Xml { get; set; }
    public DateTimeOffset? CancelledAt { get; set; }
    public string? CancelledBy { get; set; }
    public string? CancelReason { get; set; }
    public string? CancelProtocol { get; set; }
    public List<FiscalDocumentLine> Lines { get; set; } = new();
    public List<FiscalInstallment> Installments { get; set; } = new();
}

public class FiscalDocumentLine
{
    public int Id { get; set; }
    public int DocumentId { get; set; }
    public FiscalDocument? Document { get; set; }
    public int Sequence { get; set; }
    public int? ProductId { get; set; }
    public Product? Product { get; set; }
    public int? ProductionOrderId { get; set; }
    public ProductionOrder? ProductionOrder { get; set; }
    public required string Code { get; set; }
    public required string Description { get; set; }
    public required string Ncm { get; set; }
    public required string Unit { get; set; }
    public decimal Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal Total { get; set; }
    /// <summary>Share of the NF freight charged on this item (goes into the ICMS and IPI bases).</summary>
    public decimal Freight { get; set; }
    public required string IcmsCst { get; set; }
    public decimal IcmsBase { get; set; }
    public decimal IcmsPercent { get; set; }
    public decimal IcmsValue { get; set; }
    public decimal IcmsBaseReductionPercent { get; set; }
    public required string IpiCst { get; set; }
    public decimal IpiBase { get; set; }
    public decimal IpiPercent { get; set; }
    public decimal IpiValue { get; set; }
    public required string PisCst { get; set; }
    public decimal PisPercent { get; set; }
    public decimal PisValue { get; set; }
    public required string CofinsCst { get; set; }
    public decimal CofinsPercent { get; set; }
    public decimal CofinsValue { get; set; }
}

/// <summary>Duplicata of a sale NF.</summary>
public class FiscalInstallment
{
    public int Id { get; set; }
    public int DocumentId { get; set; }
    public FiscalDocument? Document { get; set; }
    public int Sequence { get; set; }
    public DateOnly DueDate { get; set; }
    public decimal Amount { get; set; }
}
