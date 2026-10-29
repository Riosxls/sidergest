using System.Globalization;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Sales;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Certificates;

public sealed record CertificateMeasureInput(CertificateMeasureKind Kind, string Name, string? Specified = null, string? Found = null);

public sealed record CertificateInput(int OrderId, int? OrderLineId = null, int? DeliveryId = null, string? Company = null, string? CustomerPo = null, DateOnly? IssueDate = null, string? InvoiceNumber = null,
    decimal? Quantity = null, string? Unit = null, string? Description = null, string? CustomerPartNumber = null, string? CustomerPartDescription = null, string? RawMaterialLot = null, string? Hardness = null,
    string? Finish = null, string? Notes = null, string? ApprovedBy = null, IReadOnlyList<CertificateMeasureInput>? Measures = null);

public sealed class CertificateService(EbtDbContext db)
{
    public const string DefaultFinish = "Isento de porosidade / Manchas / Riscos e Corrosão";

    // Last numbers issued on paper before the system took over (certificate folders, 2026-10-28); numbering is continuous across years.
    private static readonly Dictionary<string, int> LastPaperNumber = new() { ["EBT"] = 2145, ["BST"] = 5175 };

    private static readonly string[] ChemicalElements = ["C", "Mn", "P", "S", "Si", "Al", "Nb", "Cr", "Cu", "V"];
    private static readonly string[] MechanicalTests = ["LR", "LE", "LA"];
    private static readonly CultureInfo Pt = CultureInfo.GetCultureInfo("pt-BR");

    public static string ReferenceOf(int number, int year) => $"{number}-{year % 100:00}";

    /// <summary>Standard tables of the certificate template, with the dimensional specification taken from the product.</summary>
    public static List<CertificateMeasureInput> TemplateMeasures(Product? p)
    {
        var list = ChemicalElements.Select(e => new CertificateMeasureInput(CertificateMeasureKind.Chemical, e)).ToList();
        list.Add(new(CertificateMeasureKind.Dimensional, "Diâmetro", (p?.DiameterMm ?? p?.WidthMm)?.ToString("0.00", Pt)));
        list.Add(new(CertificateMeasureKind.Dimensional, "Espessura", p?.ThicknessMm?.ToString("0.00", Pt)));
        list.Add(new(CertificateMeasureKind.Dimensional, "Comprimento", p?.LengthMm?.ToString("0.##", Pt)));
        list.AddRange(MechanicalTests.Select(t => new CertificateMeasureInput(CertificateMeasureKind.Mechanical, t)));
        return list;
    }

    public async Task<QualityCertificate> CreateAsync(CertificateInput i, string? user, CancellationToken ct = default)
    {
        var order = await db.SalesOrders.AsNoTracking().Include(o => o.Lines).FirstOrDefaultAsync(o => o.Id == i.OrderId, ct) ?? throw SalesException.NotFound("Order");
        if (order.Status == SalesOrderStatus.Cancelled) throw SalesException.Conflict("Order is cancelled");
        var delivery = i.DeliveryId is { } did
            ? await db.Deliveries.AsNoTracking().Include(d => d.Lines).FirstOrDefaultAsync(d => d.Id == did && d.OrderId == order.Id && d.Status != DeliveryStatus.Cancelled, ct)
                ?? throw SalesException.Invalid("deliveryId", "Not an active delivery of this order")
            : null;
        var lineId = i.OrderLineId ?? (delivery is { Lines.Count: 1 } ? delivery.Lines[0].OrderLineId : order.Lines.Count == 1 ? order.Lines[0].Id : null);
        var line = lineId is { } lid ? order.Lines.FirstOrDefault(l => l.Id == lid) ?? throw SalesException.Invalid("orderLineId", "Not a line of this order") : null;
        if (line is null) throw SalesException.Invalid("orderLineId", "Choose the order line the certificate covers");
        var product = await db.Products.AsNoTracking().FirstOrDefaultAsync(p => p.Id == line.ProductId, ct);
        var link = await db.ProductCustomers.AsNoTracking().FirstOrDefaultAsync(c => c.ProductId == line.ProductId && c.CustomerId == order.CustomerId, ct);
        var deliveryQty = delivery?.Lines.FirstOrDefault(l => l.OrderLineId == line.Id)?.Quantity;
        var quantity = i.Quantity ?? deliveryQty ?? line.Quantity;
        if (quantity <= 0) throw SalesException.Invalid("quantity", "Must be greater than zero");

        var company = SalesService.CompanyOf(i.Company ?? order.Company);
        var date = i.IssueDate ?? SalesService.Today();
        for (var attempt = 0; ; attempt++)
        {
            var number = await NextNumberAsync(company, ct);
            var c = new QualityCertificate
            {
                Company = company, Number = number, Year = date.Year, Reference = ReferenceOf(number, date.Year), OrderId = order.Id, OrderLineId = line.Id, DeliveryId = delivery?.Id, ProductId = line.ProductId,
                CustomerPo = Clean(i.CustomerPo) ?? order.CustomerPo, IssueDate = date, InvoiceNumber = Clean(i.InvoiceNumber), Quantity = quantity, Unit = (Clean(i.Unit) ?? line.Unit).ToUpperInvariant(),
                ProductCode = product?.Code, Description = Clean(i.Description) ?? line.Description, CustomerPartNumber = Clean(i.CustomerPartNumber) ?? line.CustomerPartNumber ?? link?.CustomerPartNumber,
                CustomerPartDescription = Clean(i.CustomerPartDescription) ?? link?.CustomerDescription, RawMaterialLot = Clean(i.RawMaterialLot), Hardness = Clean(i.Hardness), Finish = Clean(i.Finish) ?? DefaultFinish,
                Notes = Clean(i.Notes), ApprovedBy = Clean(i.ApprovedBy), Status = CertificateStatus.Draft, CreatedBy = user, CreatedAt = DateTimeOffset.UtcNow
            };
            SetMeasures(c, i.Measures ?? TemplateMeasures(product));
            db.QualityCertificates.Add(c);
            try
            {
                await db.SaveChangesAsync(ct);
                return c;
            }
            catch (DbUpdateException) when (attempt < 3)
            {
                db.ChangeTracker.Clear(); // another certificate took the number: try the next one
            }
        }
    }

    public async Task<QualityCertificate> UpdateAsync(int id, CertificateInput i, CancellationToken ct = default)
    {
        var c = await LoadAsync(id, ct);
        if (c.Status != CertificateStatus.Draft) throw SalesException.Conflict($"Certificate is {c.Status}; only drafts can be edited");
        await CheckDeliveryAsync(c, i.DeliveryId, ct);
        c.DeliveryId = i.DeliveryId;
        if (i.Quantity is { } q) c.Quantity = q > 0 ? q : throw SalesException.Invalid("quantity", "Must be greater than zero");
        if (i.IssueDate is { } d)
        {
            c.IssueDate = d;
            c.Year = d.Year;
            c.Reference = ReferenceOf(c.Number, c.Year);
        }
        c.CustomerPo = Clean(i.CustomerPo);
        c.InvoiceNumber = Clean(i.InvoiceNumber);
        if (Clean(i.Unit) is { } u) c.Unit = u.ToUpperInvariant();
        if (Clean(i.Description) is { } desc) c.Description = desc;
        c.CustomerPartNumber = Clean(i.CustomerPartNumber);
        c.CustomerPartDescription = Clean(i.CustomerPartDescription);
        c.RawMaterialLot = Clean(i.RawMaterialLot);
        c.Hardness = Clean(i.Hardness);
        c.Finish = Clean(i.Finish) ?? DefaultFinish;
        c.Notes = Clean(i.Notes);
        c.ApprovedBy = Clean(i.ApprovedBy);
        if (i.Measures is not null)
        {
            db.CertificateMeasures.RemoveRange(c.Measures);
            c.Measures = new();
            SetMeasures(c, i.Measures);
        }
        await db.SaveChangesAsync(ct);
        return c;
    }

    /// <summary>Links the certificate to a delivery of the same order (or unlinks it with null). Allowed on issued certificates too, since the delivery is usually planned after the certificate.</summary>
    public async Task<QualityCertificate> LinkDeliveryAsync(int id, int? deliveryId, CancellationToken ct = default)
    {
        var c = await LoadAsync(id, ct);
        if (c.Status == CertificateStatus.Cancelled) throw SalesException.Conflict("Certificate is cancelled");
        await CheckDeliveryAsync(c, deliveryId, ct);
        c.DeliveryId = deliveryId;
        await db.SaveChangesAsync(ct);
        return c;
    }

    private async Task CheckDeliveryAsync(QualityCertificate c, int? deliveryId, CancellationToken ct)
    {
        if (deliveryId is { } did && did != c.DeliveryId && !await db.Deliveries.AnyAsync(d => d.Id == did && d.OrderId == c.OrderId && d.Status != DeliveryStatus.Cancelled, ct))
            throw SalesException.Invalid("deliveryId", "Not an active delivery of this order");
    }

    public async Task<QualityCertificate> IssueAsync(int id, string? user, CancellationToken ct = default)
    {
        var c = await LoadAsync(id, ct);
        if (c.Status != CertificateStatus.Draft) throw SalesException.Conflict($"Certificate is {c.Status}");
        if (c.Measures.All(m => m.Found is null)) throw SalesException.Invalid("measures", "Fill in the values found before issuing");
        c.Status = CertificateStatus.Issued;
        c.IssuedBy = user;
        c.IssuedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        return c;
    }

    public async Task<QualityCertificate> CancelAsync(int id, string? reason, CancellationToken ct = default)
    {
        var c = await LoadAsync(id, ct);
        if (c.Status == CertificateStatus.Cancelled) throw SalesException.Conflict("Certificate is already cancelled");
        c.CancelReason = Clean(reason) ?? throw SalesException.Invalid("reason", "Required");
        c.Status = CertificateStatus.Cancelled;
        await db.SaveChangesAsync(ct);
        return c;
    }

    public async Task DeleteAsync(int id, CancellationToken ct = default)
    {
        var c = await LoadAsync(id, ct);
        if (c.Status != CertificateStatus.Draft) throw SalesException.Conflict($"Certificate is {c.Status}; cancel it instead");
        db.QualityCertificates.Remove(c);
        await db.SaveChangesAsync(ct);
    }

    public async Task SetWaivedAsync(int orderId, bool waived, CancellationToken ct = default)
    {
        var o = await db.SalesOrders.FirstOrDefaultAsync(x => x.Id == orderId, ct) ?? throw SalesException.NotFound("Order");
        o.CertificateWaived = waived;
        await db.SaveChangesAsync(ct);
    }

    private async Task<QualityCertificate> LoadAsync(int id, CancellationToken ct) =>
        await db.QualityCertificates.Include(c => c.Measures).FirstOrDefaultAsync(c => c.Id == id, ct) ?? throw SalesException.NotFound("Certificate");

    private async Task<int> NextNumberAsync(string company, CancellationToken ct)
    {
        var last = await db.QualityCertificates.Where(c => c.Company == company).Select(c => (int?)c.Number).MaxAsync(ct) ?? 0;
        return Math.Max(last, LastPaperNumber.GetValueOrDefault(company)) + 1;
    }

    private static void SetMeasures(QualityCertificate c, IEnumerable<CertificateMeasureInput> measures)
    {
        foreach (var g in measures.Where(m => Clean(m.Name) is not null).GroupBy(m => m.Kind))
            foreach (var (m, n) in g.Select((m, n) => (m, n)))
                c.Measures.Add(new CertificateMeasure { Kind = g.Key, Sequence = n + 1, Name = m.Name.Trim(), Specified = Clean(m.Specified), Found = Clean(m.Found) });
    }

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}
