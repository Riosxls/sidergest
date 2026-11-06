using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class CertificateTemplateFound : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "hardness",
                table: "certificate_templates",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "found",
                table: "certificate_template_measures",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "hardness",
                table: "certificate_templates");

            migrationBuilder.DropColumn(
                name: "found",
                table: "certificate_template_measures");
        }
    }
}
