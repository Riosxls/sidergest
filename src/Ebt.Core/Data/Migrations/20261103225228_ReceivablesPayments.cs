using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class ReceivablesPayments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "receivable_payments",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    installment_id = table.Column<int>(type: "integer", nullable: false),
                    paid_on = table.Column<DateOnly>(type: "date", nullable: false),
                    amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    method = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    notes = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<string>(type: "text", nullable: true),
                    reversed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    reversed_by = table.Column<string>(type: "text", nullable: true),
                    reverse_reason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_receivable_payments", x => x.id);
                    table.CheckConstraint("ck_receivable_payments_amount", "amount > 0");
                    table.ForeignKey(
                        name: "fk_receivable_payments_fiscal_installments_installment_id",
                        column: x => x.installment_id,
                        principalTable: "fiscal_installments",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_receivable_payments_installment_id",
                table: "receivable_payments",
                column: "installment_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "receivable_payments");
        }
    }
}
