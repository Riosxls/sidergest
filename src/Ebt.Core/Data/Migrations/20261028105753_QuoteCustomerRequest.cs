using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class QuoteCustomerRequest : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "request_file_name",
                table: "quotes",
                type: "character varying(255)",
                maxLength: 255,
                nullable: true);

            migrationBuilder.AddColumn<long>(
                name: "request_file_size",
                table: "quotes",
                type: "bigint",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "request_file_type",
                table: "quotes",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "request_text",
                table: "quotes",
                type: "text",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "quote_request_files",
                columns: table => new
                {
                    quote_id = table.Column<int>(type: "integer", nullable: false),
                    data = table.Column<byte[]>(type: "bytea", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_quote_request_files", x => x.quote_id);
                    table.ForeignKey(
                        name: "fk_quote_request_files_quotes_quote_id",
                        column: x => x.quote_id,
                        principalTable: "quotes",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "quote_request_files");

            migrationBuilder.DropColumn(
                name: "request_file_name",
                table: "quotes");

            migrationBuilder.DropColumn(
                name: "request_file_size",
                table: "quotes");

            migrationBuilder.DropColumn(
                name: "request_file_type",
                table: "quotes");

            migrationBuilder.DropColumn(
                name: "request_text",
                table: "quotes");
        }
    }
}
