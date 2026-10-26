using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Data;

public partial class EbtDbContext
{
    public DbSet<StockLocation> StockLocations => Set<StockLocation>();
    public DbSet<StockLot> StockLots => Set<StockLot>();
    public DbSet<StockDocument> StockDocuments => Set<StockDocument>();
    public DbSet<StockMovement> StockMovements => Set<StockMovement>();
    public DbSet<StockBalance> StockBalances => Set<StockBalance>();
    public DbSet<StockReservation> StockReservations => Set<StockReservation>();
    public DbSet<StockSettings> StockSettings => Set<StockSettings>();
    public DbSet<StockClosing> StockClosings => Set<StockClosing>();
    public DbSet<AverageCost> AverageCosts => Set<AverageCost>();

    private const string OneItem = "(material_id IS NULL) <> (product_id IS NULL)";

    partial void ConfigureInventory(ModelBuilder b)
    {
        b.Entity<StockLocation>(e =>
        {
            e.HasIndex(x => x.Code).IsUnique();
            e.Property(x => x.Code).HasMaxLength(10);
            e.Property(x => x.Name).HasMaxLength(60);
        });
        b.Entity<StockLot>(e =>
        {
            e.ToTable(t => t.HasCheckConstraint("ck_stock_lots_one_item", OneItem));
            e.HasIndex(x => new { x.MaterialId, x.ProductId, x.Code }).IsUnique().AreNullsDistinct(false);
            e.Property(x => x.Code).HasMaxLength(30);
            e.HasOne(x => x.Material).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Supplier).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<StockDocument>(e =>
        {
            e.HasIndex(x => x.Date);
            e.HasIndex(x => x.Reference);
            e.HasIndex(x => x.ReversalOfId).IsUnique();
            e.Property(x => x.Reference).HasMaxLength(40);
            e.HasOne(x => x.Supplier).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Customer).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.ReversalOf).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<StockMovement>(e =>
        {
            e.ToTable(t =>
            {
                t.HasCheckConstraint("ck_stock_movements_one_item", OneItem);
                t.HasCheckConstraint("ck_stock_movements_nonzero", "quantity <> 0");
            });
            e.HasIndex(x => new { x.MaterialId, x.Date });
            e.HasIndex(x => new { x.ProductId, x.Date });
            e.HasIndex(x => x.LotId);
            e.Property(x => x.Quantity).HasPrecision(18, 4);
            e.Property(x => x.UnitCost).HasPrecision(18, 6);
            e.Property(x => x.IcmsRate).HasPrecision(5, 2);
            e.HasOne(x => x.Document).WithMany(x => x.Movements).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Material).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Location).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Lot).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne<StockReservation>().WithMany().HasForeignKey(x => x.ReservationId).OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<StockBalance>(e =>
        {
            e.ToTable(t => t.HasCheckConstraint("ck_stock_balances_one_item", OneItem));
            e.HasIndex(x => new { x.MaterialId, x.ProductId, x.LocationId, x.LotId }).IsUnique().AreNullsDistinct(false);
            e.Property(x => x.Quantity).HasPrecision(18, 4);
            e.HasOne(x => x.Material).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Location).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Lot).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<StockReservation>(e =>
        {
            e.ToTable(t =>
            {
                t.HasCheckConstraint("ck_stock_reservations_one_item", OneItem);
                t.HasCheckConstraint("ck_stock_reservations_quantity", "quantity > 0 AND consumed >= 0");
            });
            e.HasIndex(x => new { x.MaterialId, x.ProductId, x.Status });
            e.HasIndex(x => x.Reference);
            e.Property(x => x.Reference).HasMaxLength(40);
            e.Property(x => x.Quantity).HasPrecision(18, 4);
            e.Property(x => x.Consumed).HasPrecision(18, 4);
            e.HasOne(x => x.Material).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Location).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<StockSettings>(e =>
        {
            e.ToTable("stock_settings");
            e.Property(x => x.CuttingServicePerKg).HasPrecision(14, 6);
            e.Property(x => x.ScrapResalePerKg).HasPrecision(14, 6);
            e.Property(x => x.ScrapPercent).HasPrecision(6, 3);
            e.HasData(new StockSettings { Id = 1 });
        });
        b.HasSequence<long>("stock_lot_numbers");
        b.Entity<StockClosing>(e => e.HasIndex(x => x.Period).IsUnique());
        b.Entity<AverageCost>(e =>
        {
            e.ToTable(t => t.HasCheckConstraint("ck_average_costs_bucket", "(thickness_mm IS NULL) <> (material_id IS NULL)"));
            e.HasIndex(x => new { x.Period, x.ThicknessMm, x.MaterialId }).IsUnique().AreNullsDistinct(false);
            e.Property(x => x.ThicknessMm).HasPrecision(8, 3);
            e.Property(x => x.OpeningQuantity).HasPrecision(18, 4);
            e.Property(x => x.OpeningAverage).HasPrecision(18, 6);
            e.Property(x => x.PurchaseQuantity).HasPrecision(18, 4);
            e.Property(x => x.PurchaseValue).HasPrecision(18, 4);
            e.Property(x => x.ServiceQuantity).HasPrecision(18, 4);
            e.Property(x => x.ServiceValue).HasPrecision(18, 4);
            e.Property(x => x.MonthAverage).HasPrecision(18, 6);
            e.Property(x => x.Average).HasPrecision(18, 6);
            e.Property(x => x.AverageGross).HasPrecision(18, 6);
            e.HasOne(x => x.Material).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
    }
}
