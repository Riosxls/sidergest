using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class CustomerDefaultPaymentTerm : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "default_payment_term_id",
                table: "customers",
                type: "integer",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "ix_customers_default_payment_term_id",
                table: "customers",
                column: "default_payment_term_id");

            migrationBuilder.AddForeignKey(
                name: "fk_customers_payment_terms_default_payment_term_id",
                table: "customers",
                column: "default_payment_term_id",
                principalTable: "payment_terms",
                principalColumn: "id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "fk_customers_payment_terms_default_payment_term_id",
                table: "customers");

            migrationBuilder.DropIndex(
                name: "ix_customers_default_payment_term_id",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "default_payment_term_id",
                table: "customers");
        }
    }
}
