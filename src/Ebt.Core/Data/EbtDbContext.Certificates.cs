using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Data;

public partial class EbtDbContext
{
    public DbSet<QualityCertificate> QualityCertificates => Set<QualityCertificate>();
    public DbSet<CertificateMeasure> CertificateMeasures => Set<CertificateMeasure>();

    partial void ConfigureCertificates(ModelBuilder b)
    {
        b.Entity<QualityCertificate>(e =>
        {
            e.ToTable("quality_certificates");
            e.HasIndex(x => new { x.Company, x.Number }).IsUnique();
            e.HasIndex(x => x.OrderId);
            e.HasIndex(x => x.DeliveryId);
            e.Property(x => x.Company).HasMaxLength(10);
            e.Property(x => x.Reference).HasMaxLength(20);
            e.Property(x => x.InvoiceNumber).HasMaxLength(15);
            e.Property(x => x.Unit).HasMaxLength(3);
            e.Property(x => x.CustomerPo).HasMaxLength(40);
            e.Property(x => x.ProductCode).HasMaxLength(40);
            e.Property(x => x.RawMaterialLot).HasMaxLength(60);
            e.Property(x => x.Hardness).HasMaxLength(40);
            e.Property(x => x.Quantity).HasPrecision(14, 3);
            e.ToTable(t => t.HasCheckConstraint("ck_quality_certificates_values", "quantity > 0"));
            e.HasOne(x => x.Order).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.OrderLine).WithMany().OnDelete(DeleteBehavior.SetNull);
            e.HasOne(x => x.Delivery).WithMany().OnDelete(DeleteBehavior.SetNull);
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.SetNull);
        });
        b.Entity<CertificateMeasure>(e =>
        {
            e.ToTable("certificate_measures");
            e.HasIndex(x => new { x.CertificateId, x.Kind, x.Sequence }).IsUnique();
            e.Property(x => x.Name).HasMaxLength(40);
            e.Property(x => x.Specified).HasMaxLength(60);
            e.Property(x => x.Found).HasMaxLength(60);
            e.HasOne(x => x.Certificate).WithMany(x => x.Measures).OnDelete(DeleteBehavior.Cascade);
        });
    }
}
