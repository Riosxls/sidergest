using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Api.Endpoints;

public record BackupStatus(bool Configured, string? Directory, int Count, DateTimeOffset? LastBackupAt, string? LastBackupFile, long? LastBackupSizeBytes);

public static class SystemEndpoints
{
    /// <summary>What <c>scripts/backup.ps1</c> writes to <c>status.json</c> after each run.</summary>
    private record BackupStatusFile(int Count, DateTimeOffset? LastBackupAt, string? LastBackupFile, long? LastBackupSizeBytes);

    /// <summary>
    /// Reads <c>status.json</c> from the folder the backup script writes it to. Only that file is mounted (read-only) into the API container,
    /// never the dumps, so the API process cannot read the data they hold.
    /// </summary>
    public static BackupStatus ScanBackups(string? directory)
    {
        var none = new BackupStatus(false, null, 0, null, null, null);
        if (string.IsNullOrWhiteSpace(directory)) return none;
        var path = Path.Combine(directory, "status.json");
        if (!File.Exists(path)) return none;
        try
        {
            var s = JsonSerializer.Deserialize<BackupStatusFile>(File.ReadAllText(path), new JsonSerializerOptions(JsonSerializerDefaults.Web));
            return s is null ? none : new BackupStatus(true, null, s.Count, s.LastBackupAt, s.LastBackupFile, s.LastBackupSizeBytes);
        }
        catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException) { return none; }
    }

    public static void MapSystem(this WebApplication app)
    {
        app.MapGet("/api/system/about", async (EbtDbContext db, IWebHostEnvironment env, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            var info = typeof(Program).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? typeof(Program).Assembly.GetName().Version?.ToString() ?? "";
            var ok = false;
            string? last = null;
            try
            {
                ok = await db.Database.CanConnectAsync(ct);
                if (ok) last = (await db.Database.GetAppliedMigrationsAsync(ct)).LastOrDefault();
            }
            catch (Exception) when (!ct.IsCancellationRequested)
            {
                ok = false; // reported as databaseOk=false instead of a 500
            }
            // Environment, runtime and migration details are for admins; everyone else gets the version and the clock.
            var admin = principal.IsInRole(nameof(UserRole.Admin));
            return Results.Ok(new
            {
                version = info.Split('+')[0],
                runtime = admin ? System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription : null,
                environment = admin ? env.EnvironmentName : null,
                serverTime = DateTimeOffset.UtcNow,
                timeZone = TimeZoneInfo.Local.Id,
                lastMigration = admin ? last : null,
                databaseOk = ok
            });
        }).WithTags("System").RequireAuthorization(Policies.Read);

        app.MapGet("/api/admin/backup-status", (IConfiguration config) => Results.Ok(ScanBackups(config["Backup:Directory"])))
            .WithTags("System").RequireAuthorization(Policies.Admin);
    }
}
