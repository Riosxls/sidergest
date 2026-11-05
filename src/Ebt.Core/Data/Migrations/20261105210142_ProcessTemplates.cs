using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class ProcessTemplates : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "process_templates",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    customer_key = table.Column<string>(type: "character varying(6)", maxLength: 6, nullable: true),
                    customer_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    diameter_mm = table.Column<decimal>(type: "numeric(12,4)", precision: 12, scale: 4, nullable: false),
                    thickness_mm = table.Column<decimal>(type: "numeric(12,4)", precision: 12, scale: 4, nullable: true),
                    length_mm = table.Column<decimal>(type: "numeric(12,4)", precision: 12, scale: 4, nullable: true),
                    spec = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    source_ref = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    source_date = table.Column<DateOnly>(type: "date", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_process_templates", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "process_template_operations",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    template_id = table.Column<int>(type: "integer", nullable: false),
                    sequence = table.Column<int>(type: "integer", nullable: false),
                    description = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    tolerance = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: true),
                    measure_start = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: true),
                    measure_end = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: true),
                    resource = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_process_template_operations", x => x.id);
                    table.ForeignKey(
                        name: "fk_process_template_operations_process_templates_template_id",
                        column: x => x.template_id,
                        principalTable: "process_templates",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_process_template_operations_template_id_sequence",
                table: "process_template_operations",
                columns: new[] { "template_id", "sequence" });

            migrationBuilder.CreateIndex(
                name: "ix_process_templates_customer_key_diameter_mm_thickness_mm_len",
                table: "process_templates",
                columns: new[] { "customer_key", "diameter_mm", "thickness_mm", "length_mm" },
                unique: true)
                .Annotation("Npgsql:NullsDistinct", false);

            migrationBuilder.CreateIndex(
                name: "ix_process_templates_diameter_mm",
                table: "process_templates",
                column: "diameter_mm");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "process_template_operations");

            migrationBuilder.DropTable(
                name: "process_templates");
        }
    }
}
