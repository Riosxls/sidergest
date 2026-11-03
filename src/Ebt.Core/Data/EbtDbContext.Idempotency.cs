using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Data;

public partial class EbtDbContext
{
    public DbSet<IdempotencyKey> IdempotencyKeys => Set<IdempotencyKey>();

    partial void ConfigureIdempotency(ModelBuilder b)
    {
        b.Entity<IdempotencyKey>(e =>
        {
            e.ToTable("idempotency_keys");
            e.HasIndex(x => new { x.UserId, x.Key }).IsUnique();
            e.HasIndex(x => x.ExpiresAt);
            e.Property(x => x.Key).HasMaxLength(64);
            e.Property(x => x.Method).HasMaxLength(10);
            e.Property(x => x.Path).HasMaxLength(300);
            e.Property(x => x.BodyHash).HasMaxLength(64);
            e.Property(x => x.ResponseContentType).HasMaxLength(120);
        });
    }
}
