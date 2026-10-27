using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class Sales : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateSequence<int>(
                name: "delivery_numbers");

            migrationBuilder.CreateSequence<int>(
                name: "sales_order_numbers");

            migrationBuilder.CreateSequence<int>(
                name: "sales_quote_numbers");

            migrationBuilder.CreateTable(
                name: "payment_terms",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    name = table.Column<string>(type: "text", nullable: false),
                    days = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    credit_limit = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: true),
                    active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_payment_terms", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "price_list",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    product_id = table.Column<int>(type: "integer", nullable: false),
                    customer_id = table.Column<int>(type: "integer", nullable: true),
                    unit_price = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    ipi_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: true),
                    icms_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: true),
                    valid_from = table.Column<DateOnly>(type: "date", nullable: false),
                    valid_to = table.Column<DateOnly>(type: "date", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_price_list", x => x.id);
                    table.CheckConstraint("ck_price_list_values", "unit_price >= 0 AND (valid_to IS NULL OR valid_to >= valid_from)");
                    table.ForeignKey(
                        name: "fk_price_list_customers_customer_id",
                        column: x => x.customer_id,
                        principalTable: "customers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_price_list_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "sales_events",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    kind = table.Column<int>(type: "integer", nullable: false),
                    record_id = table.Column<int>(type: "integer", nullable: false),
                    action = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    from_status = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                    to_status = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                    note = table.Column<string>(type: "text", nullable: true),
                    user = table.Column<string>(type: "text", nullable: true),
                    at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_sales_events", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "sales_settings",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    max_discount_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    default_validity_days = table.Column<int>(type: "integer", nullable: false),
                    minimum_order_value = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    shipping_location_id = table.Column<int>(type: "integer", nullable: true),
                    default_conditions = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_sales_settings", x => x.id);
                    table.CheckConstraint("ck_sales_settings_values", "max_discount_percent >= 0 AND max_discount_percent <= 100 AND default_validity_days > 0 AND minimum_order_value >= 0");
                    table.ForeignKey(
                        name: "fk_sales_settings_stock_locations_shipping_location_id",
                        column: x => x.shipping_location_id,
                        principalTable: "stock_locations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "quotes",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    number = table.Column<int>(type: "integer", nullable: false),
                    revision = table.Column<int>(type: "integer", nullable: false),
                    reference = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    customer_id = table.Column<int>(type: "integer", nullable: false),
                    address_id = table.Column<int>(type: "integer", nullable: true),
                    contact_name = table.Column<string>(type: "text", nullable: true),
                    contact_email = table.Column<string>(type: "text", nullable: true),
                    customer_reference = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    payment_term_id = table.Column<int>(type: "integer", nullable: true),
                    freight = table.Column<int>(type: "integer", nullable: false),
                    validity_days = table.Column<int>(type: "integer", nullable: false),
                    valid_until = table.Column<DateOnly>(type: "date", nullable: true),
                    conditions = table.Column<string>(type: "text", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true),
                    status = table.Column<int>(type: "integer", nullable: false),
                    needs_approval = table.Column<bool>(type: "boolean", nullable: false),
                    approved_by = table.Column<string>(type: "text", nullable: true),
                    approved_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    sent_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    sent_to = table.Column<string>(type: "text", nullable: true),
                    decided_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    decision_by = table.Column<string>(type: "text", nullable: true),
                    decision_note = table.Column<string>(type: "text", nullable: true),
                    customer_po = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    sales_order_id = table.Column<int>(type: "integer", nullable: true),
                    created_by = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_quotes", x => x.id);
                    table.ForeignKey(
                        name: "fk_quotes_customer_addresses_address_id",
                        column: x => x.address_id,
                        principalTable: "customer_addresses",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_quotes_customers_customer_id",
                        column: x => x.customer_id,
                        principalTable: "customers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_quotes_payment_terms_payment_term_id",
                        column: x => x.payment_term_id,
                        principalTable: "payment_terms",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "quote_lines",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    quote_id = table.Column<int>(type: "integer", nullable: false),
                    sequence = table.Column<int>(type: "integer", nullable: false),
                    product_id = table.Column<int>(type: "integer", nullable: false),
                    customer_part_number = table.Column<string>(type: "text", nullable: true),
                    description = table.Column<string>(type: "text", nullable: false),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    unit = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    unit_price = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    list_price = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: true),
                    ipi_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    icms_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    lead_time_days = table.Column<int>(type: "integer", nullable: true),
                    delivery_date = table.Column<DateOnly>(type: "date", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_quote_lines", x => x.id);
                    table.CheckConstraint("ck_quote_lines_values", "quantity > 0 AND unit_price >= 0");
                    table.ForeignKey(
                        name: "fk_quote_lines_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_quote_lines_quotes_quote_id",
                        column: x => x.quote_id,
                        principalTable: "quotes",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "sales_orders",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    number = table.Column<int>(type: "integer", nullable: false),
                    reference = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    quote_id = table.Column<int>(type: "integer", nullable: true),
                    customer_id = table.Column<int>(type: "integer", nullable: false),
                    address_id = table.Column<int>(type: "integer", nullable: false),
                    customer_po = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    payment_term_id = table.Column<int>(type: "integer", nullable: true),
                    freight = table.Column<int>(type: "integer", nullable: false),
                    status = table.Column<int>(type: "integer", nullable: false),
                    notes = table.Column<string>(type: "text", nullable: true),
                    status_reason = table.Column<string>(type: "text", nullable: true),
                    created_by = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    released_by = table.Column<string>(type: "text", nullable: true),
                    released_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_sales_orders", x => x.id);
                    table.ForeignKey(
                        name: "fk_sales_orders_customer_addresses_address_id",
                        column: x => x.address_id,
                        principalTable: "customer_addresses",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_sales_orders_customers_customer_id",
                        column: x => x.customer_id,
                        principalTable: "customers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_sales_orders_payment_terms_payment_term_id",
                        column: x => x.payment_term_id,
                        principalTable: "payment_terms",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_sales_orders_quotes_quote_id",
                        column: x => x.quote_id,
                        principalTable: "quotes",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "deliveries",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    number = table.Column<int>(type: "integer", nullable: false),
                    reference = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    order_id = table.Column<int>(type: "integer", nullable: false),
                    address_id = table.Column<int>(type: "integer", nullable: false),
                    planned_date = table.Column<DateOnly>(type: "date", nullable: false),
                    status = table.Column<int>(type: "integer", nullable: false),
                    carrier = table.Column<string>(type: "text", nullable: true),
                    vehicle_plate = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: true),
                    invoice_number = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: true),
                    packages = table.Column<int>(type: "integer", nullable: false),
                    gross_weight_kg = table.Column<decimal>(type: "numeric(14,3)", precision: 14, scale: 3, nullable: true),
                    stock_document_id = table.Column<int>(type: "integer", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true),
                    created_by = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    shipped_by = table.Column<string>(type: "text", nullable: true),
                    shipped_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    delivered_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    received_by = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_deliveries", x => x.id);
                    table.ForeignKey(
                        name: "fk_deliveries_customer_addresses_address_id",
                        column: x => x.address_id,
                        principalTable: "customer_addresses",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_deliveries_sales_orders_order_id",
                        column: x => x.order_id,
                        principalTable: "sales_orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_deliveries_stock_documents_stock_document_id",
                        column: x => x.stock_document_id,
                        principalTable: "stock_documents",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "sales_order_lines",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    order_id = table.Column<int>(type: "integer", nullable: false),
                    sequence = table.Column<int>(type: "integer", nullable: false),
                    product_id = table.Column<int>(type: "integer", nullable: false),
                    customer_part_number = table.Column<string>(type: "text", nullable: true),
                    description = table.Column<string>(type: "text", nullable: false),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    unit = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    unit_price = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    ipi_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    icms_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    due_date = table.Column<DateOnly>(type: "date", nullable: false),
                    from_stock = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    reservation_id = table.Column<int>(type: "integer", nullable: true),
                    production_order_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_sales_order_lines", x => x.id);
                    table.CheckConstraint("ck_sales_order_lines_values", "quantity > 0 AND unit_price >= 0 AND from_stock >= 0");
                    table.ForeignKey(
                        name: "fk_sales_order_lines_production_orders_production_order_id",
                        column: x => x.production_order_id,
                        principalTable: "production_orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_sales_order_lines_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_sales_order_lines_sales_orders_order_id",
                        column: x => x.order_id,
                        principalTable: "sales_orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_sales_order_lines_stock_reservations_reservation_id",
                        column: x => x.reservation_id,
                        principalTable: "stock_reservations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "delivery_lines",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    delivery_id = table.Column<int>(type: "integer", nullable: false),
                    order_line_id = table.Column<int>(type: "integer", nullable: false),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    packages = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_delivery_lines", x => x.id);
                    table.CheckConstraint("ck_delivery_lines_values", "quantity > 0 AND packages >= 0");
                    table.ForeignKey(
                        name: "fk_delivery_lines_deliveries_delivery_id",
                        column: x => x.delivery_id,
                        principalTable: "deliveries",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_delivery_lines_sales_order_lines_order_line_id",
                        column: x => x.order_line_id,
                        principalTable: "sales_order_lines",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.InsertData(
                table: "sales_settings",
                columns: new[] { "id", "default_conditions", "default_validity_days", "max_discount_percent", "minimum_order_value", "shipping_location_id" },
                values: new object[] { 1, null, 15, 5m, 0m, null });

            migrationBuilder.CreateIndex(
                name: "ix_deliveries_address_id",
                table: "deliveries",
                column: "address_id");

            migrationBuilder.CreateIndex(
                name: "ix_deliveries_number",
                table: "deliveries",
                column: "number",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_deliveries_order_id",
                table: "deliveries",
                column: "order_id");

            migrationBuilder.CreateIndex(
                name: "ix_deliveries_reference",
                table: "deliveries",
                column: "reference",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_deliveries_status",
                table: "deliveries",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_deliveries_stock_document_id",
                table: "deliveries",
                column: "stock_document_id");

            migrationBuilder.CreateIndex(
                name: "ix_delivery_lines_delivery_id_order_line_id",
                table: "delivery_lines",
                columns: new[] { "delivery_id", "order_line_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_delivery_lines_order_line_id",
                table: "delivery_lines",
                column: "order_line_id");

            migrationBuilder.CreateIndex(
                name: "ix_payment_terms_code",
                table: "payment_terms",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_price_list_customer_id",
                table: "price_list",
                column: "customer_id");

            migrationBuilder.CreateIndex(
                name: "ix_price_list_product_id_customer_id_valid_from",
                table: "price_list",
                columns: new[] { "product_id", "customer_id", "valid_from" },
                unique: true)
                .Annotation("Npgsql:NullsDistinct", false);

            migrationBuilder.CreateIndex(
                name: "ix_quote_lines_product_id",
                table: "quote_lines",
                column: "product_id");

            migrationBuilder.CreateIndex(
                name: "ix_quote_lines_quote_id_sequence",
                table: "quote_lines",
                columns: new[] { "quote_id", "sequence" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_quotes_address_id",
                table: "quotes",
                column: "address_id");

            migrationBuilder.CreateIndex(
                name: "ix_quotes_customer_id",
                table: "quotes",
                column: "customer_id");

            migrationBuilder.CreateIndex(
                name: "ix_quotes_number_revision",
                table: "quotes",
                columns: new[] { "number", "revision" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_quotes_payment_term_id",
                table: "quotes",
                column: "payment_term_id");

            migrationBuilder.CreateIndex(
                name: "ix_quotes_status",
                table: "quotes",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_sales_events_kind_record_id",
                table: "sales_events",
                columns: new[] { "kind", "record_id" });

            migrationBuilder.CreateIndex(
                name: "ix_sales_order_lines_order_id_sequence",
                table: "sales_order_lines",
                columns: new[] { "order_id", "sequence" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_sales_order_lines_product_id",
                table: "sales_order_lines",
                column: "product_id");

            migrationBuilder.CreateIndex(
                name: "ix_sales_order_lines_production_order_id",
                table: "sales_order_lines",
                column: "production_order_id");

            migrationBuilder.CreateIndex(
                name: "ix_sales_order_lines_reservation_id",
                table: "sales_order_lines",
                column: "reservation_id");

            migrationBuilder.CreateIndex(
                name: "ix_sales_orders_address_id",
                table: "sales_orders",
                column: "address_id");

            migrationBuilder.CreateIndex(
                name: "ix_sales_orders_customer_id",
                table: "sales_orders",
                column: "customer_id");

            migrationBuilder.CreateIndex(
                name: "ix_sales_orders_number",
                table: "sales_orders",
                column: "number",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_sales_orders_payment_term_id",
                table: "sales_orders",
                column: "payment_term_id");

            migrationBuilder.CreateIndex(
                name: "ix_sales_orders_quote_id",
                table: "sales_orders",
                column: "quote_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_sales_orders_reference",
                table: "sales_orders",
                column: "reference",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_sales_orders_status",
                table: "sales_orders",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_sales_settings_shipping_location_id",
                table: "sales_settings",
                column: "shipping_location_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "delivery_lines");

            migrationBuilder.DropTable(
                name: "price_list");

            migrationBuilder.DropTable(
                name: "quote_lines");

            migrationBuilder.DropTable(
                name: "sales_events");

            migrationBuilder.DropTable(
                name: "sales_settings");

            migrationBuilder.DropTable(
                name: "deliveries");

            migrationBuilder.DropTable(
                name: "sales_order_lines");

            migrationBuilder.DropTable(
                name: "sales_orders");

            migrationBuilder.DropTable(
                name: "quotes");

            migrationBuilder.DropTable(
                name: "payment_terms");

            migrationBuilder.DropSequence(
                name: "delivery_numbers");

            migrationBuilder.DropSequence(
                name: "sales_order_numbers");

            migrationBuilder.DropSequence(
                name: "sales_quote_numbers");
        }
    }
}
