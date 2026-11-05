using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class PriceHistory : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "price_history",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    date = table.Column<DateOnly>(type: "date", nullable: false),
                    customer_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    diameter_mm = table.Column<decimal>(type: "numeric(12,4)", precision: 12, scale: 4, nullable: false),
                    thickness_mm = table.Column<decimal>(type: "numeric(12,4)", precision: 12, scale: 4, nullable: false),
                    length_mm = table.Column<decimal>(type: "numeric(12,4)", precision: 12, scale: 4, nullable: false),
                    unit = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    unit_price = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    weight_kg = table.Column<decimal>(type: "numeric(18,5)", precision: 18, scale: 5, nullable: false),
                    price_per_kg = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    spec = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: true),
                    import_key = table.Column<string>(type: "text", nullable: false),
                    source = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_price_history", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "ix_price_history_date",
                table: "price_history",
                column: "date");

            migrationBuilder.CreateIndex(
                name: "ix_price_history_import_key",
                table: "price_history",
                column: "import_key",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "price_history");
        }
    }
}
