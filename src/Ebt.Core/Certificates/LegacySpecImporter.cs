using System.Reflection;
using System.Text.Json;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Certificates;

public sealed record LegacySpecRow(string Name, string? Specified, string? Found = null);

/// <summary>Specification of one customer+product read from the Excel certificates of 2025-26 (latest certificate of each combination, see legacy-specs.json).</summary>
public sealed record LegacySpec(string Customer, decimal Diameter, decimal Thickness, decimal? Length, string? Title, string? Finish, string? Notes, string? CustomerPartNumber, string? CustomerPartDescription,
    string LearnedFrom, int Certificates, List<LegacySpecRow> Chemical, List<LegacySpecRow> Dimensional, List<LegacySpecRow> Mechanical);

public sealed record LegacySpecImportResult(int Created, int AlreadyHadTemplate, int NoCustomer, int NoProduct, int PartNumbersFilled, int FoundFilled = 0);

/// <summary>
/// Loads the specifications written on the old Excel certificates as templates, so the first certificate of each customer and product already
/// carries chemical, dimensional and mechanical limits. Templates learned from certificates issued here are never overwritten; an Excel template loaded before the found values existed only gets them added.
/// </summary>
public sealed class LegacySpecImporter(EbtDbContext db)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public static IReadOnlyList<LegacySpec> Load()
    {
        var asm = typeof(LegacySpecImporter).Assembly;
        var name = asm.GetManifestResourceNames().Single(n => n.EndsWith("legacy-specs.json", StringComparison.Ordinal));
        using var s = asm.GetManifestResourceStream(name)!;
        return JsonSerializer.Deserialize<List<LegacySpec>>(s, Json)!;
    }

    public async Task<LegacySpecImportResult> ImportAsync(string? user, CancellationToken ct = default) => await ImportAsync(Load(), user, ct);

    public async Task<LegacySpecImportResult> ImportAsync(IEnumerable<LegacySpec> specs, string? user, CancellationToken ct = default)
    {
        var customers = await db.Customers.AsNoTracking().Select(c => new { c.Id, c.Name }).ToListAsync(ct);
        var products = await db.Products.AsNoTracking().Where(p => !p.Blocked).Select(p => new { p.Id, p.Name, p.DiameterMm, p.ThicknessMm, p.LengthMm }).ToListAsync(ct);
        var have = (await db.CertificateTemplates.AsNoTracking().Select(t => new { t.ProductId, t.CustomerId }).ToListAsync(ct)).Select(t => (t.ProductId, t.CustomerId)).ToHashSet();
        var excel = (await db.CertificateTemplates.Include(t => t.Measures).Where(t => t.LearnedFrom != null && t.LearnedFrom.EndsWith("(Excel)")).ToListAsync(ct)).ToDictionary(t => (t.ProductId, t.CustomerId));
        int created = 0, existing = 0, noCustomer = 0, noProduct = 0, parts = 0, foundFilled = 0;
        var now = DateTimeOffset.UtcNow;
        foreach (var s in specs)
        {
            var cust = customers.Where(c => string.Equals(c.Name, s.Customer, StringComparison.OrdinalIgnoreCase)).ToList();
            if (cust.Count == 0) { noCustomer++; continue; }
            var prods = products.Where(p => p.DiameterMm is { } d && Math.Abs(d - s.Diameter) < 0.011m && p.ThicknessMm is { } t && Math.Abs(t - s.Thickness) < 0.011m
                && (s.Length is null ? p.Name.Contains("ROLO", StringComparison.OrdinalIgnoreCase) : !p.Name.Contains("ROLO", StringComparison.OrdinalIgnoreCase) && p.LengthMm is { } l && Math.Abs(l - s.Length.Value) < 0.5m)).ToList();
            if (prods.Count == 0) { noProduct++; continue; }
            foreach (var c in cust)
                foreach (var p in prods)
                {
                    if (!have.Add((p.Id, c.Id)))
                    {
                        existing++;
                        if (excel.TryGetValue((p.Id, c.Id), out var old))
                        {
                            foreach (var (kind, rows) in new[] { (CertificateMeasureKind.Chemical, s.Chemical), (CertificateMeasureKind.Dimensional, s.Dimensional), (CertificateMeasureKind.Mechanical, s.Mechanical) })
                                foreach (var row in rows)
                                    if (old.Measures.FirstOrDefault(m => m.Kind == kind && m.Name == row.Name && m.Found is null) is { } m) { m.Found = FoundOf(row); foundFilled++; }
                        }
                        continue;
                    }
                    var t = new CertificateTemplate { ProductId = p.Id, CustomerId = c.Id, Title = s.Title, Finish = s.Finish, Notes = s.Notes, UpdatedBy = user ?? "importação", UpdatedAt = now, LearnedFrom = $"{s.LearnedFrom} (Excel)" };
                    AddRows(t, CertificateMeasureKind.Chemical, s.Chemical);
                    AddRows(t, CertificateMeasureKind.Dimensional, s.Dimensional);
                    AddRows(t, CertificateMeasureKind.Mechanical, s.Mechanical);
                    db.CertificateTemplates.Add(t);
                    created++;
                    if (s.CustomerPartNumber is null && s.CustomerPartDescription is null) continue;
                    var link = await db.ProductCustomers.FirstOrDefaultAsync(x => x.ProductId == p.Id && x.CustomerId == c.Id, ct);
                    if (link is null) db.ProductCustomers.Add(link = new ProductCustomer { ProductId = p.Id, CustomerId = c.Id, Active = true });
                    if (string.IsNullOrWhiteSpace(link.CustomerPartNumber) && s.CustomerPartNumber is not null) { link.CustomerPartNumber = s.CustomerPartNumber; parts++; }
                    if (string.IsNullOrWhiteSpace(link.CustomerDescription) && s.CustomerPartDescription is not null) link.CustomerDescription = s.CustomerPartDescription;
                }
        }
        await db.SaveChangesAsync(ct);
        return new(created, existing, noCustomer, noProduct, parts, foundFilled);
    }

    /// <summary>A result left blank on the Excel sheet (a test not run) is printed as "-" on the certificate, so it is kept that way instead of blocking the issue.</summary>
    private static string FoundOf(LegacySpecRow r) => string.IsNullOrWhiteSpace(r.Found) ? "-" : r.Found;

    private static void AddRows(CertificateTemplate t, CertificateMeasureKind kind, List<LegacySpecRow> rows)
    {
        foreach (var (r, n) in rows.Select((r, n) => (r, n)))
            t.Measures.Add(new CertificateTemplateMeasure { Kind = kind, Sequence = n + 1, Name = r.Name, Specified = r.Specified, Found = FoundOf(r) });
    }
}
