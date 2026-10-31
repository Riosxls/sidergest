using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class DataSourceMarker : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "source",
                table: "suppliers",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "source",
                table: "stock_documents",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "source",
                table: "sales_orders",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "source",
                table: "quotes",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "source",
                table: "purchase_requisitions",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "source",
                table: "purchase_orders",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "source",
                table: "products",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "source",
                table: "production_orders",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "source",
                table: "materials",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "source",
                table: "deliveries",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "source",
                table: "customers",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            // Backfill: 1 = Imported for rows that already carry a legacy marker.
            migrationBuilder.Sql("UPDATE customers SET source = 1 WHERE legacy_code IS NOT NULL;");
            migrationBuilder.Sql("UPDATE suppliers SET source = 1 WHERE legacy_code IS NOT NULL;");
            migrationBuilder.Sql("UPDATE production_orders SET source = 1 WHERE id IN (SELECT order_id FROM production_reports WHERE legacy_key IS NOT NULL);");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "source",
                table: "suppliers");

            migrationBuilder.DropColumn(
                name: "source",
                table: "stock_documents");

            migrationBuilder.DropColumn(
                name: "source",
                table: "sales_orders");

            migrationBuilder.DropColumn(
                name: "source",
                table: "quotes");

            migrationBuilder.DropColumn(
                name: "source",
                table: "purchase_requisitions");

            migrationBuilder.DropColumn(
                name: "source",
                table: "purchase_orders");

            migrationBuilder.DropColumn(
                name: "source",
                table: "products");

            migrationBuilder.DropColumn(
                name: "source",
                table: "production_orders");

            migrationBuilder.DropColumn(
                name: "source",
                table: "materials");

            migrationBuilder.DropColumn(
                name: "source",
                table: "deliveries");

            migrationBuilder.DropColumn(
                name: "source",
                table: "customers");
        }
    }
}
