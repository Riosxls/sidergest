using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Data;

public partial class EbtDbContext
{
    public const string ProductionOrderNumbers = "production_order_numbers";
    public const string InternalOrderNumbers = "internal_order_numbers";

    public DbSet<ProductionSettings> ProductionSettings => Set<ProductionSettings>();
    public DbSet<Shift> Shifts => Set<Shift>();
    public DbSet<Employee> Employees => Set<Employee>();
    public DbSet<ProductionOccurrence> ProductionOccurrences => Set<ProductionOccurrence>();
    public DbSet<Holiday> Holidays => Set<Holiday>();
    public DbSet<ProductionOrder> ProductionOrders => Set<ProductionOrder>();
    public DbSet<ProductionOrderOperation> ProductionOrderOperations => Set<ProductionOrderOperation>();
    public DbSet<ProductionOrderMaterial> ProductionOrderMaterials => Set<ProductionOrderMaterial>();
    public DbSet<OverrunRelease> OverrunReleases => Set<OverrunRelease>();
    public DbSet<OutsideShipment> OutsideShipments => Set<OutsideShipment>();
    public DbSet<ProductionReport> ProductionReports => Set<ProductionReport>();

    partial void ConfigureProduction(ModelBuilder b)
    {
        b.HasSequence<int>(ProductionOrderNumbers);
        b.HasSequence<int>(InternalOrderNumbers);

        b.Entity<ProductionSettings>(e =>
        {
            e.ToTable("production_settings");
            e.Property(x => x.OverrunTolerancePercent).HasPrecision(7, 4);
            e.Property(x => x.HoursPerDay).HasPrecision(5, 2);
            e.ToTable(t => t.HasCheckConstraint("ck_production_settings_hours", "hours_per_day > 0 AND hours_per_day <= 24"));
            e.HasOne(x => x.IssueLocation).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.ReceiptLocation).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasData(new ProductionSettings { Id = 1 });
        });
        b.Entity<Shift>(e =>
        {
            e.HasIndex(x => x.Code).IsUnique();
            e.Property(x => x.Code).HasMaxLength(10);
            e.Property(x => x.Hours).HasPrecision(5, 2);
        });
        b.Entity<Employee>(e =>
        {
            e.HasIndex(x => x.Code).IsUnique();
            e.Property(x => x.Code).HasMaxLength(10);
            e.Property(x => x.Name).HasMaxLength(80);
            e.HasOne(x => x.WorkCenter).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Shift).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<ProductionOccurrence>(e =>
        {
            e.HasIndex(x => x.Code).IsUnique();
            e.Property(x => x.Code).HasMaxLength(10);
        });
        b.Entity<Holiday>(e => e.HasIndex(x => x.Date).IsUnique());

        b.Entity<ProductionOrder>(e =>
        {
            e.HasIndex(x => new { x.Kind, x.Number }).IsUnique();
            e.HasIndex(x => x.Reference).IsUnique();
            e.HasIndex(x => x.Status);
            e.HasIndex(x => x.DueDate);
            e.HasIndex(x => x.ProductId);
            e.Property(x => x.Reference).HasMaxLength(40);
            e.Property(x => x.PrimaryTube).HasMaxLength(120);
            Qty(e.Property(x => x.Quantity));
            e.Property(x => x.MaterialCost).HasPrecision(18, 4);
            e.Property(x => x.ServiceCost).HasPrecision(18, 4);
            e.Property(x => x.UnitCost).HasPrecision(18, 6);
            e.ToTable(t => t.HasCheckConstraint("ck_production_orders_quantity", "quantity > 0"));
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Customer).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.ParentOrder).WithMany().HasForeignKey(x => x.ParentOrderId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.PreviousOrder).WithMany().HasForeignKey(x => x.PreviousOrderId).OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<ProductionOrderOperation>(e =>
        {
            e.HasIndex(x => new { x.OrderId, x.Sequence }).IsUnique();
            e.Property(x => x.SetupHours).HasPrecision(10, 4);
            e.Property(x => x.PiecesPerHour).HasPrecision(12, 3);
            e.Property(x => x.Operators).HasPrecision(6, 2);
            e.Property(x => x.PlannedHours).HasPrecision(12, 4);
            e.Property(x => x.Tolerance).HasMaxLength(60);
            e.Property(x => x.MeasureStart).HasMaxLength(60);
            e.Property(x => x.MeasureEnd).HasMaxLength(60);
            Qty(e.Property(x => x.OverrunReleased));
            e.ToTable(t => t.HasCheckConstraint("ck_production_order_operations_external", "NOT external OR supplier_id IS NOT NULL"));
            e.HasOne(x => x.Order).WithMany(x => x.Operations).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Machine).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.WorkCenter).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Supplier).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<ProductionOrderMaterial>(e =>
        {
            e.ToTable(t =>
            {
                t.HasCheckConstraint("ck_production_order_materials_one_item", "(material_id IS NULL) <> (component_product_id IS NULL)");
                t.HasCheckConstraint("ck_production_order_materials_quantity", "required_quantity >= 0");
            });
            e.HasIndex(x => x.OrderId);
            e.HasIndex(x => x.ReservationId).IsUnique();
            e.Property(x => x.QuantityPerUnit).HasPrecision(18, 6);
            Qty(e.Property(x => x.RequiredQuantity));
            e.Property(x => x.Unit).HasMaxLength(3);
            e.HasOne(x => x.Order).WithMany(x => x.Materials).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Material).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.ComponentProduct).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Reservation).WithMany().OnDelete(DeleteBehavior.SetNull);
        });
        b.Entity<OverrunRelease>(e =>
        {
            Qty(e.Property(x => x.Quantity));
            e.ToTable(t => t.HasCheckConstraint("ck_overrun_releases_quantity", "quantity > 0"));
            e.HasOne(x => x.Operation).WithMany().OnDelete(DeleteBehavior.Cascade);
        });
        b.Entity<OutsideShipment>(e =>
        {
            e.HasIndex(x => x.OperationId);
            Qty(e.Property(x => x.Quantity));
            Qty(e.Property(x => x.ReturnedQuantity));
            Qty(e.Property(x => x.ScrapQuantity));
            e.Property(x => x.ServiceValue).HasPrecision(18, 4);
            e.Property(x => x.InvoiceNumber).HasMaxLength(15);
            e.ToTable(t => t.HasCheckConstraint("ck_outside_shipments_quantities", "quantity > 0 AND returned_quantity >= 0 AND scrap_quantity >= 0 AND returned_quantity + scrap_quantity <= quantity"));
            e.HasOne(x => x.Operation).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Supplier).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<ProductionReport>(e =>
        {
            e.HasIndex(x => new { x.OrderId, x.OperationId });
            e.HasIndex(x => x.Date);
            e.HasIndex(x => x.LegacyKey).IsUnique();
            e.Property(x => x.LegacyKey).HasMaxLength(30);
            Qty(e.Property(x => x.GoodQuantity));
            Qty(e.Property(x => x.ScrapQuantity));
            e.Property(x => x.Hours).HasPrecision(10, 4);
            e.Property(x => x.SetupHours).HasPrecision(10, 4);
            e.Property(x => x.Operators).HasPrecision(6, 2);
            e.Property(x => x.DowntimeHours).HasPrecision(10, 4);
            e.Property(x => x.WeightKg).HasPrecision(18, 4);
            e.ToTable(t => t.HasCheckConstraint("ck_production_reports_quantities", "good_quantity >= 0 AND scrap_quantity >= 0"));
            e.HasOne(x => x.Order).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Operation).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Shift).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Employee).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Machine).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.DowntimeOccurrence).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.ScrapOccurrence).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.OutsideShipment).WithMany().OnDelete(DeleteBehavior.Cascade);
        });
    }
}
