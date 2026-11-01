using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Data;

public partial class EbtDbContext
{
    public DbSet<BackupSettings> BackupSettings => Set<BackupSettings>();

    partial void ConfigureBackup(ModelBuilder b)
    {
        b.Entity<BackupSettings>(e =>
        {
            e.ToTable("backup_settings");
            e.Property(x => x.Destination).HasMaxLength(260);
            e.Property(x => x.LastRunMessage).HasMaxLength(500);
            e.ToTable(t => t.HasCheckConstraint("ck_backup_settings_keep", "keep >= 1 AND keep <= 365"));
            e.HasData(new BackupSettings { Id = 1 });
        });
    }
}
