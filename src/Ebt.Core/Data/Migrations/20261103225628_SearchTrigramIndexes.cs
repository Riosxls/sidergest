using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class SearchTrigramIndexes : Migration
    {
        // Columns that /api/search and the viability list match with ILIKE '%term%'. A btree cannot serve a leading wildcard; a trigram GIN index can.
        private static readonly (string Table, string Column)[] Searched =
        [
            ("products", "code"), ("products", "name"), ("production_orders", "reference"),
            ("sales_orders", "reference"), ("sales_orders", "customer_po"), ("quotes", "reference"), ("quotes", "customer_reference"),
            ("customers", "name"), ("customers", "trade_name"), ("customers", "document"), ("customers", "legacy_code"),
            ("suppliers", "name"), ("suppliers", "trade_name"), ("suppliers", "legacy_code"),
            ("fiscal_documents", "recipient_name"), ("deliveries", "reference"),
            ("quality_certificates", "reference"), ("quality_certificates", "description"), ("quality_certificates", "customer_po"), ("quality_certificates", "invoice_number"),
            ("feasibility_studies", "reference"), ("feasibility_studies", "title")
        ];

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("CREATE EXTENSION IF NOT EXISTS pg_trgm;");
            foreach (var (table, column) in Searched)
                migrationBuilder.Sql($"CREATE INDEX IF NOT EXISTS ix_{table}_{column}_trgm ON {table} USING gin ({column} gin_trgm_ops);");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            foreach (var (table, column) in Searched)
                migrationBuilder.Sql($"DROP INDEX IF EXISTS ix_{table}_{column}_trgm;");
        }
    }
}
