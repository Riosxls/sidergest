using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class InitialEngineering : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "customers",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    legacy_code = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: true),
                    name = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    trade_name = table.Column<string>(type: "text", nullable: true),
                    consumer_type = table.Column<int>(type: "integer", nullable: false),
                    active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_customers", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "material_classes",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_material_classes", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "material_groups",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_material_groups", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "material_subgroups",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "text", nullable: false),
                    standard = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_material_subgroups", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "products",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    name = table.Column<string>(type: "text", nullable: false),
                    kind = table.Column<int>(type: "integer", nullable: false),
                    shape = table.Column<int>(type: "integer", nullable: true),
                    diameter_mm = table.Column<decimal>(type: "numeric(10,3)", precision: 10, scale: 3, nullable: true),
                    width_mm = table.Column<decimal>(type: "numeric(10,3)", precision: 10, scale: 3, nullable: true),
                    height_mm = table.Column<decimal>(type: "numeric(10,3)", precision: 10, scale: 3, nullable: true),
                    thickness_mm = table.Column<decimal>(type: "numeric(8,3)", precision: 8, scale: 3, nullable: true),
                    length_mm = table.Column<decimal>(type: "numeric(12,3)", precision: 12, scale: 3, nullable: true),
                    net_weight_kg = table.Column<decimal>(type: "numeric(14,5)", precision: 14, scale: 5, nullable: true),
                    loss_percent = table.Column<decimal>(type: "numeric(5,2)", precision: 5, scale: 2, nullable: true),
                    ncm = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: false),
                    stock_unit = table.Column<string>(type: "text", nullable: false),
                    pieces_per_package = table.Column<int>(type: "integer", nullable: true),
                    blocked = table.Column<bool>(type: "boolean", nullable: false),
                    drawing_revision = table.Column<string>(type: "text", nullable: true),
                    process_revision = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_products", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "standard_operations",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_standard_operations", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "suppliers",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    legacy_code = table.Column<string>(type: "text", nullable: true),
                    name = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    trade_name = table.Column<string>(type: "text", nullable: true),
                    group_code = table.Column<string>(type: "text", nullable: true),
                    active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_suppliers", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "tools",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "text", nullable: false),
                    warning_limit = table.Column<int>(type: "integer", nullable: true),
                    inspection_limit = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_tools", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "users",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    username = table.Column<string>(type: "text", nullable: false),
                    password_hash = table.Column<string>(type: "text", nullable: false),
                    role = table.Column<int>(type: "integer", nullable: false),
                    active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_users", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "work_centers",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "text", nullable: false),
                    cost_center = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_work_centers", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "customer_addresses",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    customer_id = table.Column<int>(type: "integer", nullable: false),
                    legacy_code = table.Column<string>(type: "text", nullable: true),
                    document = table.Column<string>(type: "character varying(14)", maxLength: 14, nullable: false),
                    state_registration = table.Column<string>(type: "text", nullable: true),
                    icms_contributor = table.Column<bool>(type: "boolean", nullable: false),
                    street = table.Column<string>(type: "text", nullable: true),
                    number = table.Column<string>(type: "text", nullable: true),
                    complement = table.Column<string>(type: "text", nullable: true),
                    district = table.Column<string>(type: "text", nullable: true),
                    city = table.Column<string>(type: "text", nullable: true),
                    city_ibge_code = table.Column<string>(type: "character varying(7)", maxLength: 7, nullable: true),
                    uf = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    zip_code = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: true),
                    default_cfop = table.Column<string>(type: "text", nullable: true),
                    buyer = table.Column<string>(type: "text", nullable: true),
                    email = table.Column<string>(type: "text", nullable: true),
                    phone = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_customer_addresses", x => x.id);
                    table.ForeignKey(
                        name: "fk_customer_addresses_customers_customer_id",
                        column: x => x.customer_id,
                        principalTable: "customers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "materials",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    description = table.Column<string>(type: "text", nullable: false),
                    class_id = table.Column<int>(type: "integer", nullable: true),
                    group_id = table.Column<int>(type: "integer", nullable: true),
                    subgroup_id = table.Column<int>(type: "integer", nullable: true),
                    stock_unit = table.Column<string>(type: "text", nullable: false),
                    purchase_unit = table.Column<string>(type: "text", nullable: false),
                    purchase_factor = table.Column<decimal>(type: "numeric(14,6)", precision: 14, scale: 6, nullable: false),
                    thickness_mm = table.Column<decimal>(type: "numeric(8,3)", precision: 8, scale: 3, nullable: true),
                    width_mm = table.Column<decimal>(type: "numeric(10,3)", precision: 10, scale: 3, nullable: true),
                    ncm = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: true),
                    lead_time_days = table.Column<int>(type: "integer", nullable: true),
                    purchase_lot = table.Column<decimal>(type: "numeric(14,3)", precision: 14, scale: 3, nullable: true),
                    min_stock = table.Column<decimal>(type: "numeric(14,3)", precision: 14, scale: 3, nullable: true),
                    max_stock = table.Column<decimal>(type: "numeric(14,3)", precision: 14, scale: 3, nullable: true),
                    requires_inspection = table.Column<bool>(type: "boolean", nullable: false),
                    generates_purchase_order = table.Column<bool>(type: "boolean", nullable: false),
                    external_processing = table.Column<bool>(type: "boolean", nullable: false),
                    active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_materials", x => x.id);
                    table.ForeignKey(
                        name: "fk_materials_material_classes_class_id",
                        column: x => x.class_id,
                        principalTable: "material_classes",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_materials_material_groups_group_id",
                        column: x => x.group_id,
                        principalTable: "material_groups",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_materials_material_subgroups_subgroup_id",
                        column: x => x.subgroup_id,
                        principalTable: "material_subgroups",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "product_customers",
                columns: table => new
                {
                    product_id = table.Column<int>(type: "integer", nullable: false),
                    customer_id = table.Column<int>(type: "integer", nullable: false),
                    customer_part_number = table.Column<string>(type: "text", nullable: true),
                    customer_description = table.Column<string>(type: "text", nullable: true),
                    active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_product_customers", x => new { x.product_id, x.customer_id });
                    table.ForeignKey(
                        name: "fk_product_customers_customers_customer_id",
                        column: x => x.customer_id,
                        principalTable: "customers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_product_customers_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "revisions",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    product_id = table.Column<int>(type: "integer", nullable: false),
                    kind = table.Column<int>(type: "integer", nullable: false),
                    code = table.Column<string>(type: "text", nullable: false),
                    reason = table.Column<string>(type: "text", nullable: true),
                    user = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_revisions", x => x.id);
                    table.ForeignKey(
                        name: "fk_revisions_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "supplier_addresses",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    supplier_id = table.Column<int>(type: "integer", nullable: false),
                    legacy_code = table.Column<string>(type: "text", nullable: true),
                    document = table.Column<string>(type: "character varying(14)", maxLength: 14, nullable: true),
                    state_registration = table.Column<string>(type: "text", nullable: true),
                    street = table.Column<string>(type: "text", nullable: true),
                    number = table.Column<string>(type: "text", nullable: true),
                    district = table.Column<string>(type: "text", nullable: true),
                    city = table.Column<string>(type: "text", nullable: true),
                    city_ibge_code = table.Column<string>(type: "text", nullable: true),
                    uf = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    zip_code = table.Column<string>(type: "text", nullable: true),
                    email = table.Column<string>(type: "text", nullable: true),
                    phone = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_supplier_addresses", x => x.id);
                    table.ForeignKey(
                        name: "fk_supplier_addresses_suppliers_supplier_id",
                        column: x => x.supplier_id,
                        principalTable: "suppliers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "machines",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "text", nullable: false),
                    work_center_id = table.Column<int>(type: "integer", nullable: true),
                    family = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_machines", x => x.id);
                    table.ForeignKey(
                        name: "fk_machines_work_centers_work_center_id",
                        column: x => x.work_center_id,
                        principalTable: "work_centers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "routing_operations",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    product_id = table.Column<int>(type: "integer", nullable: false),
                    sequence = table.Column<int>(type: "integer", nullable: false),
                    standard_operation_id = table.Column<int>(type: "integer", nullable: true),
                    machine_id = table.Column<int>(type: "integer", nullable: true),
                    work_center_id = table.Column<int>(type: "integer", nullable: true),
                    tool_id = table.Column<int>(type: "integer", nullable: true),
                    setup_hours = table.Column<decimal>(type: "numeric(10,4)", precision: 10, scale: 4, nullable: true),
                    pieces_per_hour = table.Column<decimal>(type: "numeric(12,3)", precision: 12, scale: 3, nullable: true),
                    operators = table.Column<decimal>(type: "numeric(6,2)", precision: 6, scale: 2, nullable: true),
                    description = table.Column<string>(type: "text", nullable: true),
                    standard = table.Column<string>(type: "text", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_routing_operations", x => x.id);
                    table.CheckConstraint("ck_routing_operations_sequence", "sequence > 0 AND sequence % 10 = 0");
                    table.ForeignKey(
                        name: "fk_routing_operations_machines_machine_id",
                        column: x => x.machine_id,
                        principalTable: "machines",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_routing_operations_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_routing_operations_standard_operations_standard_operation_id",
                        column: x => x.standard_operation_id,
                        principalTable: "standard_operations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_routing_operations_tools_tool_id",
                        column: x => x.tool_id,
                        principalTable: "tools",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_routing_operations_work_centers_work_center_id",
                        column: x => x.work_center_id,
                        principalTable: "work_centers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "bom_items",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    routing_operation_id = table.Column<int>(type: "integer", nullable: false),
                    material_id = table.Column<int>(type: "integer", nullable: true),
                    component_product_id = table.Column<int>(type: "integer", nullable: true),
                    quantity = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    unit = table.Column<string>(type: "text", nullable: false),
                    factor = table.Column<decimal>(type: "numeric(14,6)", precision: 14, scale: 6, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_bom_items", x => x.id);
                    table.CheckConstraint("ck_bom_items_one_source", "(material_id IS NULL) <> (component_product_id IS NULL)");
                    table.ForeignKey(
                        name: "fk_bom_items_materials_material_id",
                        column: x => x.material_id,
                        principalTable: "materials",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_bom_items_products_component_product_id",
                        column: x => x.component_product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_bom_items_routing_operations_routing_operation_id",
                        column: x => x.routing_operation_id,
                        principalTable: "routing_operations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_bom_items_component_product_id",
                table: "bom_items",
                column: "component_product_id");

            migrationBuilder.CreateIndex(
                name: "ix_bom_items_material_id",
                table: "bom_items",
                column: "material_id");

            migrationBuilder.CreateIndex(
                name: "ix_bom_items_routing_operation_id",
                table: "bom_items",
                column: "routing_operation_id");

            migrationBuilder.CreateIndex(
                name: "ix_customer_addresses_customer_id_legacy_code",
                table: "customer_addresses",
                columns: new[] { "customer_id", "legacy_code" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_customers_legacy_code",
                table: "customers",
                column: "legacy_code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_machines_code",
                table: "machines",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_machines_work_center_id",
                table: "machines",
                column: "work_center_id");

            migrationBuilder.CreateIndex(
                name: "ix_material_classes_code",
                table: "material_classes",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_material_groups_code",
                table: "material_groups",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_material_subgroups_code",
                table: "material_subgroups",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_materials_class_id",
                table: "materials",
                column: "class_id");

            migrationBuilder.CreateIndex(
                name: "ix_materials_code",
                table: "materials",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_materials_group_id",
                table: "materials",
                column: "group_id");

            migrationBuilder.CreateIndex(
                name: "ix_materials_subgroup_id",
                table: "materials",
                column: "subgroup_id");

            migrationBuilder.CreateIndex(
                name: "ix_product_customers_customer_id",
                table: "product_customers",
                column: "customer_id");

            migrationBuilder.CreateIndex(
                name: "ix_products_code",
                table: "products",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_revisions_product_id",
                table: "revisions",
                column: "product_id");

            migrationBuilder.CreateIndex(
                name: "ix_routing_operations_machine_id",
                table: "routing_operations",
                column: "machine_id");

            migrationBuilder.CreateIndex(
                name: "ix_routing_operations_product_id_sequence",
                table: "routing_operations",
                columns: new[] { "product_id", "sequence" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_routing_operations_standard_operation_id",
                table: "routing_operations",
                column: "standard_operation_id");

            migrationBuilder.CreateIndex(
                name: "ix_routing_operations_tool_id",
                table: "routing_operations",
                column: "tool_id");

            migrationBuilder.CreateIndex(
                name: "ix_routing_operations_work_center_id",
                table: "routing_operations",
                column: "work_center_id");

            migrationBuilder.CreateIndex(
                name: "ix_standard_operations_code",
                table: "standard_operations",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_supplier_addresses_supplier_id_legacy_code",
                table: "supplier_addresses",
                columns: new[] { "supplier_id", "legacy_code" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_suppliers_legacy_code",
                table: "suppliers",
                column: "legacy_code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_tools_code",
                table: "tools",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_users_username",
                table: "users",
                column: "username",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_work_centers_code",
                table: "work_centers",
                column: "code",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "bom_items");

            migrationBuilder.DropTable(
                name: "customer_addresses");

            migrationBuilder.DropTable(
                name: "product_customers");

            migrationBuilder.DropTable(
                name: "revisions");

            migrationBuilder.DropTable(
                name: "supplier_addresses");

            migrationBuilder.DropTable(
                name: "users");

            migrationBuilder.DropTable(
                name: "materials");

            migrationBuilder.DropTable(
                name: "routing_operations");

            migrationBuilder.DropTable(
                name: "customers");

            migrationBuilder.DropTable(
                name: "suppliers");

            migrationBuilder.DropTable(
                name: "material_classes");

            migrationBuilder.DropTable(
                name: "material_groups");

            migrationBuilder.DropTable(
                name: "material_subgroups");

            migrationBuilder.DropTable(
                name: "machines");

            migrationBuilder.DropTable(
                name: "products");

            migrationBuilder.DropTable(
                name: "standard_operations");

            migrationBuilder.DropTable(
                name: "tools");

            migrationBuilder.DropTable(
                name: "work_centers");
        }
    }
}
