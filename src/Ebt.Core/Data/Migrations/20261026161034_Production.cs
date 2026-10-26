using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class Production : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateSequence<int>(
                name: "internal_order_numbers");

            migrationBuilder.CreateSequence<int>(
                name: "production_order_numbers");

            migrationBuilder.CreateTable(
                name: "holidays",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    date = table.Column<DateOnly>(type: "date", nullable: false),
                    name = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_holidays", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "production_occurrences",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    description = table.Column<string>(type: "text", nullable: false),
                    kind = table.Column<int>(type: "integer", nullable: false),
                    stops_order = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_production_occurrences", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "production_orders",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    kind = table.Column<int>(type: "integer", nullable: false),
                    number = table.Column<int>(type: "integer", nullable: false),
                    reference = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    product_id = table.Column<int>(type: "integer", nullable: false),
                    customer_id = table.Column<int>(type: "integer", nullable: true),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    due_date = table.Column<DateOnly>(type: "date", nullable: false),
                    planned_start = table.Column<DateOnly>(type: "date", nullable: true),
                    planned_end = table.Column<DateOnly>(type: "date", nullable: true),
                    adjusted_start = table.Column<DateOnly>(type: "date", nullable: true),
                    adjusted_end = table.Column<DateOnly>(type: "date", nullable: true),
                    status = table.Column<int>(type: "integer", nullable: false),
                    parent_order_id = table.Column<int>(type: "integer", nullable: true),
                    previous_order_id = table.Column<int>(type: "integer", nullable: true),
                    bales = table.Column<int>(type: "integer", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true),
                    status_reason = table.Column<string>(type: "text", nullable: true),
                    created_by = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    released_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    finished_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    closed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    closed_by = table.Column<string>(type: "text", nullable: true),
                    cost_closed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    material_cost = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: true),
                    service_cost = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: true),
                    unit_cost = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_production_orders", x => x.id);
                    table.CheckConstraint("ck_production_orders_quantity", "quantity > 0");
                    table.ForeignKey(
                        name: "fk_production_orders_customers_customer_id",
                        column: x => x.customer_id,
                        principalTable: "customers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_orders_production_orders_parent_order_id",
                        column: x => x.parent_order_id,
                        principalTable: "production_orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_orders_production_orders_previous_order_id",
                        column: x => x.previous_order_id,
                        principalTable: "production_orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_orders_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "production_settings",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    overrun_tolerance_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    hours_per_day = table.Column<decimal>(type: "numeric(5,2)", precision: 5, scale: 2, nullable: false),
                    work_saturdays = table.Column<bool>(type: "boolean", nullable: false),
                    issue_location_id = table.Column<int>(type: "integer", nullable: true),
                    receipt_location_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_production_settings", x => x.id);
                    table.CheckConstraint("ck_production_settings_hours", "hours_per_day > 0 AND hours_per_day <= 24");
                    table.ForeignKey(
                        name: "fk_production_settings_stock_locations_issue_location_id",
                        column: x => x.issue_location_id,
                        principalTable: "stock_locations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_settings_stock_locations_receipt_location_id",
                        column: x => x.receipt_location_id,
                        principalTable: "stock_locations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "shifts",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    name = table.Column<string>(type: "text", nullable: false),
                    starts_at = table.Column<TimeOnly>(type: "time without time zone", nullable: true),
                    ends_at = table.Column<TimeOnly>(type: "time without time zone", nullable: true),
                    hours = table.Column<decimal>(type: "numeric(5,2)", precision: 5, scale: 2, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_shifts", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "production_order_materials",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    order_id = table.Column<int>(type: "integer", nullable: false),
                    operation_sequence = table.Column<int>(type: "integer", nullable: false),
                    material_id = table.Column<int>(type: "integer", nullable: true),
                    component_product_id = table.Column<int>(type: "integer", nullable: true),
                    quantity_per_unit = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    required_quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    unit = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    reservation_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_production_order_materials", x => x.id);
                    table.CheckConstraint("ck_production_order_materials_one_item", "(material_id IS NULL) <> (component_product_id IS NULL)");
                    table.CheckConstraint("ck_production_order_materials_quantity", "required_quantity >= 0");
                    table.ForeignKey(
                        name: "fk_production_order_materials_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_order_materials_production_orders_order_id",
                        column: x => x.order_id,
                        principalTable: "production_orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_production_order_materials_products_component_product_id",
                        column: x => x.component_product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_order_materials_stock_reservations_reservation_id",
                        column: x => x.reservation_id,
                        principalTable: "stock_reservations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "production_order_operations",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    order_id = table.Column<int>(type: "integer", nullable: false),
                    sequence = table.Column<int>(type: "integer", nullable: false),
                    description = table.Column<string>(type: "text", nullable: true),
                    machine_id = table.Column<int>(type: "integer", nullable: true),
                    work_center_id = table.Column<int>(type: "integer", nullable: true),
                    setup_hours = table.Column<decimal>(type: "numeric(10,4)", precision: 10, scale: 4, nullable: true),
                    pieces_per_hour = table.Column<decimal>(type: "numeric(12,3)", precision: 12, scale: 3, nullable: true),
                    operators = table.Column<decimal>(type: "numeric(6,2)", precision: 6, scale: 2, nullable: true),
                    external = table.Column<bool>(type: "boolean", nullable: false),
                    supplier_id = table.Column<int>(type: "integer", nullable: true),
                    external_lead_days = table.Column<int>(type: "integer", nullable: true),
                    overrun_released = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    planned_hours = table.Column<decimal>(type: "numeric(12,4)", precision: 12, scale: 4, nullable: false),
                    planned_start = table.Column<DateOnly>(type: "date", nullable: true),
                    planned_end = table.Column<DateOnly>(type: "date", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_production_order_operations", x => x.id);
                    table.CheckConstraint("ck_production_order_operations_external", "NOT external OR supplier_id IS NOT NULL");
                    table.ForeignKey(
                        name: "fk_production_order_operations_machines_machine_id",
                        column: x => x.machine_id,
                        principalTable: "machines",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_order_operations_production_orders_order_id",
                        column: x => x.order_id,
                        principalTable: "production_orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_production_order_operations_suppliers_supplier_id",
                        column: x => x.supplier_id,
                        principalTable: "suppliers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_order_operations_work_centers_work_center_id",
                        column: x => x.work_center_id,
                        principalTable: "work_centers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "employees",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    name = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    nickname = table.Column<string>(type: "text", nullable: true),
                    function = table.Column<string>(type: "text", nullable: true),
                    work_center_id = table.Column<int>(type: "integer", nullable: true),
                    shift_id = table.Column<int>(type: "integer", nullable: true),
                    active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_employees", x => x.id);
                    table.ForeignKey(
                        name: "fk_employees_shifts_shift_id",
                        column: x => x.shift_id,
                        principalTable: "shifts",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_employees_work_centers_work_center_id",
                        column: x => x.work_center_id,
                        principalTable: "work_centers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "outside_shipments",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    operation_id = table.Column<int>(type: "integer", nullable: false),
                    supplier_id = table.Column<int>(type: "integer", nullable: false),
                    sent_on = table.Column<DateOnly>(type: "date", nullable: false),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    invoice_number = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: true),
                    returned_quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    scrap_quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    service_value = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    notes = table.Column<string>(type: "text", nullable: true),
                    created_by = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_outside_shipments", x => x.id);
                    table.CheckConstraint("ck_outside_shipments_quantities", "quantity > 0 AND returned_quantity >= 0 AND scrap_quantity >= 0 AND returned_quantity + scrap_quantity <= quantity");
                    table.ForeignKey(
                        name: "fk_outside_shipments_production_order_operations_operation_id",
                        column: x => x.operation_id,
                        principalTable: "production_order_operations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_outside_shipments_suppliers_supplier_id",
                        column: x => x.supplier_id,
                        principalTable: "suppliers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "overrun_releases",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    operation_id = table.Column<int>(type: "integer", nullable: false),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    justification = table.Column<string>(type: "text", nullable: false),
                    released_by = table.Column<string>(type: "text", nullable: true),
                    released_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_overrun_releases", x => x.id);
                    table.CheckConstraint("ck_overrun_releases_quantity", "quantity > 0");
                    table.ForeignKey(
                        name: "fk_overrun_releases_production_order_operations_operation_id",
                        column: x => x.operation_id,
                        principalTable: "production_order_operations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "production_reports",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    order_id = table.Column<int>(type: "integer", nullable: false),
                    operation_id = table.Column<int>(type: "integer", nullable: false),
                    date = table.Column<DateOnly>(type: "date", nullable: false),
                    shift_id = table.Column<int>(type: "integer", nullable: true),
                    employee_id = table.Column<int>(type: "integer", nullable: true),
                    machine_id = table.Column<int>(type: "integer", nullable: true),
                    start_time = table.Column<TimeOnly>(type: "time without time zone", nullable: true),
                    end_time = table.Column<TimeOnly>(type: "time without time zone", nullable: true),
                    hours = table.Column<decimal>(type: "numeric(10,4)", precision: 10, scale: 4, nullable: true),
                    setup_hours = table.Column<decimal>(type: "numeric(10,4)", precision: 10, scale: 4, nullable: true),
                    operators = table.Column<decimal>(type: "numeric(6,2)", precision: 6, scale: 2, nullable: true),
                    downtime_hours = table.Column<decimal>(type: "numeric(10,4)", precision: 10, scale: 4, nullable: true),
                    downtime_occurrence_id = table.Column<int>(type: "integer", nullable: true),
                    good_quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    scrap_quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    scrap_occurrence_id = table.Column<int>(type: "integer", nullable: true),
                    weight_kg = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: true),
                    outside_shipment_id = table.Column<int>(type: "integer", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true),
                    legacy_key = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                    reported_by = table.Column<string>(type: "text", nullable: true),
                    reported_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_production_reports", x => x.id);
                    table.CheckConstraint("ck_production_reports_quantities", "good_quantity >= 0 AND scrap_quantity >= 0");
                    table.ForeignKey(
                        name: "fk_production_reports_employees_employee_id",
                        column: x => x.employee_id,
                        principalTable: "employees",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_reports_machines_machine_id",
                        column: x => x.machine_id,
                        principalTable: "machines",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_reports_outside_shipments_outside_shipment_id",
                        column: x => x.outside_shipment_id,
                        principalTable: "outside_shipments",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_production_reports_production_occurrences_downtime_occurren",
                        column: x => x.downtime_occurrence_id,
                        principalTable: "production_occurrences",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_reports_production_occurrences_scrap_occurrence_",
                        column: x => x.scrap_occurrence_id,
                        principalTable: "production_occurrences",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_reports_production_order_operations_operation_id",
                        column: x => x.operation_id,
                        principalTable: "production_order_operations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_reports_production_orders_order_id",
                        column: x => x.order_id,
                        principalTable: "production_orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_production_reports_shifts_shift_id",
                        column: x => x.shift_id,
                        principalTable: "shifts",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.InsertData(
                table: "production_settings",
                columns: new[] { "id", "hours_per_day", "issue_location_id", "overrun_tolerance_percent", "receipt_location_id", "work_saturdays" },
                values: new object[] { 1, 8m, null, 3m, null, false });

            migrationBuilder.CreateIndex(
                name: "ix_employees_code",
                table: "employees",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_employees_shift_id",
                table: "employees",
                column: "shift_id");

            migrationBuilder.CreateIndex(
                name: "ix_employees_work_center_id",
                table: "employees",
                column: "work_center_id");

            migrationBuilder.CreateIndex(
                name: "ix_holidays_date",
                table: "holidays",
                column: "date",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_outside_shipments_operation_id",
                table: "outside_shipments",
                column: "operation_id");

            migrationBuilder.CreateIndex(
                name: "ix_outside_shipments_supplier_id",
                table: "outside_shipments",
                column: "supplier_id");

            migrationBuilder.CreateIndex(
                name: "ix_overrun_releases_operation_id",
                table: "overrun_releases",
                column: "operation_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_occurrences_code",
                table: "production_occurrences",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_production_order_materials_component_product_id",
                table: "production_order_materials",
                column: "component_product_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_order_materials_material_id",
                table: "production_order_materials",
                column: "material_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_order_materials_order_id",
                table: "production_order_materials",
                column: "order_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_order_materials_reservation_id",
                table: "production_order_materials",
                column: "reservation_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_production_order_operations_machine_id",
                table: "production_order_operations",
                column: "machine_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_order_operations_order_id_sequence",
                table: "production_order_operations",
                columns: new[] { "order_id", "sequence" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_production_order_operations_supplier_id",
                table: "production_order_operations",
                column: "supplier_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_order_operations_work_center_id",
                table: "production_order_operations",
                column: "work_center_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_orders_customer_id",
                table: "production_orders",
                column: "customer_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_orders_due_date",
                table: "production_orders",
                column: "due_date");

            migrationBuilder.CreateIndex(
                name: "ix_production_orders_kind_number",
                table: "production_orders",
                columns: new[] { "kind", "number" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_production_orders_parent_order_id",
                table: "production_orders",
                column: "parent_order_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_orders_previous_order_id",
                table: "production_orders",
                column: "previous_order_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_orders_product_id",
                table: "production_orders",
                column: "product_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_orders_reference",
                table: "production_orders",
                column: "reference",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_production_orders_status",
                table: "production_orders",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_production_reports_date",
                table: "production_reports",
                column: "date");

            migrationBuilder.CreateIndex(
                name: "ix_production_reports_downtime_occurrence_id",
                table: "production_reports",
                column: "downtime_occurrence_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_reports_employee_id",
                table: "production_reports",
                column: "employee_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_reports_legacy_key",
                table: "production_reports",
                column: "legacy_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_production_reports_machine_id",
                table: "production_reports",
                column: "machine_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_reports_operation_id",
                table: "production_reports",
                column: "operation_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_reports_order_id_operation_id",
                table: "production_reports",
                columns: new[] { "order_id", "operation_id" });

            migrationBuilder.CreateIndex(
                name: "ix_production_reports_outside_shipment_id",
                table: "production_reports",
                column: "outside_shipment_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_reports_scrap_occurrence_id",
                table: "production_reports",
                column: "scrap_occurrence_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_reports_shift_id",
                table: "production_reports",
                column: "shift_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_settings_issue_location_id",
                table: "production_settings",
                column: "issue_location_id");

            migrationBuilder.CreateIndex(
                name: "ix_production_settings_receipt_location_id",
                table: "production_settings",
                column: "receipt_location_id");

            migrationBuilder.CreateIndex(
                name: "ix_shifts_code",
                table: "shifts",
                column: "code",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "holidays");

            migrationBuilder.DropTable(
                name: "overrun_releases");

            migrationBuilder.DropTable(
                name: "production_order_materials");

            migrationBuilder.DropTable(
                name: "production_reports");

            migrationBuilder.DropTable(
                name: "production_settings");

            migrationBuilder.DropTable(
                name: "employees");

            migrationBuilder.DropTable(
                name: "outside_shipments");

            migrationBuilder.DropTable(
                name: "production_occurrences");

            migrationBuilder.DropTable(
                name: "shifts");

            migrationBuilder.DropTable(
                name: "production_order_operations");

            migrationBuilder.DropTable(
                name: "production_orders");

            migrationBuilder.DropSequence(
                name: "internal_order_numbers");

            migrationBuilder.DropSequence(
                name: "production_order_numbers");
        }
    }
}
