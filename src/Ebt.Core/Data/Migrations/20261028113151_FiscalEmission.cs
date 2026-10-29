using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class FiscalEmission : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "cfops",
                columns: table => new
                {
                    code = table.Column<string>(type: "character varying(4)", maxLength: 4, nullable: false),
                    description = table.Column<string>(type: "text", nullable: false),
                    kind = table.Column<int>(type: "integer", nullable: false),
                    taxed = table.Column<bool>(type: "boolean", nullable: false),
                    icms_cst = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    ipi_cst = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    pis_cst = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    cofins_cst = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    default_pis_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    default_cofins_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    ipi_framing_code = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    generates_installments = table.Column<bool>(type: "boolean", nullable: false),
                    active = table.Column<bool>(type: "boolean", nullable: false),
                    legal_text = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_cfops", x => x.code);
                });

            migrationBuilder.CreateTable(
                name: "fiscal_documents",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    kind = table.Column<int>(type: "integer", nullable: false),
                    status = table.Column<int>(type: "integer", nullable: false),
                    cfop_code = table.Column<string>(type: "character varying(4)", maxLength: 4, nullable: false),
                    series = table.Column<int>(type: "integer", nullable: false),
                    number = table.Column<int>(type: "integer", nullable: false),
                    access_key = table.Column<string>(type: "character varying(44)", maxLength: 44, nullable: false),
                    environment = table.Column<int>(type: "integer", nullable: false),
                    simulated = table.Column<bool>(type: "boolean", nullable: false),
                    protocol = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    issued_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    issued_by = table.Column<string>(type: "text", nullable: true),
                    delivery_id = table.Column<int>(type: "integer", nullable: true),
                    outside_shipment_id = table.Column<int>(type: "integer", nullable: true),
                    customer_id = table.Column<int>(type: "integer", nullable: true),
                    supplier_id = table.Column<int>(type: "integer", nullable: true),
                    recipient_name = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    recipient_document = table.Column<string>(type: "character varying(14)", maxLength: 14, nullable: false),
                    recipient_uf = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    products_total = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    freight_total = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    icms_base = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    icms_total = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    ipi_total = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    pis_total = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    cofins_total = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    invoice_total = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    additional_info = table.Column<string>(type: "text", nullable: true),
                    xml = table.Column<string>(type: "text", nullable: false),
                    cancelled_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    cancelled_by = table.Column<string>(type: "text", nullable: true),
                    cancel_reason = table.Column<string>(type: "text", nullable: true),
                    cancel_protocol = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_fiscal_documents", x => x.id);
                    table.ForeignKey(
                        name: "fk_fiscal_documents_customers_customer_id",
                        column: x => x.customer_id,
                        principalTable: "customers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_fiscal_documents_deliveries_delivery_id",
                        column: x => x.delivery_id,
                        principalTable: "deliveries",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_fiscal_documents_outside_shipments_outside_shipment_id",
                        column: x => x.outside_shipment_id,
                        principalTable: "outside_shipments",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_fiscal_documents_suppliers_supplier_id",
                        column: x => x.supplier_id,
                        principalTable: "suppliers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "fiscal_settings",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    enabled = table.Column<bool>(type: "boolean", nullable: false),
                    environment = table.Column<int>(type: "integer", nullable: false),
                    company_name = table.Column<string>(type: "text", nullable: true),
                    trade_name = table.Column<string>(type: "text", nullable: true),
                    cnpj = table.Column<string>(type: "character varying(14)", maxLength: 14, nullable: true),
                    state_registration = table.Column<string>(type: "character varying(14)", maxLength: 14, nullable: true),
                    tax_regime = table.Column<int>(type: "integer", nullable: false),
                    street = table.Column<string>(type: "text", nullable: true),
                    number = table.Column<string>(type: "text", nullable: true),
                    complement = table.Column<string>(type: "text", nullable: true),
                    district = table.Column<string>(type: "text", nullable: true),
                    city = table.Column<string>(type: "text", nullable: true),
                    city_ibge_code = table.Column<string>(type: "character varying(7)", maxLength: 7, nullable: true),
                    uf = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    zip_code = table.Column<string>(type: "text", nullable: true),
                    phone = table.Column<string>(type: "text", nullable: true),
                    series = table.Column<int>(type: "integer", nullable: false),
                    next_number = table.Column<int>(type: "integer", nullable: false),
                    cancel_window_hours = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_fiscal_settings", x => x.id);
                    table.CheckConstraint("ck_fiscal_settings_values", "series > 0 AND next_number > 0 AND cancel_window_hours >= 0 AND tax_regime BETWEEN 1 AND 3");
                });

            migrationBuilder.CreateTable(
                name: "monthly_prices",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    product_id = table.Column<int>(type: "integer", nullable: false),
                    customer_id = table.Column<int>(type: "integer", nullable: false),
                    cfop_code = table.Column<string>(type: "character varying(4)", maxLength: 4, nullable: false),
                    year = table.Column<int>(type: "integer", nullable: false),
                    month = table.Column<int>(type: "integer", nullable: false),
                    unit_price = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_monthly_prices", x => x.id);
                    table.CheckConstraint("ck_monthly_prices_values", "unit_price > 0 AND month BETWEEN 1 AND 12 AND year BETWEEN 2000 AND 2100");
                    table.ForeignKey(
                        name: "fk_monthly_prices_customers_customer_id",
                        column: x => x.customer_id,
                        principalTable: "customers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_monthly_prices_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "tax_rules",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    product_id = table.Column<int>(type: "integer", nullable: false),
                    customer_id = table.Column<int>(type: "integer", nullable: true),
                    cfop_code = table.Column<string>(type: "character varying(4)", maxLength: 4, nullable: false),
                    icms_cst = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: true),
                    icms_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    icms_base_reduction_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    ipi_cst = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: true),
                    ipi_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    pis_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: true),
                    cofins_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_tax_rules", x => x.id);
                    table.ForeignKey(
                        name: "fk_tax_rules_cfops_cfop_code",
                        column: x => x.cfop_code,
                        principalTable: "cfops",
                        principalColumn: "code",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_tax_rules_customers_customer_id",
                        column: x => x.customer_id,
                        principalTable: "customers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_tax_rules_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "fiscal_document_lines",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    document_id = table.Column<int>(type: "integer", nullable: false),
                    sequence = table.Column<int>(type: "integer", nullable: false),
                    product_id = table.Column<int>(type: "integer", nullable: true),
                    production_order_id = table.Column<int>(type: "integer", nullable: true),
                    code = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    description = table.Column<string>(type: "text", nullable: false),
                    ncm = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: false),
                    unit = table.Column<string>(type: "character varying(6)", maxLength: 6, nullable: false),
                    quantity = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    unit_price = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: false),
                    total = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    freight = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    icms_cst = table.Column<string>(type: "text", nullable: false),
                    icms_base = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    icms_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    icms_value = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    icms_base_reduction_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    ipi_cst = table.Column<string>(type: "text", nullable: false),
                    ipi_base = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    ipi_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    ipi_value = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    pis_cst = table.Column<string>(type: "text", nullable: false),
                    pis_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    pis_value = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    cofins_cst = table.Column<string>(type: "text", nullable: false),
                    cofins_percent = table.Column<decimal>(type: "numeric(7,4)", precision: 7, scale: 4, nullable: false),
                    cofins_value = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_fiscal_document_lines", x => x.id);
                    table.ForeignKey(
                        name: "fk_fiscal_document_lines_fiscal_documents_document_id",
                        column: x => x.document_id,
                        principalTable: "fiscal_documents",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_fiscal_document_lines_production_orders_production_order_id",
                        column: x => x.production_order_id,
                        principalTable: "production_orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_fiscal_document_lines_products_product_id",
                        column: x => x.product_id,
                        principalTable: "products",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "fiscal_installments",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    document_id = table.Column<int>(type: "integer", nullable: false),
                    sequence = table.Column<int>(type: "integer", nullable: false),
                    due_date = table.Column<DateOnly>(type: "date", nullable: false),
                    amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_fiscal_installments", x => x.id);
                    table.ForeignKey(
                        name: "fk_fiscal_installments_fiscal_documents_document_id",
                        column: x => x.document_id,
                        principalTable: "fiscal_documents",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.InsertData(
                table: "cfops",
                columns: new[] { "code", "active", "cofins_cst", "default_cofins_percent", "default_pis_percent", "description", "generates_installments", "icms_cst", "ipi_cst", "ipi_framing_code", "kind", "legal_text", "pis_cst", "taxed" },
                values: new object[,]
                {
                    { "5101", true, "01", 3m, 0.65m, "Venda de produção do estabelecimento", true, "00", "50", "999", 0, null, "01", true },
                    { "5124", true, "01", 3m, 0.65m, "Industrialização efetuada para outra empresa", true, "00", "50", "999", 0, null, "01", true },
                    { "5901", true, "09", 0m, 0m, "Remessa para industrialização por encomenda", false, "50", "55", "108", 1, "Suspensão do IPI conforme art. 43 do Decreto 7.212/10. Suspensão do ICMS conforme art. 402 do RICMS/SP. Remessa para industrialização, retorno previsto.", "09", false },
                    { "5902", true, "09", 0m, 0m, "Retorno de mercadoria utilizada na industrialização por encomenda", false, "50", "55", "108", 0, "Retorno de mercadoria recebida para industrialização.", "09", false },
                    { "5920", true, "08", 0m, 0m, "Remessa de vasilhame ou sacaria", false, "41", "53", "999", 0, null, "08", false },
                    { "5921", true, "08", 0m, 0m, "Retorno de vasilhame ou sacaria", false, "41", "53", "999", 0, null, "08", false }
                });

            migrationBuilder.InsertData(
                table: "fiscal_settings",
                columns: new[] { "id", "cancel_window_hours", "city", "city_ibge_code", "cnpj", "company_name", "complement", "district", "enabled", "environment", "next_number", "number", "phone", "series", "state_registration", "street", "tax_regime", "trade_name", "uf", "zip_code" },
                values: new object[] { 1, 24, null, null, null, null, null, null, false, 2, 2581, null, null, 1, null, null, 3, null, "SP", null });

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_document_lines_document_id_sequence",
                table: "fiscal_document_lines",
                columns: new[] { "document_id", "sequence" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_document_lines_product_id",
                table: "fiscal_document_lines",
                column: "product_id");

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_document_lines_production_order_id",
                table: "fiscal_document_lines",
                column: "production_order_id");

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_documents_access_key",
                table: "fiscal_documents",
                column: "access_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_documents_customer_id",
                table: "fiscal_documents",
                column: "customer_id");

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_documents_delivery_id",
                table: "fiscal_documents",
                column: "delivery_id");

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_documents_outside_shipment_id",
                table: "fiscal_documents",
                column: "outside_shipment_id");

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_documents_series_number",
                table: "fiscal_documents",
                columns: new[] { "series", "number" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_documents_supplier_id",
                table: "fiscal_documents",
                column: "supplier_id");

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_installments_document_id_sequence",
                table: "fiscal_installments",
                columns: new[] { "document_id", "sequence" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_monthly_prices_customer_id",
                table: "monthly_prices",
                column: "customer_id");

            migrationBuilder.CreateIndex(
                name: "ix_monthly_prices_product_id_customer_id_cfop_code_year_month",
                table: "monthly_prices",
                columns: new[] { "product_id", "customer_id", "cfop_code", "year", "month" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_tax_rules_cfop_code",
                table: "tax_rules",
                column: "cfop_code");

            migrationBuilder.CreateIndex(
                name: "ix_tax_rules_customer_id",
                table: "tax_rules",
                column: "customer_id");

            migrationBuilder.CreateIndex(
                name: "ix_tax_rules_product_id_customer_id_cfop_code",
                table: "tax_rules",
                columns: new[] { "product_id", "customer_id", "cfop_code" },
                unique: true)
                .Annotation("Npgsql:NullsDistinct", false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "fiscal_document_lines");

            migrationBuilder.DropTable(
                name: "fiscal_installments");

            migrationBuilder.DropTable(
                name: "fiscal_settings");

            migrationBuilder.DropTable(
                name: "monthly_prices");

            migrationBuilder.DropTable(
                name: "tax_rules");

            migrationBuilder.DropTable(
                name: "fiscal_documents");

            migrationBuilder.DropTable(
                name: "cfops");
        }
    }
}
