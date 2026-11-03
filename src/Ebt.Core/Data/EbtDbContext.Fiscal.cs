using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Data;

public partial class EbtDbContext
{
    public DbSet<FiscalSettings> FiscalSettings => Set<FiscalSettings>();
    public DbSet<Cfop> Cfops => Set<Cfop>();
    public DbSet<TaxRule> TaxRules => Set<TaxRule>();
    public DbSet<MonthlyPrice> MonthlyPrices => Set<MonthlyPrice>();
    public DbSet<FiscalDocument> FiscalDocuments => Set<FiscalDocument>();
    public DbSet<FiscalDocumentLine> FiscalDocumentLines => Set<FiscalDocumentLine>();
    public DbSet<FiscalInstallment> FiscalInstallments => Set<FiscalInstallment>();
    public DbSet<ReceivablePayment> ReceivablePayments => Set<ReceivablePayment>();
    public DbSet<FiscalInutilization> FiscalInutilizations => Set<FiscalInutilization>();
    public DbSet<FiscalEvent> FiscalEvents => Set<FiscalEvent>();
    public DbSet<FiscalCarrier> FiscalCarriers => Set<FiscalCarrier>();

    partial void ConfigureFiscal(ModelBuilder b)
    {
        b.Entity<FiscalSettings>(e =>
        {
            e.ToTable("fiscal_settings");
            e.Property(x => x.Cnpj).HasMaxLength(14);
            e.Property(x => x.StateRegistration).HasMaxLength(14);
            e.Property(x => x.Uf).HasMaxLength(2);
            e.Property(x => x.CityIbgeCode).HasMaxLength(7);
            e.ToTable(t => t.HasCheckConstraint("ck_fiscal_settings_values", "series > 0 AND next_number > 0 AND cancel_window_hours >= 0 AND tax_regime BETWEEN 1 AND 3"));
            e.HasData(new FiscalSettings { Id = 1 });
        });
        b.Entity<Cfop>(e =>
        {
            e.ToTable("cfops");
            e.HasKey(x => x.Code);
            e.Property(x => x.Code).HasMaxLength(4);
            e.Property(x => x.IcmsCst).HasMaxLength(3);
            e.Property(x => x.IpiCst).HasMaxLength(2);
            e.Property(x => x.PisCst).HasMaxLength(2);
            e.Property(x => x.CofinsCst).HasMaxLength(2);
            e.Property(x => x.IpiFramingCode).HasMaxLength(3);
            Pct(e.Property(x => x.DefaultPisPercent));
            Pct(e.Property(x => x.DefaultCofinsPercent));
            e.HasData(
                new Cfop { Code = "5101", Description = "Venda de produção do estabelecimento", Kind = FiscalKind.Sale, Taxed = true, IcmsCst = "00", IpiCst = "50", PisCst = "01", CofinsCst = "01", DefaultPisPercent = 0.65m, DefaultCofinsPercent = 3m, GeneratesInstallments = true },
                new Cfop { Code = "5124", Description = "Industrialização efetuada para outra empresa", Kind = FiscalKind.Sale, Taxed = true, IcmsCst = "00", IpiCst = "50", PisCst = "01", CofinsCst = "01", DefaultPisPercent = 0.65m, DefaultCofinsPercent = 3m, GeneratesInstallments = true },
                new Cfop { Code = "5901", Description = "Remessa para industrialização por encomenda", Kind = FiscalKind.OutsideShipment, Taxed = false, IcmsCst = "50", IpiCst = "55", PisCst = "09", CofinsCst = "09", IpiFramingCode = "108",
                    LegalText = "Suspensão do IPI conforme art. 43 do Decreto 7.212/10. Suspensão do ICMS conforme art. 402 do RICMS/SP. Remessa para industrialização, retorno previsto." },
                new Cfop { Code = "5902", Description = "Retorno de mercadoria utilizada na industrialização por encomenda", Kind = FiscalKind.Sale, Taxed = false, IcmsCst = "50", IpiCst = "55", PisCst = "09", CofinsCst = "09", IpiFramingCode = "108",
                    LegalText = "Retorno de mercadoria recebida para industrialização." },
                new Cfop { Code = "1202", Description = "Devolução de venda de produção do estabelecimento", Kind = FiscalKind.Return, Taxed = true, IcmsCst = "00", IpiCst = "00", PisCst = "01", CofinsCst = "01", DefaultPisPercent = 0.65m, DefaultCofinsPercent = 3m },
                new Cfop { Code = "2202", Description = "Devolução de venda de produção do estabelecimento", Kind = FiscalKind.Return, Taxed = true, IcmsCst = "00", IpiCst = "00", PisCst = "01", CofinsCst = "01", DefaultPisPercent = 0.65m, DefaultCofinsPercent = 3m },
                new Cfop { Code = "5920", Description = "Remessa de vasilhame ou sacaria", Kind = FiscalKind.Sale, Taxed = false, IcmsCst = "41", IpiCst = "53", PisCst = "08", CofinsCst = "08", IpiFramingCode = "999" },
                new Cfop { Code = "5921", Description = "Retorno de vasilhame ou sacaria", Kind = FiscalKind.Sale, Taxed = false, IcmsCst = "41", IpiCst = "53", PisCst = "08", CofinsCst = "08", IpiFramingCode = "999" });
        });
        b.Entity<TaxRule>(e =>
        {
            e.ToTable("tax_rules");
            e.HasIndex(x => new { x.ProductId, x.CustomerId, x.CfopCode }).IsUnique().AreNullsDistinct(false);
            e.Property(x => x.CfopCode).HasMaxLength(4);
            e.Property(x => x.IcmsCst).HasMaxLength(3);
            e.Property(x => x.IpiCst).HasMaxLength(2);
            Pct(e.Property(x => x.IcmsPercent));
            Pct(e.Property(x => x.IcmsBaseReductionPercent));
            Pct(e.Property(x => x.IpiPercent));
            Pct(e.Property(x => x.PisPercent));
            Pct(e.Property(x => x.CofinsPercent));
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Customer).WithMany().OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Cfop).WithMany().HasForeignKey(x => x.CfopCode).OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<MonthlyPrice>(e =>
        {
            e.ToTable("monthly_prices");
            e.HasIndex(x => new { x.ProductId, x.CustomerId, x.CfopCode, x.Year, x.Month }).IsUnique();
            e.Property(x => x.CfopCode).HasMaxLength(4);
            Price(e.Property(x => x.UnitPrice));
            e.ToTable(t => t.HasCheckConstraint("ck_monthly_prices_values", "unit_price > 0 AND month BETWEEN 1 AND 12 AND year BETWEEN 2000 AND 2100"));
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Customer).WithMany().OnDelete(DeleteBehavior.Cascade);
        });
        b.Entity<FiscalDocument>(e =>
        {
            e.HasIndex(x => new { x.Series, x.Number }).IsUnique();
            e.HasIndex(x => x.AccessKey).IsUnique();
            // Two live NFs (Pending or Authorized) for one delivery are impossible; Rejected and Cancelled ones do not count.
            e.HasIndex(x => x.DeliveryId).IsUnique().HasDatabaseName("ux_fiscal_documents_live_delivery").HasFilter("delivery_id IS NOT NULL AND status IN (0, 2)");
            e.HasIndex(x => x.OutsideShipmentId);
            e.HasIndex(x => x.ReferencedDocumentId);
            e.Property(x => x.Warnings).HasMaxLength(500);
            e.Property(x => x.ReferencedAccessKey).HasMaxLength(44);
            e.HasOne(x => x.ReferencedDocument).WithMany().HasForeignKey(x => x.ReferencedDocumentId).OnDelete(DeleteBehavior.NoAction); // NoAction: checked at the end of the statement, so a data reset can delete both ends at once
            e.HasOne(x => x.StockDocument).WithMany().HasForeignKey(x => x.StockDocumentId).OnDelete(DeleteBehavior.Restrict);
            e.Property(x => x.CfopCode).HasMaxLength(4);
            e.Property(x => x.AccessKey).HasMaxLength(44);
            e.Property(x => x.Protocol).HasMaxLength(20);
            e.Property(x => x.CancelProtocol).HasMaxLength(20);
            e.Property(x => x.StatusMessage).HasMaxLength(500);
            e.Property(x => x.RecipientName).HasMaxLength(120);
            e.Property(x => x.RecipientDocument).HasMaxLength(14);
            e.Property(x => x.RecipientUf).HasMaxLength(2);
            foreach (var p in new[] { e.Property(x => x.ProductsTotal), e.Property(x => x.FreightTotal), e.Property(x => x.IcmsBase), e.Property(x => x.IcmsTotal), e.Property(x => x.IpiTotal), e.Property(x => x.PisTotal), e.Property(x => x.CofinsTotal), e.Property(x => x.InvoiceTotal) })
                p.HasPrecision(18, 2);
            e.HasOne(x => x.Delivery).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.OutsideShipment).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Customer).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Supplier).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
        b.Entity<FiscalDocumentLine>(e =>
        {
            e.HasIndex(x => new { x.DocumentId, x.Sequence }).IsUnique();
            e.Property(x => x.Code).HasMaxLength(60);
            e.Property(x => x.Ncm).HasMaxLength(8);
            e.Property(x => x.Unit).HasMaxLength(6);
            Qty(e.Property(x => x.Quantity));
            Price(e.Property(x => x.UnitPrice));
            foreach (var p in new[] { e.Property(x => x.Total), e.Property(x => x.Freight), e.Property(x => x.IcmsBase), e.Property(x => x.IcmsValue), e.Property(x => x.IpiBase), e.Property(x => x.IpiValue), e.Property(x => x.PisValue), e.Property(x => x.CofinsValue) })
                p.HasPrecision(18, 2);
            foreach (var p in new[] { e.Property(x => x.IcmsPercent), e.Property(x => x.IcmsBaseReductionPercent), e.Property(x => x.IpiPercent), e.Property(x => x.PisPercent), e.Property(x => x.CofinsPercent) })
                Pct(p);
            e.HasOne(x => x.Document).WithMany(x => x.Lines).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.ProductionOrder).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasIndex(x => x.ReferencedLineId);
            e.HasOne(x => x.ReferencedLine).WithMany().HasForeignKey(x => x.ReferencedLineId).OnDelete(DeleteBehavior.NoAction);
        });
        b.Entity<FiscalEvent>(e =>
        {
            e.ToTable("fiscal_events", t => t.HasCheckConstraint("ck_fiscal_events_sequence", "sequence BETWEEN 1 AND 20"));
            e.HasIndex(x => new { x.DocumentId, x.EventType, x.Sequence }).IsUnique();
            e.Property(x => x.EventType).HasMaxLength(6);
            e.Property(x => x.Text).HasMaxLength(1000);
            e.Property(x => x.Protocol).HasMaxLength(20);
            e.HasOne(x => x.Document).WithMany(x => x.Events).HasForeignKey(x => x.DocumentId).OnDelete(DeleteBehavior.Cascade);
        });
        b.Entity<FiscalCarrier>(e =>
        {
            e.ToTable("fiscal_carriers");
            e.HasIndex(x => x.Name).IsUnique();
            e.Property(x => x.Name).HasMaxLength(60);
            e.Property(x => x.Document).HasMaxLength(14);
            e.Property(x => x.StateRegistration).HasMaxLength(14);
            e.Property(x => x.Address).HasMaxLength(60);
            e.Property(x => x.City).HasMaxLength(60);
            e.Property(x => x.Uf).HasMaxLength(2);
            e.Property(x => x.VehicleUf).HasMaxLength(2);
        });
        b.Entity<FiscalInutilization>(e =>
        {
            e.ToTable("fiscal_inutilizations", t => t.HasCheckConstraint("ck_fiscal_inutilizations_range", "from_number > 0 AND to_number >= from_number"));
            e.HasIndex(x => new { x.Series, x.FromNumber, x.ToNumber });
            e.Property(x => x.Reason).HasMaxLength(255);
            e.Property(x => x.Protocol).HasMaxLength(20);
        });
        b.Entity<ReceivablePayment>(e =>
        {
            e.ToTable("receivable_payments", t => t.HasCheckConstraint("ck_receivable_payments_amount", "amount > 0"));
            e.Property(x => x.Amount).HasPrecision(18, 2);
            e.Property(x => x.Method).HasMaxLength(40);
            e.Property(x => x.Notes).HasMaxLength(500);
            e.Property(x => x.ReverseReason).HasMaxLength(500);
            e.HasIndex(x => x.InstallmentId);
            e.HasOne(x => x.Installment).WithMany(x => x.Payments).HasForeignKey(x => x.InstallmentId).OnDelete(DeleteBehavior.Cascade);
        });
        b.Entity<FiscalInstallment>(e =>
        {
            e.HasIndex(x => new { x.DocumentId, x.Sequence }).IsUnique();
            e.Property(x => x.Amount).HasPrecision(18, 2);
            e.HasOne(x => x.Document).WithMany(x => x.Installments).OnDelete(DeleteBehavior.Cascade);
        });
    }
}
