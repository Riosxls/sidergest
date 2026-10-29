using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class SecurityHardening : Migration
    {
        private static readonly (string Table, string Column)[] TrigramTargets =
        [
            ("products", "code"), ("products", "name"),
            ("materials", "code"), ("materials", "description"),
            ("customers", "name"), ("customers", "trade_name"),
            ("suppliers", "name"), ("suppliers", "trade_name"),
            ("quotes", "reference"), ("sales_orders", "reference"), ("sales_orders", "customer_po"),
            ("deliveries", "reference"), ("deliveries", "invoice_number"),
        ];

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Trigram indexes keep the ILIKE '%term%' list searches index-assisted (pg_trgm is trusted on PostgreSQL 13+).
            migrationBuilder.Sql("CREATE EXTENSION IF NOT EXISTS pg_trgm;");
            foreach (var (table, column) in TrigramTargets)
                migrationBuilder.Sql($"CREATE INDEX IF NOT EXISTS ix_{table}_{column}_trgm ON {table} USING gin ({column} gin_trgm_ops);");

            migrationBuilder.AddColumn<int>(
                name: "failed_logins",
                table: "users",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "locked_until",
                table: "users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "token_version",
                table: "users",
                type: "integer",
                nullable: false,
                defaultValue: 0);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            foreach (var (table, column) in TrigramTargets)
                migrationBuilder.Sql($"DROP INDEX IF EXISTS ix_{table}_{column}_trgm;");

            migrationBuilder.DropColumn(
                name: "failed_logins",
                table: "users");

            migrationBuilder.DropColumn(
                name: "locked_until",
                table: "users");

            migrationBuilder.DropColumn(
                name: "token_version",
                table: "users");
        }
    }
}
