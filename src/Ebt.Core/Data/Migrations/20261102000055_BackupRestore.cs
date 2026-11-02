using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class BackupRestore : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "restore_file",
                table: "backup_settings",
                type: "character varying(120)",
                maxLength: 120,
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "restore_requested_at",
                table: "backup_settings",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.UpdateData(
                table: "backup_settings",
                keyColumn: "id",
                keyValue: 1,
                columns: new[] { "restore_file", "restore_requested_at" },
                values: new object[] { null, null });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "restore_file",
                table: "backup_settings");

            migrationBuilder.DropColumn(
                name: "restore_requested_at",
                table: "backup_settings");
        }
    }
}
