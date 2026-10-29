using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class CustomerCompanyData : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "city",
                table: "customers",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "complement",
                table: "customers",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "contact",
                table: "customers",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "district",
                table: "customers",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "document",
                table: "customers",
                type: "character varying(14)",
                maxLength: 14,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "email",
                table: "customers",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "icms_contributor",
                table: "customers",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "number",
                table: "customers",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "phone",
                table: "customers",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "state_registration",
                table: "customers",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "street",
                table: "customers",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "uf",
                table: "customers",
                type: "character varying(2)",
                maxLength: 2,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "zip_code",
                table: "customers",
                type: "character varying(8)",
                maxLength: 8,
                nullable: true);

            // Seed the company data from each customer's first (default) address; edited independently afterwards.
            migrationBuilder.Sql(@"
                UPDATE customers c SET
                    document = a.document, state_registration = a.state_registration, icms_contributor = a.icms_contributor,
                    street = a.street, number = a.number, complement = a.complement, district = a.district, city = a.city,
                    uf = a.uf, zip_code = a.zip_code, contact = a.buyer, email = a.email, phone = a.phone
                FROM (SELECT DISTINCT ON (customer_id) * FROM customer_addresses ORDER BY customer_id, legacy_code, id) a
                WHERE a.customer_id = c.id;");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "city",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "complement",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "contact",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "district",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "document",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "email",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "icms_contributor",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "number",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "phone",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "state_registration",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "street",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "uf",
                table: "customers");

            migrationBuilder.DropColumn(
                name: "zip_code",
                table: "customers");
        }
    }
}
