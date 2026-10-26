using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class Inventory : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateSequence(
                name: "stock_lot_numbers");

            migrationBuilder.CreateTable(
                name: "average_costs",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    period = table.Column<int>(type: "integer", nullable: false),
                    thickness_mm = table.Column<decimal>(type: "numeric(8,3)", precision: 8, scale: 3, nullable: true),
                    material_id = table.Column<int>(type: "integer", nullable: true),
                    opening_quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    opening_average = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    purchase_quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    purchase_value = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    service_quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    service_value = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    month_average = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    average = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    average_gross = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    imported = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_average_costs", x => x.id);
                    table.CheckConstraint("ck_average_costs_bucket", "(thickness_mm IS NULL) <> (material_id IS NULL)");
                    table.ForeignKey(
                        name: "fk_average_costs_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "stock_closings",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    period = table.Column<int>(type: "integer", nullable: false),
                    closed_by = table.Column<string>(type: "text", nullable: false),
                    closed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_stock_closings", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "stock_documents",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    type = table.Column<int>(type: "integer", nullable: false),
                    date = table.Column<DateOnly>(type: "date", nullable: false),
                    reference = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    supplier_id = table.Column<int>(type: "integer", nullable: true),
                    customer_id = table.Column<int>(type: "integer", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true),
                    reversal_of_id = table.Column<int>(type: "integer", nullable: true),
                    reversed = table.Column<bool>(type: "boolean", nullable: false),
                    created_by = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_stock_documents", x => x.id);
                    table.ForeignKey(
                        name: "fk_stock_documents_customers_customer_id",
                        column: x => x.customer_id,
                        principalTable: "customers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_documents_stock_documents_reversal_of_id",
                        column: x => x.reversal_of_id,
                        principalTable: "stock_documents",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_documents_suppliers_supplier_id",
                        column: x => x.supplier_id,
                        principalTable: "suppliers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "stock_locations",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    name = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    kind = table.Column<int>(type: "integer", nullable: false),
                    active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_stock_locations", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "stock_lots",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    material_id = table.Column<int>(type: "integer", nullable: true),
                    product_id = table.Column<int>(type: "integer", nullable: true),
                    code = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    status = table.Column<int>(type: "integer", nullable: false),
                    supplier_id = table.Column<int>(type: "integer", nullable: true),
                    invoice_number = table.Column<string>(type: "text", nullable: true),
                    heat_number = table.Column<string>(type: "text", nullable: true),
                    received_on = table.Column<DateOnly>(type: "date", nullable: false),
                    inspection_note = table.Column<string>(type: "text", nullable: true),
                    inspected_by = table.Column<string>(type: "text", nullable: true),
                    inspected_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_stock_lots", x => x.id);
                    table.CheckConstraint("ck_stock_lots_one_item", "(material_id IS NULL) <> (product_id IS NULL)");
                    table.ForeignKey(
                        name: "fk_stock_lots_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_lots_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_lots_suppliers_supplier_id",
                        column: x => x.supplier_id,
                        principalTable: "suppliers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "stock_settings",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    allow_negative_stock = table.Column<bool>(type: "boolean", nullable: false),
                    deduct_icms_from_average = table.Column<bool>(type: "boolean", nullable: false),
                    cutting_service_per_kg = table.Column<decimal>(type: "numeric(14,6)", precision: 14, scale: 6, nullable: false),
                    scrap_resale_per_kg = table.Column<decimal>(type: "numeric(14,6)", precision: 14, scale: 6, nullable: false),
                    scrap_percent = table.Column<decimal>(type: "numeric(6,3)", precision: 6, scale: 3, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_stock_settings", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "stock_reservations",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    material_id = table.Column<int>(type: "integer", nullable: true),
                    product_id = table.Column<int>(type: "integer", nullable: true),
                    location_id = table.Column<int>(type: "integer", nullable: true),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    consumed = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    status = table.Column<int>(type: "integer", nullable: false),
                    reference = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    needed_on = table.Column<DateOnly>(type: "date", nullable: true),
                    created_by = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_stock_reservations", x => x.id);
                    table.CheckConstraint("ck_stock_reservations_one_item", "(material_id IS NULL) <> (product_id IS NULL)");
                    table.CheckConstraint("ck_stock_reservations_quantity", "quantity > 0 AND consumed >= 0");
                    table.ForeignKey(
                        name: "fk_stock_reservations_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_reservations_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_reservations_stock_locations_location_id",
                        column: x => x.location_id,
                        principalTable: "stock_locations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "stock_balances",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    material_id = table.Column<int>(type: "integer", nullable: true),
                    product_id = table.Column<int>(type: "integer", nullable: true),
                    location_id = table.Column<int>(type: "integer", nullable: false),
                    lot_id = table.Column<int>(type: "integer", nullable: true),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_stock_balances", x => x.id);
                    table.CheckConstraint("ck_stock_balances_one_item", "(material_id IS NULL) <> (product_id IS NULL)");
                    table.ForeignKey(
                        name: "fk_stock_balances_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_balances_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_balances_stock_locations_location_id",
                        column: x => x.location_id,
                        principalTable: "stock_locations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_balances_stock_lots_lot_id",
                        column: x => x.lot_id,
                        principalTable: "stock_lots",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "stock_movements",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    document_id = table.Column<int>(type: "integer", nullable: false),
                    type = table.Column<int>(type: "integer", nullable: false),
                    date = table.Column<DateOnly>(type: "date", nullable: false),
                    material_id = table.Column<int>(type: "integer", nullable: true),
                    product_id = table.Column<int>(type: "integer", nullable: true),
                    location_id = table.Column<int>(type: "integer", nullable: false),
                    lot_id = table.Column<int>(type: "integer", nullable: true),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    unit_cost = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    icms_rate = table.Column<decimal>(type: "numeric(5,2)", precision: 5, scale: 2, nullable: false),
                    reservation_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_stock_movements", x => x.id);
                    table.CheckConstraint("ck_stock_movements_nonzero", "quantity <> 0");
                    table.CheckConstraint("ck_stock_movements_one_item", "(material_id IS NULL) <> (product_id IS NULL)");
                    table.ForeignKey(
                        name: "fk_stock_movements_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_movements_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_movements_stock_documents_document_id",
                        column: x => x.document_id,
                        principalTable: "stock_documents",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_movements_stock_locations_location_id",
                        column: x => x.location_id,
                        principalTable: "stock_locations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_movements_stock_lots_lot_id",
                        column: x => x.lot_id,
                        principalTable: "stock_lots",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_stock_movements_stock_reservations_reservation_id",
                        column: x => x.reservation_id,
                        principalTable: "stock_reservations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.InsertData(
                table: "stock_settings",
                columns: new[] { "id", "allow_negative_stock", "cutting_service_per_kg", "deduct_icms_from_average", "scrap_percent", "scrap_resale_per_kg" },
                values: new object[] { 1, false, 0m, true, 0m, 0m });

            migrationBuilder.CreateIndex(
                name: "ix_average_costs_material_id",
                table: "average_costs",
                column: "material_id");

            migrationBuilder.CreateIndex(
                name: "ix_average_costs_period_thickness_mm_material_id",
                table: "average_costs",
                columns: new[] { "period", "thickness_mm", "material_id" },
                unique: true)
                .Annotation("Npgsql:NullsDistinct", false);

            migrationBuilder.CreateIndex(
                name: "ix_stock_balances_location_id",
                table: "stock_balances",
                column: "location_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_balances_lot_id",
                table: "stock_balances",
                column: "lot_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_balances_material_id_product_id_location_id_lot_id",
                table: "stock_balances",
                columns: new[] { "material_id", "product_id", "location_id", "lot_id" },
                unique: true)
                .Annotation("Npgsql:NullsDistinct", false);

            migrationBuilder.CreateIndex(
                name: "ix_stock_balances_product_id",
                table: "stock_balances",
                column: "product_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_closings_period",
                table: "stock_closings",
                column: "period",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_stock_documents_customer_id",
                table: "stock_documents",
                column: "customer_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_documents_date",
                table: "stock_documents",
                column: "date");

            migrationBuilder.CreateIndex(
                name: "ix_stock_documents_reference",
                table: "stock_documents",
                column: "reference");

            migrationBuilder.CreateIndex(
                name: "ix_stock_documents_reversal_of_id",
                table: "stock_documents",
                column: "reversal_of_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_stock_documents_supplier_id",
                table: "stock_documents",
                column: "supplier_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_locations_code",
                table: "stock_locations",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_stock_lots_material_id_product_id_code",
                table: "stock_lots",
                columns: new[] { "material_id", "product_id", "code" },
                unique: true)
                .Annotation("Npgsql:NullsDistinct", false);

            migrationBuilder.CreateIndex(
                name: "ix_stock_lots_product_id",
                table: "stock_lots",
                column: "product_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_lots_supplier_id",
                table: "stock_lots",
                column: "supplier_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_movements_document_id",
                table: "stock_movements",
                column: "document_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_movements_location_id",
                table: "stock_movements",
                column: "location_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_movements_lot_id",
                table: "stock_movements",
                column: "lot_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_movements_material_id_date",
                table: "stock_movements",
                columns: new[] { "material_id", "date" });

            migrationBuilder.CreateIndex(
                name: "ix_stock_movements_product_id_date",
                table: "stock_movements",
                columns: new[] { "product_id", "date" });

            migrationBuilder.CreateIndex(
                name: "ix_stock_movements_reservation_id",
                table: "stock_movements",
                column: "reservation_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_reservations_location_id",
                table: "stock_reservations",
                column: "location_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_reservations_material_id_product_id_status",
                table: "stock_reservations",
                columns: new[] { "material_id", "product_id", "status" });

            migrationBuilder.CreateIndex(
                name: "ix_stock_reservations_product_id",
                table: "stock_reservations",
                column: "product_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_reservations_reference",
                table: "stock_reservations",
                column: "reference");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "average_costs");

            migrationBuilder.DropTable(
                name: "stock_balances");

            migrationBuilder.DropTable(
                name: "stock_closings");

            migrationBuilder.DropTable(
                name: "stock_movements");

            migrationBuilder.DropTable(
                name: "stock_settings");

            migrationBuilder.DropTable(
                name: "stock_documents");

            migrationBuilder.DropTable(
                name: "stock_lots");

            migrationBuilder.DropTable(
                name: "stock_reservations");

            migrationBuilder.DropTable(
                name: "stock_locations");

            migrationBuilder.DropSequence(
                name: "stock_lot_numbers");
        }
    }
}
