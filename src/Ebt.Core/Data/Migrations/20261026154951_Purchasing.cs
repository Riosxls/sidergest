using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class Purchasing : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateSequence<int>(
                name: "goods_receipt_numbers");

            migrationBuilder.CreateSequence<int>(
                name: "purchase_order_numbers");

            migrationBuilder.CreateSequence<int>(
                name: "purchase_requisition_numbers");

            migrationBuilder.CreateSequence<int>(
                name: "quotation_numbers");

            migrationBuilder.CreateTable(
                name: "goods_receipts",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    number = table.Column<int>(type: "integer", nullable: false, defaultValueSql: "nextval('goods_receipt_numbers')"),
                    supplier_id = table.Column<int>(type: "integer", nullable: false),
                    invoice_number = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: false),
                    invoice_series = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    invoice_date = table.Column<DateOnly>(type: "date", nullable: false),
                    received_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    received_by = table.Column<string>(type: "text", nullable: true),
                    invoice_total = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: true),
                    calculated_total = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    divergence_justification = table.Column<string>(type: "text", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_goods_receipts", x => x.id);
                    table.ForeignKey(
                        name: "fk_goods_receipts_suppliers_supplier_id",
                        column: x => x.supplier_id,
                        principalTable: "suppliers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "purchase_orders",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    number = table.Column<int>(type: "integer", nullable: false, defaultValueSql: "nextval('purchase_order_numbers')"),
                    supplier_id = table.Column<int>(type: "integer", nullable: false),
                    status = table.Column<int>(type: "integer", nullable: false),
                    payment_terms = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true),
                    issued_by = table.Column<string>(type: "text", nullable: true),
                    issued_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    closed_by = table.Column<string>(type: "text", nullable: true),
                    closed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    close_reason = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_purchase_orders", x => x.id);
                    table.ForeignKey(
                        name: "fk_purchase_orders_suppliers_supplier_id",
                        column: x => x.supplier_id,
                        principalTable: "suppliers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "purchasing_settings",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    receiving_tolerance_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    allow_early_receipt = table.Column<bool>(type: "boolean", nullable: false),
                    early_receipt_grace_days = table.Column<int>(type: "integer", nullable: false),
                    receiving_location_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_purchasing_settings", x => x.id);
                    table.ForeignKey(
                        name: "fk_purchasing_settings_stock_locations_receiving_location_id",
                        column: x => x.receiving_location_id,
                        principalTable: "stock_locations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "quotations",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    number = table.Column<int>(type: "integer", nullable: false, defaultValueSql: "nextval('quotation_numbers')"),
                    status = table.Column<int>(type: "integer", nullable: false),
                    notes = table.Column<string>(type: "text", nullable: true),
                    created_by = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_quotations", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "supplier_materials",
                columns: table => new
                {
                    supplier_id = table.Column<int>(type: "integer", nullable: false),
                    material_id = table.Column<int>(type: "integer", nullable: false),
                    qualification = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: true),
                    qualified_at = table.Column<DateOnly>(type: "date", nullable: true),
                    last_unit_price = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: true),
                    last_purchase_date = table.Column<DateOnly>(type: "date", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_supplier_materials", x => new { x.supplier_id, x.material_id });
                    table.ForeignKey(
                        name: "fk_supplier_materials_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_supplier_materials_suppliers_supplier_id",
                        column: x => x.supplier_id,
                        principalTable: "suppliers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "payable_installments",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    goods_receipt_id = table.Column<int>(type: "integer", nullable: false),
                    sequence = table.Column<int>(type: "integer", nullable: false),
                    due_date = table.Column<DateOnly>(type: "date", nullable: false),
                    amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_payable_installments", x => x.id);
                    table.ForeignKey(
                        name: "fk_payable_installments_goods_receipts_goods_receipt_id",
                        column: x => x.goods_receipt_id,
                        principalTable: "goods_receipts",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "quotation_items",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    quotation_id = table.Column<int>(type: "integer", nullable: false),
                    item = table.Column<int>(type: "integer", nullable: false),
                    material_id = table.Column<int>(type: "integer", nullable: true),
                    description = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    unit = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_quotation_items", x => x.id);
                    table.ForeignKey(
                        name: "fk_quotation_items_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_quotation_items_quotations_quotation_id",
                        column: x => x.quotation_id,
                        principalTable: "quotations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "quotation_bids",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    quotation_item_id = table.Column<int>(type: "integer", nullable: false),
                    supplier_id = table.Column<int>(type: "integer", nullable: false),
                    unit_price = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: true),
                    discount_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    icms_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    ipi_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    lead_time_days = table.Column<int>(type: "integer", nullable: true),
                    payment_terms = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true),
                    status = table.Column<int>(type: "integer", nullable: false),
                    responded_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_quotation_bids", x => x.id);
                    table.ForeignKey(
                        name: "fk_quotation_bids_quotation_items_quotation_item_id",
                        column: x => x.quotation_item_id,
                        principalTable: "quotation_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_quotation_bids_suppliers_supplier_id",
                        column: x => x.supplier_id,
                        principalTable: "suppliers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "purchase_order_lines",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    purchase_order_id = table.Column<int>(type: "integer", nullable: false),
                    line_number = table.Column<int>(type: "integer", nullable: false),
                    material_id = table.Column<int>(type: "integer", nullable: true),
                    description = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    unit = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    unit_price = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    discount_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    icms_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    ipi_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    due_date = table.Column<DateOnly>(type: "date", nullable: false),
                    received_quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    closed = table.Column<bool>(type: "boolean", nullable: false),
                    quotation_bid_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_purchase_order_lines", x => x.id);
                    table.CheckConstraint("ck_purchase_order_lines_quantities", "quantity > 0 AND received_quantity >= 0 AND unit_price >= 0");
                    table.ForeignKey(
                        name: "fk_purchase_order_lines_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_purchase_order_lines_purchase_orders_purchase_order_id",
                        column: x => x.purchase_order_id,
                        principalTable: "purchase_orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_purchase_order_lines_quotation_bids_quotation_bid_id",
                        column: x => x.quotation_bid_id,
                        principalTable: "quotation_bids",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "goods_receipt_lines",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    goods_receipt_id = table.Column<int>(type: "integer", nullable: false),
                    purchase_order_line_id = table.Column<int>(type: "integer", nullable: false),
                    material_id = table.Column<int>(type: "integer", nullable: true),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    unit = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    unit_price = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    discount_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    icms_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    ipi_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    total = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    lot_code = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_goods_receipt_lines", x => x.id);
                    table.CheckConstraint("ck_goods_receipt_lines_quantity", "quantity > 0");
                    table.ForeignKey(
                        name: "fk_goods_receipt_lines_goods_receipts_goods_receipt_id",
                        column: x => x.goods_receipt_id,
                        principalTable: "goods_receipts",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_goods_receipt_lines_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_goods_receipt_lines_purchase_order_lines_purchase_order_lin",
                        column: x => x.purchase_order_line_id,
                        principalTable: "purchase_order_lines",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "purchase_requisitions",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    number = table.Column<int>(type: "integer", nullable: false, defaultValueSql: "nextval('purchase_requisition_numbers')"),
                    material_id = table.Column<int>(type: "integer", nullable: true),
                    description = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    unit = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    approved_quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: true),
                    department = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: true),
                    needed_by = table.Column<DateOnly>(type: "date", nullable: true),
                    application = table.Column<string>(type: "text", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true),
                    status = table.Column<int>(type: "integer", nullable: false),
                    requested_by = table.Column<string>(type: "text", nullable: true),
                    requested_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    decided_by = table.Column<string>(type: "text", nullable: true),
                    decided_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    decision_note = table.Column<string>(type: "text", nullable: true),
                    quotation_item_id = table.Column<int>(type: "integer", nullable: true),
                    purchase_order_line_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_purchase_requisitions", x => x.id);
                    table.CheckConstraint("ck_purchase_requisitions_quantity", "quantity > 0");
                    table.ForeignKey(
                        name: "fk_purchase_requisitions_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_purchase_requisitions_purchase_order_lines_purchase_order_l",
                        column: x => x.purchase_order_line_id,
                        principalTable: "purchase_order_lines",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_purchase_requisitions_quotation_items_quotation_item_id",
                        column: x => x.quotation_item_id,
                        principalTable: "quotation_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.InsertData(
                table: "purchasing_settings",
                columns: new[] { "id", "allow_early_receipt", "early_receipt_grace_days", "receiving_location_id", "receiving_tolerance_percent" },
                values: new object[] { 1, false, 0, null, 5m });

            migrationBuilder.CreateIndex(
                name: "ix_goods_receipt_lines_goods_receipt_id",
                table: "goods_receipt_lines",
                column: "goods_receipt_id");

            migrationBuilder.CreateIndex(
                name: "ix_goods_receipt_lines_material_id",
                table: "goods_receipt_lines",
                column: "material_id");

            migrationBuilder.CreateIndex(
                name: "ix_goods_receipt_lines_purchase_order_line_id",
                table: "goods_receipt_lines",
                column: "purchase_order_line_id");

            migrationBuilder.CreateIndex(
                name: "ix_goods_receipts_number",
                table: "goods_receipts",
                column: "number",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_goods_receipts_supplier_id_invoice_number_invoice_series",
                table: "goods_receipts",
                columns: new[] { "supplier_id", "invoice_number", "invoice_series" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_payable_installments_due_date",
                table: "payable_installments",
                column: "due_date");

            migrationBuilder.CreateIndex(
                name: "ix_payable_installments_goods_receipt_id_sequence",
                table: "payable_installments",
                columns: new[] { "goods_receipt_id", "sequence" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_purchase_order_lines_due_date",
                table: "purchase_order_lines",
                column: "due_date");

            migrationBuilder.CreateIndex(
                name: "ix_purchase_order_lines_material_id",
                table: "purchase_order_lines",
                column: "material_id");

            migrationBuilder.CreateIndex(
                name: "ix_purchase_order_lines_purchase_order_id_line_number",
                table: "purchase_order_lines",
                columns: new[] { "purchase_order_id", "line_number" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_purchase_order_lines_quotation_bid_id",
                table: "purchase_order_lines",
                column: "quotation_bid_id",
                unique: true,
                filter: "quotation_bid_id IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "ix_purchase_orders_number",
                table: "purchase_orders",
                column: "number",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_purchase_orders_supplier_id_status",
                table: "purchase_orders",
                columns: new[] { "supplier_id", "status" });

            migrationBuilder.CreateIndex(
                name: "ix_purchase_requisitions_material_id",
                table: "purchase_requisitions",
                column: "material_id");

            migrationBuilder.CreateIndex(
                name: "ix_purchase_requisitions_number",
                table: "purchase_requisitions",
                column: "number",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_purchase_requisitions_purchase_order_line_id",
                table: "purchase_requisitions",
                column: "purchase_order_line_id");

            migrationBuilder.CreateIndex(
                name: "ix_purchase_requisitions_quotation_item_id",
                table: "purchase_requisitions",
                column: "quotation_item_id");

            migrationBuilder.CreateIndex(
                name: "ix_purchase_requisitions_status",
                table: "purchase_requisitions",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_purchasing_settings_receiving_location_id",
                table: "purchasing_settings",
                column: "receiving_location_id");

            migrationBuilder.CreateIndex(
                name: "ix_quotation_bids_quotation_item_id_supplier_id",
                table: "quotation_bids",
                columns: new[] { "quotation_item_id", "supplier_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_quotation_bids_supplier_id",
                table: "quotation_bids",
                column: "supplier_id");

            migrationBuilder.CreateIndex(
                name: "ix_quotation_items_material_id",
                table: "quotation_items",
                column: "material_id");

            migrationBuilder.CreateIndex(
                name: "ix_quotation_items_quotation_id_item",
                table: "quotation_items",
                columns: new[] { "quotation_id", "item" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_quotations_number",
                table: "quotations",
                column: "number",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_supplier_materials_material_id",
                table: "supplier_materials",
                column: "material_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "goods_receipt_lines");

            migrationBuilder.DropTable(
                name: "payable_installments");

            migrationBuilder.DropTable(
                name: "purchase_requisitions");

            migrationBuilder.DropTable(
                name: "purchasing_settings");

            migrationBuilder.DropTable(
                name: "supplier_materials");

            migrationBuilder.DropTable(
                name: "goods_receipts");

            migrationBuilder.DropTable(
                name: "purchase_order_lines");

            migrationBuilder.DropTable(
                name: "purchase_orders");

            migrationBuilder.DropTable(
                name: "quotation_bids");

            migrationBuilder.DropTable(
                name: "quotation_items");

            migrationBuilder.DropTable(
                name: "quotations");

            migrationBuilder.DropSequence(
                name: "goods_receipt_numbers");

            migrationBuilder.DropSequence(
                name: "purchase_order_numbers");

            migrationBuilder.DropSequence(
                name: "purchase_requisition_numbers");

            migrationBuilder.DropSequence(
                name: "quotation_numbers");
        }
    }
}
