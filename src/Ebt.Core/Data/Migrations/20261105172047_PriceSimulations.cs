using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class PriceSimulations : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "price_simulations",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    shape = table.Column<string>(type: "character varying(12)", maxLength: 12, nullable: false),
                    diameter_mm = table.Column<decimal>(type: "numeric(12,4)", precision: 12, scale: 4, nullable: true),
                    width_mm = table.Column<decimal>(type: "numeric(12,4)", precision: 12, scale: 4, nullable: true),
                    height_mm = table.Column<decimal>(type: "numeric(12,4)", precision: 12, scale: 4, nullable: true),
                    thickness_mm = table.Column<decimal>(type: "numeric(12,4)", precision: 12, scale: 4, nullable: true),
                    length_mm = table.Column<decimal>(type: "numeric(12,4)", precision: 12, scale: 4, nullable: true),
                    spec = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: true),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: true),
                    customer_id = table.Column<int>(type: "integer", nullable: true),
                    customer_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    markup_percent = table.Column<decimal>(type: "numeric(9,4)", precision: 9, scale: 4, nullable: true),
                    cost_per_kg = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: true),
                    price_per_kg = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    price_per_piece = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: true),
                    basis = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    confidence = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    reason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    note = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    used_in_quote = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_price_simulations", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "ix_price_simulations_created_at",
                table: "price_simulations",
                column: "created_at");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "price_simulations");
        }
    }
}
