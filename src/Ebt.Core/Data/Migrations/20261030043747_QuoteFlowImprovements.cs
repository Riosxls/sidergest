using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class QuoteFlowImprovements : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_sales_settings_values",
                table: "sales_settings");

            migrationBuilder.AddColumn<int>(
                name: "approval_validity_days",
                table: "sales_settings",
                type: "integer",
                nullable: false,
                defaultValue: 30);

            migrationBuilder.AddColumn<int>(
                name: "follow_up_days",
                table: "sales_settings",
                type: "integer",
                nullable: false,
                defaultValue: 7);

            migrationBuilder.AddColumn<bool>(
                name: "off_list_needs_approval",
                table: "sales_settings",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<int>(
                name: "lost_reason",
                table: "quotes",
                type: "integer",
                nullable: true);

            migrationBuilder.UpdateData(
                table: "sales_settings",
                keyColumn: "id",
                keyValue: 1,
                columns: new[] { "approval_validity_days", "follow_up_days", "off_list_needs_approval" },
                values: new object[] { 30, 7, false });

            migrationBuilder.AddCheckConstraint(
                name: "ck_sales_settings_values",
                table: "sales_settings",
                sql: "max_discount_percent >= 0 AND max_discount_percent <= 100 AND default_validity_days > 0 AND minimum_order_value >= 0 AND follow_up_days > 0 AND approval_validity_days > 0");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_sales_settings_values",
                table: "sales_settings");

            migrationBuilder.DropColumn(
                name: "approval_validity_days",
                table: "sales_settings");

            migrationBuilder.DropColumn(
                name: "follow_up_days",
                table: "sales_settings");

            migrationBuilder.DropColumn(
                name: "off_list_needs_approval",
                table: "sales_settings");

            migrationBuilder.DropColumn(
                name: "lost_reason",
                table: "quotes");

            migrationBuilder.AddCheckConstraint(
                name: "ck_sales_settings_values",
                table: "sales_settings",
                sql: "max_discount_percent >= 0 AND max_discount_percent <= 100 AND default_validity_days > 0 AND minimum_order_value >= 0");
        }
    }
}
