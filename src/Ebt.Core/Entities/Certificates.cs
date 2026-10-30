namespace Ebt.Core.Entities;

public enum CertificateStatus { Draft = 0, Issued = 1, Cancelled = 2 }
public enum CertificateMeasureKind { Chemical = 0, Dimensional = 1, Mechanical = 2 }

/// <summary>
/// Quality certificate ("Certificado de Qualidade") sent with a shipment. One certificate covers one order line and, once the
/// delivery is planned, is linked to it so the NF number can be taken from the delivery.
/// </summary>
public class QualityCertificate
{
    public int Id { get; set; }
    /// <summary>EBT or BST: each company has its own numbering and letterhead.</summary>
    public required string Company { get; set; }
    public int Number { get; set; }
    public int Year { get; set; }
    public required string Reference { get; set; }
    public int OrderId { get; set; }
    public SalesOrder? Order { get; set; }
    public int? OrderLineId { get; set; }
    public SalesOrderLine? OrderLine { get; set; }
    public int? DeliveryId { get; set; }
    public Delivery? Delivery { get; set; }
    public int? ProductId { get; set; }
    public Product? Product { get; set; }
    public string? CustomerPo { get; set; }
    public DateOnly IssueDate { get; set; }
    /// <summary>NF typed on the certificate; when empty the NF of the linked delivery is used.</summary>
    public string? InvoiceNumber { get; set; }
    public decimal Quantity { get; set; }
    public required string Unit { get; set; }
    public string? ProductCode { get; set; }
    public required string Description { get; set; }
    public string? CustomerPartNumber { get; set; }
    public string? CustomerPartDescription { get; set; }
    public string? RawMaterialLot { get; set; }
    public string? Hardness { get; set; }
    public string? Finish { get; set; }
    /// <summary>Heading variant, e.g. "CERTIFICADO DE GARANTIA DA QUALIDADE DO PRODUTO" for customers that ask for it; empty means the standard title.</summary>
    public string? Title { get; set; }
    public string? Notes { get; set; }
    public string? ApprovedBy { get; set; }
    public CertificateStatus Status { get; set; }
    public string? CancelReason { get; set; }
    public string? CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public string? IssuedBy { get; set; }
    public DateTimeOffset? IssuedAt { get; set; }
    public List<CertificateMeasure> Measures { get; set; } = new();
}

/// <summary>One row of the chemical, dimensional or mechanical tables (specified vs. found).</summary>
public class CertificateMeasure
{
    public int Id { get; set; }
    public int CertificateId { get; set; }
    public QualityCertificate? Certificate { get; set; }
    public CertificateMeasureKind Kind { get; set; }
    public int Sequence { get; set; }
    public required string Name { get; set; }
    public string? Specified { get; set; }
    public string? Found { get; set; }
}

/// <summary>
/// What repeats from one certificate to the next for the same product and customer: the specified limits, the title, the finish line and the standing
/// observation. Learned when a certificate is issued, so the next one starts filled in; the found values never come from here.
/// </summary>
public class CertificateTemplate
{
    public int Id { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }
    public int CustomerId { get; set; }
    public Customer? Customer { get; set; }
    public string? Title { get; set; }
    public string? Finish { get; set; }
    public string? Notes { get; set; }
    public string? UpdatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    /// <summary>Reference of the certificate this template was last learned from.</summary>
    public string? LearnedFrom { get; set; }
    public List<CertificateTemplateMeasure> Measures { get; set; } = new();
}

public class CertificateTemplateMeasure
{
    public int Id { get; set; }
    public int TemplateId { get; set; }
    public CertificateTemplate? Template { get; set; }
    public CertificateMeasureKind Kind { get; set; }
    public int Sequence { get; set; }
    public required string Name { get; set; }
    public string? Specified { get; set; }
}
