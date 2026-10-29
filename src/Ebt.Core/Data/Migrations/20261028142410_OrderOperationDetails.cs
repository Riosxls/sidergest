using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class OrderOperationDetails : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "primary_tube",
                table: "production_orders",
                type: "character varying(120)",
                maxLength: 120,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "measure_end",
                table: "production_order_operations",
                type: "character varying(60)",
                maxLength: 60,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "measure_start",
                table: "production_order_operations",
                type: "character varying(60)",
                maxLength: 60,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "tolerance",
                table: "production_order_operations",
                type: "character varying(60)",
                maxLength: 60,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "primary_tube",
                table: "production_orders");

            migrationBuilder.DropColumn(
                name: "measure_end",
                table: "production_order_operations");

            migrationBuilder.DropColumn(
                name: "measure_start",
                table: "production_order_operations");

            migrationBuilder.DropColumn(
                name: "tolerance",
                table: "production_order_operations");
        }
    }
}
