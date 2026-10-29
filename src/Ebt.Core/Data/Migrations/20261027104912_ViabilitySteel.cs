using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class ViabilitySteel : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateSequence<int>(
                name: "feasibility_numbers");

            migrationBuilder.AddColumn<int>(
                name: "bill_to",
                table: "sales_orders",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "origin",
                table: "sales_orders",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "salesperson",
                table: "sales_orders",
                type: "character varying(60)",
                maxLength: 60,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "condition",
                table: "sales_order_lines",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "feasibility_study_id",
                table: "sales_order_lines",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "length",
                table: "sales_order_lines",
                type: "numeric(10,1)",
                precision: 10,
                scale: 1,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "material_need_kg",
                table: "sales_order_lines",
                type: "numeric(14,3)",
                precision: 14,
                scale: 3,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "outside_diameter",
                table: "sales_order_lines",
                type: "numeric(10,3)",
                precision: 10,
                scale: 3,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "piece_weight_kg",
                table: "sales_order_lines",
                type: "numeric(14,4)",
                precision: 14,
                scale: 4,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "sale_unit",
                table: "sales_order_lines",
                type: "character varying(3)",
                maxLength: 3,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "standard",
                table: "sales_order_lines",
                type: "character varying(40)",
                maxLength: 40,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "thickness",
                table: "sales_order_lines",
                type: "numeric(10,3)",
                precision: 10,
                scale: 3,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "tolerance_diameter",
                table: "sales_order_lines",
                type: "numeric(8,3)",
                precision: 8,
                scale: 3,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "tolerance_length_plus",
                table: "sales_order_lines",
                type: "numeric(8,1)",
                precision: 8,
                scale: 1,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "tolerance_thickness",
                table: "sales_order_lines",
                type: "numeric(8,3)",
                precision: 8,
                scale: 3,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "invoiced_value",
                table: "deliveries",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "lot_number",
                table: "deliveries",
                type: "character varying(30)",
                maxLength: 30,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "feasibility_studies",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    number = table.Column<int>(type: "integer", nullable: false),
                    reference = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    quote_id = table.Column<int>(type: "integer", nullable: true),
                    customer_id = table.Column<int>(type: "integer", nullable: false),
                    product_id = table.Column<int>(type: "integer", nullable: true),
                    title = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    characteristics = table.Column<string>(type: "text", nullable: true),
                    transformations = table.Column<string>(type: "text", nullable: true),
                    finishing = table.Column<string>(type: "text", nullable: true),
                    packaging = table.Column<string>(type: "text", nullable: true),
                    monthly_consumption_kg = table.Column<decimal>(type: "numeric(14,3)", precision: 14, scale: 3, nullable: true),
                    orders_allowed = table.Column<int>(type: "integer", nullable: false),
                    status = table.Column<int>(type: "integer", nullable: false),
                    rejection_reason = table.Column<string>(type: "text", nullable: true),
                    quality_by = table.Column<string>(type: "text", nullable: true),
                    quality_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    quality_note = table.Column<string>(type: "text", nullable: true),
                    production_by = table.Column<string>(type: "text", nullable: true),
                    production_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    production_note = table.Column<string>(type: "text", nullable: true),
                    commercial_by = table.Column<string>(type: "text", nullable: true),
                    commercial_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    commercial_note = table.Column<string>(type: "text", nullable: true),
                    created_by = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_feasibility_studies", x => x.id);
                    table.CheckConstraint("ck_feasibility_values", "orders_allowed > 0 AND (monthly_consumption_kg IS NULL OR monthly_consumption_kg >= 0)");
                    table.ForeignKey(
                        name: "fk_feasibility_studies_customers_customer_id",
                        column: x => x.customer_id,
                        principalTable: "customers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_feasibility_studies_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_feasibility_studies_quotes_quote_id",
                        column: x => x.quote_id,
                        principalTable: "quotes",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "steel_lots",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    lot_code = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    supplier_id = table.Column<int>(type: "integer", nullable: false),
                    purchase_invoice = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: true),
                    received_date = table.Column<DateOnly>(type: "date", nullable: false),
                    specification = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: true),
                    thickness = table.Column<decimal>(type: "numeric(10,3)", precision: 10, scale: 3, nullable: true),
                    width = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: true),
                    weight_kg = table.Column<decimal>(type: "numeric(14,3)", precision: 14, scale: 3, nullable: false),
                    price_per_kg = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    notes = table.Column<string>(type: "text", nullable: true),
                    created_by = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_steel_lots", x => x.id);
                    table.CheckConstraint("ck_steel_lots_values", "weight_kg > 0 AND price_per_kg >= 0");
                    table.ForeignKey(
                        name: "fk_steel_lots_suppliers_supplier_id",
                        column: x => x.supplier_id,
                        principalTable: "suppliers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "slitter_jobs",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    lot_id = table.Column<int>(type: "integer", nullable: false),
                    processor_id = table.Column<int>(type: "integer", nullable: false),
                    shipment_invoice = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: true),
                    shipment_date = table.Column<DateOnly>(type: "date", nullable: false),
                    sent_kg = table.Column<decimal>(type: "numeric(14,3)", precision: 14, scale: 3, nullable: false),
                    return_invoice = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: true),
                    return_date = table.Column<DateOnly>(type: "date", nullable: true),
                    finished_kg = table.Column<decimal>(type: "numeric(14,3)", precision: 14, scale: 3, nullable: true),
                    scrap_kg = table.Column<decimal>(type: "numeric(14,3)", precision: 14, scale: 3, nullable: true),
                    service_cost = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_slitter_jobs", x => x.id);
                    table.CheckConstraint("ck_slitter_jobs_values", "sent_kg > 0 AND (finished_kg IS NULL OR finished_kg >= 0) AND (scrap_kg IS NULL OR scrap_kg >= 0) AND (service_cost IS NULL OR service_cost >= 0)");
                    table.ForeignKey(
                        name: "fk_slitter_jobs_steel_lots_lot_id",
                        column: x => x.lot_id,
                        principalTable: "steel_lots",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_slitter_jobs_suppliers_processor_id",
                        column: x => x.processor_id,
                        principalTable: "suppliers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "steel_usages",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    lot_id = table.Column<int>(type: "integer", nullable: false),
                    date = table.Column<DateOnly>(type: "date", nullable: false),
                    kg = table.Column<decimal>(type: "numeric(14,3)", precision: 14, scale: 3, nullable: false),
                    labor_cost = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    reference = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_steel_usages", x => x.id);
                    table.CheckConstraint("ck_steel_usages_values", "kg > 0 AND labor_cost >= 0");
                    table.ForeignKey(
                        name: "fk_steel_usages_steel_lots_lot_id",
                        column: x => x.lot_id,
                        principalTable: "steel_lots",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_sales_order_lines_feasibility_study_id",
                table: "sales_order_lines",
                column: "feasibility_study_id");

            migrationBuilder.CreateIndex(
                name: "ix_feasibility_studies_customer_id_product_id",
                table: "feasibility_studies",
                columns: new[] { "customer_id", "product_id" });

            migrationBuilder.CreateIndex(
                name: "ix_feasibility_studies_number",
                table: "feasibility_studies",
                column: "number",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_feasibility_studies_product_id",
                table: "feasibility_studies",
                column: "product_id");

            migrationBuilder.CreateIndex(
                name: "ix_feasibility_studies_quote_id",
                table: "feasibility_studies",
                column: "quote_id");

            migrationBuilder.CreateIndex(
                name: "ix_feasibility_studies_reference",
                table: "feasibility_studies",
                column: "reference",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_feasibility_studies_status",
                table: "feasibility_studies",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_slitter_jobs_lot_id",
                table: "slitter_jobs",
                column: "lot_id");

            migrationBuilder.CreateIndex(
                name: "ix_slitter_jobs_processor_id",
                table: "slitter_jobs",
                column: "processor_id");

            migrationBuilder.CreateIndex(
                name: "ix_steel_lots_received_date",
                table: "steel_lots",
                column: "received_date");

            migrationBuilder.CreateIndex(
                name: "ix_steel_lots_supplier_id_lot_code",
                table: "steel_lots",
                columns: new[] { "supplier_id", "lot_code" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_steel_usages_lot_id",
                table: "steel_usages",
                column: "lot_id");

            migrationBuilder.AddForeignKey(
                name: "fk_sales_order_lines_feasibility_studies_feasibility_study_id",
                table: "sales_order_lines",
                column: "feasibility_study_id",
                principalTable: "feasibility_studies",
                principalColumn: "id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "fk_sales_order_lines_feasibility_studies_feasibility_study_id",
                table: "sales_order_lines");

            migrationBuilder.DropTable(
                name: "feasibility_studies");

            migrationBuilder.DropTable(
                name: "slitter_jobs");

            migrationBuilder.DropTable(
                name: "steel_usages");

            migrationBuilder.DropTable(
                name: "steel_lots");

            migrationBuilder.DropIndex(
                name: "ix_sales_order_lines_feasibility_study_id",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "bill_to",
                table: "sales_orders");

            migrationBuilder.DropColumn(
                name: "origin",
                table: "sales_orders");

            migrationBuilder.DropColumn(
                name: "salesperson",
                table: "sales_orders");

            migrationBuilder.DropColumn(
                name: "condition",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "feasibility_study_id",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "length",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "material_need_kg",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "outside_diameter",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "piece_weight_kg",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "sale_unit",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "standard",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "thickness",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "tolerance_diameter",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "tolerance_length_plus",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "tolerance_thickness",
                table: "sales_order_lines");

            migrationBuilder.DropColumn(
                name: "invoiced_value",
                table: "deliveries");

            migrationBuilder.DropColumn(
                name: "lot_number",
                table: "deliveries");

            migrationBuilder.DropSequence(
                name: "feasibility_numbers");
        }
    }
}
