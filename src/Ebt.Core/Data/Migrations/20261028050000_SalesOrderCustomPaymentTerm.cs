using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    [DbContext(typeof(EbtDbContext))]
    [Migration("20261028050000_SalesOrderCustomPaymentTerm")]
    public class SalesOrderCustomPaymentTerm : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(name: "custom_payment_term", table: "sales_orders", type: "text", nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(name: "custom_payment_term", table: "sales_orders");
        }
    }
}
