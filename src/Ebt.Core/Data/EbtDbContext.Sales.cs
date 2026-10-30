using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Data;

public partial class EbtDbContext
{
    public const string SalesQuoteNumbers = "sales_quote_numbers";
    public const string SalesOrderNumbers = "sales_order_numbers";
    public const string DeliveryNumbers = "delivery_numbers";

    public DbSet<SalesSettings> SalesSettings => Set<SalesSettings>();
    public DbSet<PaymentTerm> PaymentTerms => Set<PaymentTerm>();
    public DbSet<PriceListEntry> PriceList => Set<PriceListEntry>();
    public DbSet<Quote> Quotes => Set<Quote>();
    public DbSet<QuoteLine> QuoteLines => Set<QuoteLine>();
    public DbSet<QuoteRequestFile> QuoteRequestFiles => Set<QuoteRequestFile>();
    public DbSet<SalesOrder> SalesOrders => Set<SalesOrder>();
    public DbSet<SalesOrderLine> SalesOrderLines => Set<SalesOrderLine>();
    public DbSet<Delivery> Deliveries => Set<Delivery>();
    public DbSet<DeliveryLine> DeliveryLines => Set<DeliveryLine>();
    public DbSet<SalesEvent> SalesEvents => Set<SalesEvent>();

    partial void ConfigureSales(ModelBuilder b)
    {
        b.HasSequence<int>(SalesQuoteNumbers);
        b.HasSequence<int>(SalesOrderNumbers);
        b.HasSequence<int>(DeliveryNumbers);

        b.Entity<SalesSettings>(e =>
        {
            e.ToTable("sales_settings");
            Pct(e.Property(x => x.MaxDiscountPercent));
            e.Property(x => x.MinimumOrderValue).HasPrecision(18, 2);
            e.ToTable(t => t.HasCheckConstraint("ck_sales_settings_values", "max_discount_percent >= 0 AND max_discount_percent <= 100 AND default_validity_days > 0 AND minimum_order_value >= 0 AND follow_up_days > 0 AND approval_validity_days > 0"));
            e.HasOne(x => x.ShippingLocation).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasData(new SalesSettings { Id = 1 });
        });
        b.Entity<PaymentTerm>(e =>
        {
            e.HasIndex(x => x.Code).IsUnique();
            e.Property(x => x.Code).HasMaxLength(10);
            e.Property(x => x.Days).HasMaxLength(60);
            e.Property(x => x.CreditLimit).HasPrecision(18, 2);
        });
        b.Entity<PriceListEntry>(e =>
        {
            e.ToTable("price_list");
            e.HasIndex(x => new { x.ProductId, x.CustomerId, x.ValidFrom }).IsUnique().AreNullsDistinct(false);
            Price(e.Property(x => x.UnitPrice));
            Pct(e.Property(x => x.IpiPercent));
            Pct(e.Property(x => x.IcmsPercent));
            e.ToTable(t => t.HasCheckConstraint("ck_price_list_values", "unit_price >= 0 AND (valid_to IS NULL OR valid_to >= valid_from)"));
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Customer).WithMany().OnDelete(DeleteBehavior.Cascade);
        });
        b.Entity<Quote>(e =>
        {
            e.HasIndex(x => new { x.Number, x.Revision }).IsUnique();
            e.HasIndex(x => x.Status);
            e.HasIndex(x => x.CustomerId);
            e.Property(x => x.Reference).HasMaxLength(40);
            e.Property(x => x.CustomerPo).HasMaxLength(40);
            e.Property(x => x.CustomerReference).HasMaxLength(40);
            e.HasOne(x => x.Customer).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Address).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.PaymentTerm).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<QuoteRequestFile>(e =>
        {
            e.HasKey(x => x.QuoteId);
            e.HasOne(x => x.Quote).WithOne().HasForeignKey<QuoteRequestFile>(x => x.QuoteId).OnDelete(DeleteBehavior.Cascade);
        });
        b.Entity<Quote>().Property(x => x.RequestFileName).HasMaxLength(255);
        b.Entity<Quote>().Property(x => x.RequestFileType).HasMaxLength(100);
        b.Entity<QuoteLine>(e =>
        {
            e.HasIndex(x => new { x.QuoteId, x.Sequence }).IsUnique();
            Qty(e.Property(x => x.Quantity));
            Price(e.Property(x => x.UnitPrice));
            Price(e.Property(x => x.ListPrice));
            Pct(e.Property(x => x.IpiPercent));
            Pct(e.Property(x => x.IcmsPercent));
            e.Property(x => x.Unit).HasMaxLength(3);
            e.ToTable(t => t.HasCheckConstraint("ck_quote_lines_values", "quantity > 0 AND unit_price >= 0"));
            e.HasOne(x => x.Quote).WithMany(x => x.Lines).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<SalesOrder>(e =>
        {
            e.HasIndex(x => x.Number).IsUnique();
            e.HasIndex(x => x.Reference).IsUnique();
            e.HasIndex(x => x.Status);
            e.HasIndex(x => x.CustomerId);
            e.HasIndex(x => x.QuoteId).IsUnique();
            e.Property(x => x.Reference).HasMaxLength(40);
            e.Property(x => x.CustomerPo).HasMaxLength(40);
            e.Property(x => x.Company).HasMaxLength(10).HasDefaultValue("EBT");
            e.Property(x => x.Salesperson).HasMaxLength(60);
            e.HasOne(x => x.Quote).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Customer).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Address).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.PaymentTerm).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<SalesOrderLine>(e =>
        {
            e.HasIndex(x => new { x.OrderId, x.Sequence }).IsUnique();
            e.HasIndex(x => x.ProductionOrderId);
            Qty(e.Property(x => x.Quantity));
            Qty(e.Property(x => x.FromStock));
            Price(e.Property(x => x.UnitPrice));
            Pct(e.Property(x => x.IpiPercent));
            Pct(e.Property(x => x.IcmsPercent));
            e.Property(x => x.Unit).HasMaxLength(3);
            e.ToTable(t => t.HasCheckConstraint("ck_sales_order_lines_values", "quantity > 0 AND unit_price >= 0 AND from_stock >= 0"));
            e.HasOne(x => x.Order).WithMany(x => x.Lines).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Reservation).WithMany().OnDelete(DeleteBehavior.SetNull);
            e.HasOne(x => x.ProductionOrder).WithMany().OnDelete(DeleteBehavior.SetNull);
            e.HasOne(x => x.FeasibilityStudy).WithMany().OnDelete(DeleteBehavior.SetNull);
            e.HasIndex(x => x.FeasibilityStudyId);
            e.Property(x => x.OutsideDiameter).HasPrecision(10, 3);
            e.Property(x => x.Thickness).HasPrecision(10, 3);
            e.Property(x => x.Length).HasPrecision(10, 1);
            e.Property(x => x.Standard).HasMaxLength(40);
            e.Property(x => x.SaleUnit).HasMaxLength(3);
            e.Property(x => x.PieceWeightKg).HasPrecision(14, 4);
            e.Property(x => x.MaterialNeedKg).HasPrecision(14, 3);
            e.Property(x => x.ToleranceDiameter).HasPrecision(8, 3);
            e.Property(x => x.ToleranceThickness).HasPrecision(8, 3);
            e.Property(x => x.ToleranceLengthPlus).HasPrecision(8, 1);
        });
        b.Entity<Delivery>(e =>
        {
            e.HasIndex(x => x.Number).IsUnique();
            e.HasIndex(x => x.Reference).IsUnique();
            e.HasIndex(x => x.OrderId);
            e.HasIndex(x => x.Status);
            e.Property(x => x.Reference).HasMaxLength(40);
            e.Property(x => x.InvoiceNumber).HasMaxLength(15);
            e.Property(x => x.VehiclePlate).HasMaxLength(10);
            e.Property(x => x.GrossWeightKg).HasPrecision(14, 3);
            e.Property(x => x.LotNumber).HasMaxLength(30);
            e.Property(x => x.InvoicedValue).HasPrecision(18, 2);
            e.HasOne(x => x.Order).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Address).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.StockDocument).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<DeliveryLine>(e =>
        {
            e.HasIndex(x => new { x.DeliveryId, x.OrderLineId }).IsUnique();
            Qty(e.Property(x => x.Quantity));
            e.ToTable(t => t.HasCheckConstraint("ck_delivery_lines_values", "quantity > 0 AND packages >= 0"));
            e.HasOne(x => x.Delivery).WithMany(x => x.Lines).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.OrderLine).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<SalesEvent>(e =>
        {
            e.HasIndex(x => new { x.Kind, x.RecordId });
            e.Property(x => x.Action).HasMaxLength(40);
            e.Property(x => x.FromStatus).HasMaxLength(30);
            e.Property(x => x.ToStatus).HasMaxLength(30);
        });
    }
}
