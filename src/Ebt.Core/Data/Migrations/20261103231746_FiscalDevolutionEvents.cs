using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class FiscalDevolutionEvents : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_fiscal_documents_delivery_id",
                table: "fiscal_documents");

            migrationBuilder.AddColumn<bool>(
                name: "key_lookup_required",
                table: "fiscal_documents",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "referenced_access_key",
                table: "fiscal_documents",
                type: "character varying(44)",
                maxLength: 44,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "referenced_document_id",
                table: "fiscal_documents",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "stock_document_id",
                table: "fiscal_documents",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "warnings",
                table: "fiscal_documents",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "referenced_line_id",
                table: "fiscal_document_lines",
                type: "integer",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "fiscal_carriers",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    document = table.Column<string>(type: "character varying(14)", maxLength: 14, nullable: true),
                    state_registration = table.Column<string>(type: "character varying(14)", maxLength: 14, nullable: true),
                    address = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: true),
                    city = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: true),
                    uf = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: true),
                    vehicle_uf = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_fiscal_carriers", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "fiscal_events",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    document_id = table.Column<int>(type: "integer", nullable: false),
                    event_type = table.Column<string>(type: "character varying(6)", maxLength: 6, nullable: false),
                    sequence = table.Column<int>(type: "integer", nullable: false),
                    text = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: false),
                    protocol = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    environment = table.Column<int>(type: "integer", nullable: false),
                    simulated = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_fiscal_events", x => x.id);
                    table.CheckConstraint("ck_fiscal_events_sequence", "sequence BETWEEN 1 AND 20");
                    table.ForeignKey(
                        name: "fk_fiscal_events_fiscal_documents_document_id",
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
                    { "1202", true, "01", 3m, 0.65m, "Devolução de venda de produção do estabelecimento", false, "00", "00", "999", 2, null, "01", true },
                    { "2202", true, "01", 3m, 0.65m, "Devolução de venda de produção do estabelecimento", false, "00", "00", "999", 2, null, "01", true }
                });

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_documents_referenced_document_id",
                table: "fiscal_documents",
                column: "referenced_document_id");

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_documents_stock_document_id",
                table: "fiscal_documents",
                column: "stock_document_id");

            migrationBuilder.CreateIndex(
                name: "ux_fiscal_documents_live_delivery",
                table: "fiscal_documents",
                column: "delivery_id",
                unique: true,
                filter: "delivery_id IS NOT NULL AND status IN (0, 2)");

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_document_lines_referenced_line_id",
                table: "fiscal_document_lines",
                column: "referenced_line_id");

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_carriers_name",
                table: "fiscal_carriers",
                column: "name",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_events_document_id_event_type_sequence",
                table: "fiscal_events",
                columns: new[] { "document_id", "event_type", "sequence" },
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "fk_fiscal_document_lines_fiscal_document_lines_referenced_line",
                table: "fiscal_document_lines",
                column: "referenced_line_id",
                principalTable: "fiscal_document_lines",
                principalColumn: "id");

            migrationBuilder.AddForeignKey(
                name: "fk_fiscal_documents_fiscal_documents_referenced_document_id",
                table: "fiscal_documents",
                column: "referenced_document_id",
                principalTable: "fiscal_documents",
                principalColumn: "id");

            migrationBuilder.AddForeignKey(
                name: "fk_fiscal_documents_stock_documents_stock_document_id",
                table: "fiscal_documents",
                column: "stock_document_id",
                principalTable: "stock_documents",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "fk_fiscal_document_lines_fiscal_document_lines_referenced_line",
                table: "fiscal_document_lines");

            migrationBuilder.DropForeignKey(
                name: "fk_fiscal_documents_fiscal_documents_referenced_document_id",
                table: "fiscal_documents");

            migrationBuilder.DropForeignKey(
                name: "fk_fiscal_documents_stock_documents_stock_document_id",
                table: "fiscal_documents");

            migrationBuilder.DropTable(
                name: "fiscal_carriers");

            migrationBuilder.DropTable(
                name: "fiscal_events");

            migrationBuilder.DropIndex(
                name: "ix_fiscal_documents_referenced_document_id",
                table: "fiscal_documents");

            migrationBuilder.DropIndex(
                name: "ix_fiscal_documents_stock_document_id",
                table: "fiscal_documents");

            migrationBuilder.DropIndex(
                name: "ux_fiscal_documents_live_delivery",
                table: "fiscal_documents");

            migrationBuilder.DropIndex(
                name: "ix_fiscal_document_lines_referenced_line_id",
                table: "fiscal_document_lines");

            migrationBuilder.DeleteData(
                table: "cfops",
                keyColumn: "code",
                keyValue: "1202");

            migrationBuilder.DeleteData(
                table: "cfops",
                keyColumn: "code",
                keyValue: "2202");

            migrationBuilder.DropColumn(
                name: "key_lookup_required",
                table: "fiscal_documents");

            migrationBuilder.DropColumn(
                name: "referenced_access_key",
                table: "fiscal_documents");

            migrationBuilder.DropColumn(
                name: "referenced_document_id",
                table: "fiscal_documents");

            migrationBuilder.DropColumn(
                name: "stock_document_id",
                table: "fiscal_documents");

            migrationBuilder.DropColumn(
                name: "warnings",
                table: "fiscal_documents");

            migrationBuilder.DropColumn(
                name: "referenced_line_id",
                table: "fiscal_document_lines");

            migrationBuilder.CreateIndex(
                name: "ix_fiscal_documents_delivery_id",
                table: "fiscal_documents",
                column: "delivery_id");
        }
    }
}
