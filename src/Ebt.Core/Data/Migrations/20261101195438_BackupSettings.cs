using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class BackupSettings : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "backup_settings",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    enabled = table.Column<bool>(type: "boolean", nullable: false),
                    frequency = table.Column<int>(type: "integer", nullable: false),
                    time_of_day = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    weekday = table.Column<int>(type: "integer", nullable: false),
                    destination = table.Column<string>(type: "character varying(260)", maxLength: 260, nullable: true),
                    keep = table.Column<int>(type: "integer", nullable: false),
                    run_requested_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    last_run_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    last_run_ok = table.Column<bool>(type: "boolean", nullable: true),
                    last_run_message = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    agent_seen_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_backup_settings", x => x.id);
                    table.CheckConstraint("ck_backup_settings_keep", "keep >= 1 AND keep <= 365");
                });

            migrationBuilder.InsertData(
                table: "backup_settings",
                columns: new[] { "id", "agent_seen_at", "destination", "enabled", "frequency", "keep", "last_run_at", "last_run_message", "last_run_ok", "run_requested_at", "time_of_day", "weekday" },
                values: new object[] { 1, null, null, false, 2, 14, null, null, null, null, new TimeOnly(22, 0, 0), 0 });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "backup_settings");
        }
    }
}
