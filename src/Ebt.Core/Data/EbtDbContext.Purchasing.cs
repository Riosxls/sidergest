using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace Ebt.Core.Data;

public partial class EbtDbContext
{
    public const string RequisitionNumbers = "purchase_requisition_numbers";
    public const string QuotationNumbers = "quotation_numbers";
    public const string PurchaseOrderNumbers = "purchase_order_numbers";
    public const string GoodsReceiptNumbers = "goods_receipt_numbers";

    public DbSet<PurchasingSettings> PurchasingSettings => Set<PurchasingSettings>();
    public DbSet<PurchaseRequisition> PurchaseRequisitions => Set<PurchaseRequisition>();
    public DbSet<Quotation> Quotations => Set<Quotation>();
    public DbSet<QuotationItem> QuotationItems => Set<QuotationItem>();
    public DbSet<QuotationBid> QuotationBids => Set<QuotationBid>();
    public DbSet<PurchaseOrder> PurchaseOrders => Set<PurchaseOrder>();
    public DbSet<PurchaseOrderLine> PurchaseOrderLines => Set<PurchaseOrderLine>();
    public DbSet<GoodsReceipt> GoodsReceipts => Set<GoodsReceipt>();
    public DbSet<GoodsReceiptLine> GoodsReceiptLines => Set<GoodsReceiptLine>();
    public DbSet<PayableInstallment> PayableInstallments => Set<PayableInstallment>();
    public DbSet<SupplierMaterial> SupplierMaterials => Set<SupplierMaterial>();

    partial void ConfigurePurchasing(ModelBuilder b)
    {
        foreach (var seq in new[] { RequisitionNumbers, QuotationNumbers, PurchaseOrderNumbers, GoodsReceiptNumbers })
            b.HasSequence<int>(seq);

        b.Entity<PurchasingSettings>(e =>
        {
            e.Property(x => x.ReceivingTolerancePercent).HasPrecision(7, 4);
            e.HasData(new PurchasingSettings { Id = 1, ReceivingTolerancePercent = 5m });
            e.HasOne(x => x.ReceivingLocation).WithMany().OnDelete(DeleteBehavior.Restrict);
        });

        b.Entity<PurchaseRequisition>(e =>
        {
            e.HasIndex(x => x.Number).IsUnique();
            e.HasIndex(x => x.Status);
            e.Property(x => x.Number).HasDefaultValueSql($"nextval('{RequisitionNumbers}')");
            e.Property(x => x.Description).HasMaxLength(120);
            e.Property(x => x.Unit).HasMaxLength(3);
            e.Property(x => x.Department).HasMaxLength(10);
            Qty(e.Property(x => x.Quantity));
            Qty(e.Property(x => x.ApprovedQuantity));
            e.ToTable(t => t.HasCheckConstraint("ck_purchase_requisitions_quantity", "quantity > 0"));
            e.HasOne(x => x.Material).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.QuotationItem).WithMany(x => x.Requisitions).OnDelete(DeleteBehavior.SetNull);
            e.HasOne(x => x.PurchaseOrderLine).WithMany(x => x.Requisitions).OnDelete(DeleteBehavior.SetNull);
        });

        b.Entity<Quotation>(e =>
        {
            e.HasIndex(x => x.Number).IsUnique();
            e.Property(x => x.Number).HasDefaultValueSql($"nextval('{QuotationNumbers}')");
        });

        b.Entity<QuotationItem>(e =>
        {
            e.HasIndex(x => new { x.QuotationId, x.Item }).IsUnique();
            e.Property(x => x.Description).HasMaxLength(120);
            e.Property(x => x.Unit).HasMaxLength(3);
            Qty(e.Property(x => x.Quantity));
            e.HasOne(x => x.Quotation).WithMany(x => x.Items).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Material).WithMany().OnDelete(DeleteBehavior.Restrict);
        });

        b.Entity<QuotationBid>(e =>
        {
            e.HasIndex(x => new { x.QuotationItemId, x.SupplierId }).IsUnique();
            Price(e.Property(x => x.UnitPrice));
            Pct(e.Property(x => x.DiscountPercent));
            Pct(e.Property(x => x.IcmsPercent));
            Pct(e.Property(x => x.IpiPercent));
            e.Property(x => x.PaymentTerms).HasMaxLength(30);
            e.HasOne(x => x.QuotationItem).WithMany(x => x.Bids).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Supplier).WithMany().OnDelete(DeleteBehavior.Restrict);
        });

        b.Entity<PurchaseOrder>(e =>
        {
            e.HasIndex(x => x.Number).IsUnique();
            e.HasIndex(x => new { x.SupplierId, x.Status });
            e.Property(x => x.Number).HasDefaultValueSql($"nextval('{PurchaseOrderNumbers}')");
            e.Property(x => x.PaymentTerms).HasMaxLength(30);
            e.HasOne(x => x.Supplier).WithMany().OnDelete(DeleteBehavior.Restrict);
        });

        b.Entity<PurchaseOrderLine>(e =>
        {
            e.HasIndex(x => new { x.PurchaseOrderId, x.LineNumber }).IsUnique();
            e.HasIndex(x => x.QuotationBidId).IsUnique().HasFilter("quotation_bid_id IS NOT NULL");
            e.HasIndex(x => x.DueDate);
            e.Property(x => x.Description).HasMaxLength(120);
            e.Property(x => x.Unit).HasMaxLength(3);
            Qty(e.Property(x => x.Quantity));
            Qty(e.Property(x => x.ReceivedQuantity));
            Price(e.Property(x => x.UnitPrice));
            Pct(e.Property(x => x.DiscountPercent));
            Pct(e.Property(x => x.IcmsPercent));
            Pct(e.Property(x => x.IpiPercent));
            e.ToTable(t => t.HasCheckConstraint("ck_purchase_order_lines_quantities", "quantity > 0 AND received_quantity >= 0 AND unit_price >= 0"));
            e.HasOne(x => x.PurchaseOrder).WithMany(x => x.Lines).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Material).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.QuotationBid).WithMany().OnDelete(DeleteBehavior.SetNull);
        });

        b.Entity<GoodsReceipt>(e =>
        {
            e.HasIndex(x => x.Number).IsUnique();
            e.HasIndex(x => new { x.SupplierId, x.InvoiceNumber, x.InvoiceSeries }).IsUnique();
            e.Property(x => x.Number).HasDefaultValueSql($"nextval('{GoodsReceiptNumbers}')");
            e.Property(x => x.InvoiceNumber).HasMaxLength(15);
            e.Property(x => x.InvoiceSeries).HasMaxLength(3);
            e.Property(x => x.InvoiceTotal).HasPrecision(18, 2);
            e.Property(x => x.CalculatedTotal).HasPrecision(18, 2);
            e.HasOne(x => x.Supplier).WithMany().OnDelete(DeleteBehavior.Restrict);
        });

        b.Entity<GoodsReceiptLine>(e =>
        {
            e.Property(x => x.Unit).HasMaxLength(3);
            e.Property(x => x.LotCode).HasMaxLength(30);
            Qty(e.Property(x => x.Quantity));
            Price(e.Property(x => x.UnitPrice));
            Pct(e.Property(x => x.DiscountPercent));
            Pct(e.Property(x => x.IcmsPercent));
            Pct(e.Property(x => x.IpiPercent));
            e.Property(x => x.Total).HasPrecision(18, 2);
            e.ToTable(t => t.HasCheckConstraint("ck_goods_receipt_lines_quantity", "quantity > 0"));
            e.HasOne(x => x.GoodsReceipt).WithMany(x => x.Lines).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.PurchaseOrderLine).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Material).WithMany().OnDelete(DeleteBehavior.Restrict);
        });

        b.Entity<PayableInstallment>(e =>
        {
            e.HasIndex(x => new { x.GoodsReceiptId, x.Sequence }).IsUnique();
            e.HasIndex(x => x.DueDate);
            e.Property(x => x.Amount).HasPrecision(18, 2);
            e.HasOne(x => x.GoodsReceipt).WithMany(x => x.Installments).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<SupplierMaterial>(e =>
        {
            e.HasKey(x => new { x.SupplierId, x.MaterialId });
            e.Property(x => x.Qualification).HasMaxLength(10);
            Price(e.Property(x => x.LastUnitPrice));
            e.HasOne(x => x.Supplier).WithMany().OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Material).WithMany().OnDelete(DeleteBehavior.Cascade);
        });
    }

    private static void Qty(PropertyBuilder p) => p.HasPrecision(18, 4);
    private static void Price(PropertyBuilder p) => p.HasPrecision(18, 6);
    private static void Pct(PropertyBuilder p) => p.HasPrecision(7, 4);
}
