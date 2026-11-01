using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Maintenance;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record BackupStatus(bool Configured, string? Directory, int Count, DateTimeOffset? LastBackupAt, string? LastBackupFile, long? LastBackupSizeBytes);


/// <summary>What the app sends to change the backup plan. Frequency is the <see cref="BackupFrequency"/> name, time is HH:mm, weekday 0 = Sunday.</summary>
public record BackupSettingsInput(bool Enabled, string? Frequency, string? TimeOfDay, int Weekday, string? Destination, int Keep);

/// <summary>The backup plan plus what the agent on the server computer reported back.</summary>
public record BackupSettingsDto(bool Enabled, string Frequency, string TimeOfDay, int Weekday, string? Destination, int Keep,
    DateTimeOffset? RunRequestedAt, DateTimeOffset? LastRunAt, bool? LastRunOk, string? LastRunMessage, DateTimeOffset? AgentSeenAt, DateTimeOffset? NextRunAt)
{
    public static BackupSettingsDto From(BackupSettings s) => new(s.Enabled, s.Frequency.ToString(), s.TimeOfDay.ToString("HH:mm"), (int)s.Weekday, s.Destination, s.Keep,
        s.RunRequestedAt, s.LastRunAt, s.LastRunOk, s.LastRunMessage, s.AgentSeenAt, BackupSchedule.NextRun(s, DateTimeOffset.UtcNow));
}
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

        var backup = app.MapGroup("/api/admin/backup-settings").WithTags("System").RequireAuthorization(Policies.Admin);
        backup.MapGet("/", async (EbtDbContext db, CancellationToken ct) => Results.Ok(BackupSettingsDto.From(await LoadBackupSettings(db, ct))));
        backup.MapPut("/", async (BackupSettingsInput i, EbtDbContext db, CancellationToken ct) =>
        {
            var errors = Errors()
                .Require(Enum.TryParse<BackupFrequency>(i.Frequency, out _) && Enum.IsDefined(Enum.Parse<BackupFrequency>(i.Frequency!)), "frequency", "Hourly, Every6Hours, Daily or Weekly")
                .Require(TimeOnly.TryParseExact(i.TimeOfDay, "HH:mm", out _), "timeOfDay", "Use HH:mm, for example 22:00")
                .Require(i.Weekday is >= 0 and <= 6, "weekday", "Between 0 (Sunday) and 6 (Saturday)")
                .Require(i.Keep is >= 1 and <= 365, "keep", "Between 1 and 365");
            if (BackupSchedule.DestinationError(i.Destination) is { } why) errors.Require(false, "destination", why);
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var s = await LoadBackupSettings(db, ct);
            s.Enabled = i.Enabled;
            s.Frequency = Enum.Parse<BackupFrequency>(i.Frequency!);
            s.TimeOfDay = TimeOnly.ParseExact(i.TimeOfDay!, "HH:mm");
            s.Weekday = (DayOfWeek)i.Weekday;
            s.Destination = string.IsNullOrWhiteSpace(i.Destination) ? null : i.Destination.Trim();
            s.Keep = i.Keep;
            await db.SaveChangesAsync(ct);
            return Results.Ok(BackupSettingsDto.From(s));
        });
        backup.MapPost("/run-now", async (EbtDbContext db, CancellationToken ct) =>
        {
            var s = await LoadBackupSettings(db, ct);
            s.RunRequestedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
            return Results.Ok(BackupSettingsDto.From(s));
        });
    }

    private static async Task<BackupSettings> LoadBackupSettings(EbtDbContext db, CancellationToken ct) =>
        await db.BackupSettings.SingleOrDefaultAsync(x => x.Id == 1, ct) ?? db.BackupSettings.Add(new BackupSettings { Id = 1 }).Entity;
}
