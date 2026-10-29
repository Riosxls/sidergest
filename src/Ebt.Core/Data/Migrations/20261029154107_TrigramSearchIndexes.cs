using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <summary>Trigram indexes so the ILIKE '%term%' searches used by list endpoints stay index-assisted as data grows.</summary>
    public partial class TrigramSearchIndexes : Migration
    {
        private static readonly (string Table, string Column)[] Targets =
        [
            ("products", "code"), ("products", "name"),
            ("materials", "code"), ("materials", "description"),
            ("customers", "name"), ("customers", "trade_name"),
            ("suppliers", "name"), ("suppliers", "trade_name"),
            ("quotes", "reference"), ("sales_orders", "reference"), ("sales_orders", "customer_po"),
            ("deliveries", "reference"), ("deliveries", "invoice_number"),
        ];

        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // pg_trgm is a trusted extension on PostgreSQL 13+, so the database owner can create it.
            migrationBuilder.Sql("CREATE EXTENSION IF NOT EXISTS pg_trgm;");
            foreach (var (table, column) in Targets)
                migrationBuilder.Sql($"CREATE INDEX IF NOT EXISTS ix_{table}_{column}_trgm ON {table} USING gin ({column} gin_trgm_ops);");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            foreach (var (table, column) in Targets)
                migrationBuilder.Sql($"DROP INDEX IF EXISTS ix_{table}_{column}_trgm;");
        }
    }
}
