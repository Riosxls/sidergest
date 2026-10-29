using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Data;

public partial class EbtDbContext(DbContextOptions<EbtDbContext> options) : DbContext(options)
{
    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<CustomerAddress> CustomerAddresses => Set<CustomerAddress>();
    public DbSet<Supplier> Suppliers => Set<Supplier>();
    public DbSet<SupplierAddress> SupplierAddresses => Set<SupplierAddress>();
    public DbSet<MaterialClass> MaterialClasses => Set<MaterialClass>();
    public DbSet<MaterialGroup> MaterialGroups => Set<MaterialGroup>();
    public DbSet<MaterialSubgroup> MaterialSubgroups => Set<MaterialSubgroup>();
    public DbSet<Material> Materials => Set<Material>();
    public DbSet<WorkCenter> WorkCenters => Set<WorkCenter>();
    public DbSet<Machine> Machines => Set<Machine>();
    public DbSet<Tool> Tools => Set<Tool>();
    public DbSet<StandardOperation> StandardOperations => Set<StandardOperation>();
    public DbSet<Product> Products => Set<Product>();
    public DbSet<ProductCustomer> ProductCustomers => Set<ProductCustomer>();
    public DbSet<RoutingOperation> RoutingOperations => Set<RoutingOperation>();
    public DbSet<BomItem> BomItems => Set<BomItem>();
    public DbSet<Revision> Revisions => Set<Revision>();
    public DbSet<AppUser> Users => Set<AppUser>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Customer>(e =>
        {
            e.HasIndex(x => x.LegacyCode).IsUnique();
            e.Property(x => x.Name).HasMaxLength(120);
            e.Property(x => x.LegacyCode).HasMaxLength(10);
            e.Property(x => x.Document).HasMaxLength(14);
            e.Property(x => x.Uf).HasMaxLength(2);
            e.Property(x => x.ZipCode).HasMaxLength(8);
            e.HasOne(x => x.DefaultPaymentTerm).WithMany().HasForeignKey(x => x.DefaultPaymentTermId).OnDelete(DeleteBehavior.SetNull);
        });
        b.Entity<CustomerAddress>(e =>
        {
            e.HasIndex(x => new { x.CustomerId, x.LegacyCode }).IsUnique();
            e.Property(x => x.Document).HasMaxLength(14);
            e.Property(x => x.Uf).HasMaxLength(2);
            e.Property(x => x.CityIbgeCode).HasMaxLength(7);
            e.Property(x => x.ZipCode).HasMaxLength(8);
            e.HasOne(x => x.Customer).WithMany(x => x.Addresses).OnDelete(DeleteBehavior.Cascade);
        });
        b.Entity<Supplier>(e =>
        {
            e.HasIndex(x => x.LegacyCode).IsUnique();
            e.Property(x => x.Name).HasMaxLength(120);
        });
        b.Entity<SupplierAddress>(e =>
        {
            e.HasIndex(x => new { x.SupplierId, x.LegacyCode }).IsUnique();
            e.Property(x => x.Document).HasMaxLength(14);
            e.Property(x => x.Uf).HasMaxLength(2);
            e.HasOne(x => x.Supplier).WithMany(x => x.Addresses).OnDelete(DeleteBehavior.Cascade);
        });
        b.Entity<MaterialClass>().HasIndex(x => x.Code).IsUnique();
        b.Entity<MaterialGroup>().HasIndex(x => x.Code).IsUnique();
        b.Entity<MaterialSubgroup>().HasIndex(x => x.Code).IsUnique();
        b.Entity<Material>(e =>
        {
            e.HasIndex(x => x.Code).IsUnique();
            e.Property(x => x.Code).HasMaxLength(20);
            e.Property(x => x.Ncm).HasMaxLength(8);
            e.Property(x => x.PurchaseFactor).HasPrecision(14, 6);
            e.Property(x => x.ThicknessMm).HasPrecision(8, 3);
            e.Property(x => x.WidthMm).HasPrecision(10, 3);
            e.Property(x => x.PurchaseLot).HasPrecision(14, 3);
            e.Property(x => x.MinStock).HasPrecision(14, 3);
            e.Property(x => x.MaxStock).HasPrecision(14, 3);
            e.HasOne(x => x.Class).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Group).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Subgroup).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<WorkCenter>().HasIndex(x => x.Code).IsUnique();
        b.Entity<Machine>(e =>
        {
            e.HasIndex(x => x.Code).IsUnique();
            e.HasOne(x => x.WorkCenter).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<Tool>().HasIndex(x => x.Code).IsUnique();
        b.Entity<StandardOperation>().HasIndex(x => x.Code).IsUnique();
        b.Entity<Product>(e =>
        {
            e.HasIndex(x => x.Code).IsUnique();
            e.Property(x => x.Code).HasMaxLength(20);
            e.Property(x => x.Ncm).HasMaxLength(8);
            e.Property(x => x.DiameterMm).HasPrecision(10, 3);
            e.Property(x => x.WidthMm).HasPrecision(10, 3);
            e.Property(x => x.HeightMm).HasPrecision(10, 3);
            e.Property(x => x.ThicknessMm).HasPrecision(8, 3);
            e.Property(x => x.LengthMm).HasPrecision(12, 3);
            e.Property(x => x.NetWeightKg).HasPrecision(14, 5);
            e.Property(x => x.LossPercent).HasPrecision(5, 2);
        });
        b.Entity<ProductCustomer>(e =>
        {
            e.HasKey(x => new { x.ProductId, x.CustomerId });
            e.HasOne(x => x.Product).WithMany(x => x.Customers).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Customer).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<RoutingOperation>(e =>
        {
            e.HasIndex(x => new { x.ProductId, x.Sequence }).IsUnique();
            e.ToTable(t => t.HasCheckConstraint("ck_routing_operations_sequence", "sequence > 0 AND sequence % 10 = 0"));
            e.Property(x => x.SetupHours).HasPrecision(10, 4);
            e.Property(x => x.PiecesPerHour).HasPrecision(12, 3);
            e.Property(x => x.Operators).HasPrecision(6, 2);
            e.HasOne(x => x.Product).WithMany(x => x.Routing).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Machine).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.WorkCenter).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Tool).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.StandardOperation).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<BomItem>(e =>
        {
            e.ToTable(t => t.HasCheckConstraint("ck_bom_items_one_source", "(material_id IS NULL) <> (component_product_id IS NULL)"));
            e.Property(x => x.Quantity).HasPrecision(18, 6);
            e.Property(x => x.Factor).HasPrecision(14, 6);
            e.HasOne(x => x.RoutingOperation).WithMany(x => x.Items).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Material).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.ComponentProduct).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<Revision>(e => e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Cascade));
        b.Entity<AppUser>(e =>
        {
            e.ToTable("users");
            e.HasIndex(x => x.Username).IsUnique();
        });
        ConfigureInventory(b);
        ConfigurePurchasing(b);
        ConfigureProduction(b);
        ConfigureSales(b);
        ConfigureFiscal(b);
        ConfigureCertificates(b);
        ConfigureViability(b);
        ConfigureSteel(b);
    }

    partial void ConfigureInventory(ModelBuilder b);

    partial void ConfigurePurchasing(ModelBuilder b);

    partial void ConfigureProduction(ModelBuilder b);

    partial void ConfigureSales(ModelBuilder b);
    partial void ConfigureFiscal(ModelBuilder b);
    partial void ConfigureCertificates(ModelBuilder b);

    partial void ConfigureViability(ModelBuilder b);

    partial void ConfigureSteel(ModelBuilder b);
}
