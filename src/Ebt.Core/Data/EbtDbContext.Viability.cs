using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Data;

public partial class EbtDbContext
{
    public const string FeasibilityNumbers = "feasibility_numbers";

    public DbSet<FeasibilityStudy> FeasibilityStudies => Set<FeasibilityStudy>();

    partial void ConfigureViability(ModelBuilder b)
    {
        b.HasSequence<int>(FeasibilityNumbers);
        b.Entity<FeasibilityStudy>(e =>
        {
            e.ToTable("feasibility_studies");
            e.HasIndex(x => x.Number).IsUnique();
            e.HasIndex(x => x.Reference).IsUnique();
            e.HasIndex(x => x.Status);
            e.HasIndex(x => x.QuoteId);
            e.HasIndex(x => new { x.CustomerId, x.ProductId });
            e.Property(x => x.Reference).HasMaxLength(40);
            e.Property(x => x.Title).HasMaxLength(120);
            e.Property(x => x.MonthlyConsumptionKg).HasPrecision(14, 3);
            e.ToTable(t => t.HasCheckConstraint("ck_feasibility_values", "orders_allowed > 0 AND (monthly_consumption_kg IS NULL OR monthly_consumption_kg >= 0)"));
            e.HasOne(x => x.Quote).WithMany().OnDelete(DeleteBehavior.SetNull);
            e.HasOne(x => x.Customer).WithMany().OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Product).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
    }
}
