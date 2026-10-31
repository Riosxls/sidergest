using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class AuditUserIndex : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "ix_audit_log_user_at",
                table: "audit_log",
                columns: new[] { "user", "at" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_audit_log_user_at",
                table: "audit_log");
        }
    }
}
