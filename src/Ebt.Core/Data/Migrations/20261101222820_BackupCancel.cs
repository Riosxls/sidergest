using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class BackupCancel : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "cancel_requested_at",
                table: "backup_settings",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.UpdateData(
                table: "backup_settings",
                keyColumn: "id",
                keyValue: 1,
                column: "cancel_requested_at",
                value: null);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "cancel_requested_at",
                table: "backup_settings");
        }
    }
}
