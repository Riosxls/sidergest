using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Data;

public partial class EbtDbContext
{
    public DbSet<SteelLot> SteelLots => Set<SteelLot>();
    public DbSet<SlitterJob> SlitterJobs => Set<SlitterJob>();
    public DbSet<SteelUsage> SteelUsages => Set<SteelUsage>();

    partial void ConfigureSteel(ModelBuilder b)
    {
        b.Entity<SteelLot>(e =>
        {
            e.ToTable("steel_lots");
            e.HasIndex(x => new { x.SupplierId, x.LotCode }).IsUnique();
            e.HasIndex(x => x.ReceivedDate);
            e.Property(x => x.LotCode).HasMaxLength(40);
            e.Property(x => x.PurchaseInvoice).HasMaxLength(15);
            e.Property(x => x.Specification).HasMaxLength(60);
            e.Property(x => x.Thickness).HasPrecision(10, 3);
            e.Property(x => x.Width).HasPrecision(10, 2);
            e.Property(x => x.WeightKg).HasPrecision(14, 3);
            Price(e.Property(x => x.PricePerKg));
            e.ToTable(t => t.HasCheckConstraint("ck_steel_lots_values", "weight_kg > 0 AND price_per_kg >= 0"));
            e.HasOne(x => x.Supplier).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<SlitterJob>(e =>
        {
            e.ToTable("slitter_jobs");
            e.HasIndex(x => x.LotId);
            e.Property(x => x.ShipmentInvoice).HasMaxLength(15);
            e.Property(x => x.ReturnInvoice).HasMaxLength(15);
            e.Property(x => x.SentKg).HasPrecision(14, 3);
            e.Property(x => x.FinishedKg).HasPrecision(14, 3);
            e.Property(x => x.ScrapKg).HasPrecision(14, 3);
            e.Property(x => x.ServiceCost).HasPrecision(18, 2);
            e.ToTable(t => t.HasCheckConstraint("ck_slitter_jobs_values", "sent_kg > 0 AND (finished_kg IS NULL OR finished_kg >= 0) AND (scrap_kg IS NULL OR scrap_kg >= 0) AND (service_cost IS NULL OR service_cost >= 0)"));
            e.HasOne(x => x.Lot).WithMany(x => x.SlitterJobs).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Processor).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<SteelUsage>(e =>
        {
            e.ToTable("steel_usages");
            e.HasIndex(x => x.LotId);
            e.Property(x => x.Kg).HasPrecision(14, 3);
            e.Property(x => x.LaborCost).HasPrecision(18, 2);
            e.Property(x => x.Reference).HasMaxLength(40);
            e.ToTable(t => t.HasCheckConstraint("ck_steel_usages_values", "kg > 0 AND labor_cost >= 0"));
            e.HasOne(x => x.Lot).WithMany(x => x.Usages).OnDelete(DeleteBehavior.Cascade);
        });
    }
}
