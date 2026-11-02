using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class BackupKeepCap : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Clamp before the stricter constraint is added; a plan that already keeps 5 or fewer is left alone.
            migrationBuilder.Sql("UPDATE backup_settings SET keep = 5 WHERE keep > 5;");

            migrationBuilder.DropCheckConstraint(
                name: "ck_backup_settings_keep",
                table: "backup_settings");

            migrationBuilder.AddColumn<string>(
                name: "delete_file",
                table: "backup_settings",
                type: "character varying(120)",
                maxLength: 120,
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "delete_requested_at",
                table: "backup_settings",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddCheckConstraint(
                name: "ck_backup_settings_keep",
                table: "backup_settings",
                sql: "keep >= 1 AND keep <= 5");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_backup_settings_keep",
                table: "backup_settings");

            migrationBuilder.DropColumn(
                name: "delete_file",
                table: "backup_settings");

            migrationBuilder.DropColumn(
                name: "delete_requested_at",
                table: "backup_settings");

            migrationBuilder.AddCheckConstraint(
                name: "ck_backup_settings_keep",
                table: "backup_settings",
                sql: "keep >= 1 AND keep <= 365");
        }
    }
}
