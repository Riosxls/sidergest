using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class FiscalInutilizations : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "fiscal_inutilizations",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    series = table.Column<int>(type: "integer", nullable: false),
                    from_number = table.Column<int>(type: "integer", nullable: false),
                    to_number = table.Column<int>(type: "integer", nullable: false),
                    reason = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    environment = table.Column<int>(type: "integer", nullable: false),
                    protocol = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    simulated = table.Column<bool>(type: "boolean", nullable: false),
                    xml = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_fiscal_inutilizations", x => x.id);
                    table.CheckConstraint("ck_fiscal_inutilizations_range", "from_number > 0 AND to_number >= from_number");
                });

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_inutilizations_series_from_number_to_number",
                table: "fiscal_inutilizations",
                columns: new[] { "series", "from_number", "to_number" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "fiscal_inutilizations");
        }
    }
}
