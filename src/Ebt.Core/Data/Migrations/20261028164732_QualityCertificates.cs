using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class QualityCertificates : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "certificate_waived",
                table: "sales_orders",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.CreateTable(
                name: "quality_certificates",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    company = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    number = table.Column<int>(type: "integer", nullable: false),
                    year = table.Column<int>(type: "integer", nullable: false),
                    reference = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    order_id = table.Column<int>(type: "integer", nullable: false),
                    order_line_id = table.Column<int>(type: "integer", nullable: true),
                    delivery_id = table.Column<int>(type: "integer", nullable: true),
                    product_id = table.Column<int>(type: "integer", nullable: true),
                    customer_po = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    issue_date = table.Column<DateOnly>(type: "date", nullable: false),
                    invoice_number = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: true),
                    quantity = table.Column<decimal>(type: "numeric(14,3)", precision: 14, scale: 3, nullable: false),
                    unit = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    product_code = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    description = table.Column<string>(type: "text", nullable: false),
                    customer_part_number = table.Column<string>(type: "text", nullable: true),
                    customer_part_description = table.Column<string>(type: "text", nullable: true),
                    raw_material_lot = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: true),
                    hardness = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    finish = table.Column<string>(type: "text", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true),
                    approved_by = table.Column<string>(type: "text", nullable: true),
                    status = table.Column<int>(type: "integer", nullable: false),
                    cancel_reason = table.Column<string>(type: "text", nullable: true),
                    created_by = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    issued_by = table.Column<string>(type: "text", nullable: true),
                    issued_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_quality_certificates", x => x.id);
                    table.CheckConstraint("ck_quality_certificates_values", "quantity > 0");
                    table.ForeignKey(
                        name: "fk_quality_certificates_deliveries_delivery_id",
                        column: x => x.delivery_id,
                        principalTable: "deliveries",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_quality_certificates_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_quality_certificates_sales_order_lines_order_line_id",
                        column: x => x.order_line_id,
                        principalTable: "sales_order_lines",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_quality_certificates_sales_orders_order_id",
                        column: x => x.order_id,
                        principalTable: "sales_orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "certificate_measures",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    certificate_id = table.Column<int>(type: "integer", nullable: false),
                    kind = table.Column<int>(type: "integer", nullable: false),
                    sequence = table.Column<int>(type: "integer", nullable: false),
                    name = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    specified = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: true),
                    found = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_certificate_measures", x => x.id);
                    table.ForeignKey(
                        name: "fk_certificate_measures_quality_certificates_certificate_id",
                        column: x => x.certificate_id,
                        principalTable: "quality_certificates",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_certificate_measures_certificate_id_kind_sequence",
                table: "certificate_measures",
                columns: new[] { "certificate_id", "kind", "sequence" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_quality_certificates_company_number",
                table: "quality_certificates",
                columns: new[] { "company", "number" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_quality_certificates_delivery_id",
                table: "quality_certificates",
                column: "delivery_id");

            migrationBuilder.CreateIndex(
                name: "ix_quality_certificates_order_id",
                table: "quality_certificates",
                column: "order_id");

            migrationBuilder.CreateIndex(
                name: "ix_quality_certificates_order_line_id",
                table: "quality_certificates",
                column: "order_line_id");

            migrationBuilder.CreateIndex(
                name: "ix_quality_certificates_product_id",
                table: "quality_certificates",
                column: "product_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "certificate_measures");

            migrationBuilder.DropTable(
                name: "quality_certificates");

            migrationBuilder.DropColumn(
                name: "certificate_waived",
                table: "sales_orders");
        }
    }
}
