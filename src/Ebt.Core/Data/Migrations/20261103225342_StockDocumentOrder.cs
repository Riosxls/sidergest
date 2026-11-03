using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class StockDocumentOrder : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "order_id",
                table: "stock_documents",
                type: "integer",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "ix_stock_documents_order_id",
                table: "stock_documents",
                column: "order_id");

            migrationBuilder.AddForeignKey(
                name: "fk_stock_documents_production_orders_order_id",
                table: "stock_documents",
                column: "order_id",
                principalTable: "production_orders",
                principalColumn: "id",
                onDelete: ReferentialAction.SetNull);

            // Legacy rows only carry the order reference (unique on production_orders): link the issue (10), return (5), receipt (3) and reversal (30) documents.
            migrationBuilder.Sql("""
                UPDATE stock_documents d SET order_id = o.id
                FROM production_orders o
                WHERE d.reference = o.reference AND d.order_id IS NULL AND d.type IN (3, 5, 10, 30);
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "fk_stock_documents_production_orders_order_id",
                table: "stock_documents");

            migrationBuilder.DropIndex(
                name: "ix_stock_documents_order_id",
                table: "stock_documents");

            migrationBuilder.DropColumn(
                name: "order_id",
                table: "stock_documents");
        }
    }
}
