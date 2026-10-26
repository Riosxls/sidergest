using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Ebt.Core.Data;

public class DesignTimeFactory : IDesignTimeDbContextFactory<EbtDbContext>
{
    public EbtDbContext CreateDbContext(string[] args)
    {
        var cs = Environment.GetEnvironmentVariable("EBT_DESIGN_DB") ?? "Host=localhost;Database=ebt_design;Username=postgres";
        return new EbtDbContext(Create(cs));
    }

    public static DbContextOptions<EbtDbContext> Create(string connectionString) =>
        new DbContextOptionsBuilder<EbtDbContext>().UseNpgsql(connectionString).UseSnakeCaseNamingConvention().Options;
}
