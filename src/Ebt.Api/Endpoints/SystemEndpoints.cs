using System.Reflection;
using System.Security.Claims;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Api.Endpoints;

public record BackupStatus(bool Configured, string? Directory, int Count, DateTimeOffset? LastBackupAt, string? LastBackupFile, long? LastBackupSizeBytes);

public static class SystemEndpoints
{
    /// <summary>Looks at the folder the backup script writes to (mounted read-only into the API container) and reports the newest <c>ebt-*.dump</c>.</summary>
    public static BackupStatus ScanBackups(string? directory)
    {
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory)) return new BackupStatus(false, null, 0, null, null, null);
        var files = new DirectoryInfo(directory).GetFiles("ebt-*.dump").OrderByDescending(f => f.LastWriteTimeUtc).ToList();
        var last = files.FirstOrDefault();
        return new BackupStatus(true, null, files.Count, last is null ? null : new DateTimeOffset(last.LastWriteTimeUtc, TimeSpan.Zero), last?.Name, last?.Length);
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
