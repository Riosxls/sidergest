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
    DateTimeOffset? RunRequestedAt, DateTimeOffset? CancelRequestedAt, DateTimeOffset? LastRunAt, bool? LastRunOk, string? LastRunMessage, DateTimeOffset? AgentSeenAt, DateTimeOffset? NextRunAt, SystemEndpoints.BackupProgress? Progress)
{
    public static BackupSettingsDto From(BackupSettings s, SystemEndpoints.BackupProgress? progress) => new(s.Enabled, s.Frequency.ToString(), s.TimeOfDay.ToString("HH:mm"), (int)s.Weekday, s.Destination, s.Keep,
        s.RunRequestedAt, s.CancelRequestedAt, s.LastRunAt, s.LastRunOk, s.LastRunMessage, s.AgentSeenAt, BackupSchedule.NextRun(s, DateTimeOffset.UtcNow), progress);
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

    /// <summary>What <c>scripts/backup.ps1</c> writes to <c>progress.json</c> while it runs.</summary>
    public record BackupProgress(bool Running, int Percent, string? Stage, DateTimeOffset? StartedAt, DateTimeOffset? UpdatedAt);

    /// <summary>A running backup that has not updated its file for this long is treated as dead (crashed script, computer asleep).</summary>
    public static readonly TimeSpan ProgressStaleAfter = TimeSpan.FromSeconds(90);

    /// <summary>
    /// Reads <c>progress.json</c> next to <c>status.json</c>. Null when there is none; a "running" file that stopped updating is reported as not running.
    /// </summary>
    public static BackupProgress? ScanProgress(string? directory, DateTimeOffset? now = null)
    {
        if (string.IsNullOrWhiteSpace(directory)) return null;
        var path = Path.Combine(directory, "progress.json");
        if (!File.Exists(path)) return null;
        try
        {
            var p = JsonSerializer.Deserialize<BackupProgress>(File.ReadAllText(path), new JsonSerializerOptions(JsonSerializerDefaults.Web));
            if (p is null) return null;
            var percent = Math.Clamp(p.Percent, 0, 100);
            var stale = p.Running && (p.UpdatedAt is null || (now ?? DateTimeOffset.UtcNow) - p.UpdatedAt.Value > ProgressStaleAfter);
            return p with { Percent = percent, Running = p.Running && !stale };
        }
        catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException) { return null; }
    }

    /// <summary>One dump the agent lists in <c>backups.json</c>; location is local, destination or both.</summary>
    public record BackupItem(string Name, long SizeBytes, DateTimeOffset? CreatedAt, string? Location, bool HasChecksum);
    private record BackupListFile(DateTimeOffset? ListedAt, List<BackupItem>? Items);

    /// <summary>What the agent writes to <c>restore-result.json</c> when a restore ends.</summary>
    public record RestoreResult(bool Ok, string? Message, string? File, string? SafetyDump, DateTimeOffset? FinishedAt);
    public record RestoreState(DateTimeOffset? RequestedAt, string? File, RestoreResult? Result);
    public record BackupListResponse(List<BackupItem> Items, DateTimeOffset? ListedAt, RestoreState Restore);
    public record RestoreRequest(string? File, string? Confirm);

    private static readonly System.Text.RegularExpressions.Regex DumpName = new("^ebt-[A-Za-z0-9-]+-[0-9]{8}-[0-9]{6}[.]dump$", System.Text.RegularExpressions.RegexOptions.CultureInvariant);

    private static T? ReadAgentFile<T>(string? directory, string name) where T : class
    {
        if (string.IsNullOrWhiteSpace(directory)) return null;
        var path = Path.Combine(directory, name);
        if (!File.Exists(path)) return null;
        try { return JsonSerializer.Deserialize<T>(File.ReadAllText(path), new JsonSerializerOptions(JsonSerializerDefaults.Web)); }
        catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException) { return null; }
    }

    /// <summary>The dumps listed in <c>backups.json</c>, newest first; empty when the file is missing or invalid.</summary>
    public static (List<BackupItem> Items, DateTimeOffset? ListedAt) ScanBackupList(string? directory)
    {
        var f = ReadAgentFile<BackupListFile>(directory, "backups.json");
        var items = (f?.Items ?? []).Where(i => i is not null && !string.IsNullOrWhiteSpace(i.Name)).OrderByDescending(i => i.CreatedAt ?? DateTimeOffset.MinValue).ThenByDescending(i => i.Name, StringComparer.Ordinal).ToList();
        return (items, f?.ListedAt);
    }

    public static RestoreResult? ScanRestoreResult(string? directory) => ReadAgentFile<RestoreResult>(directory, "restore-result.json");

    private static bool RestorePending(BackupSettings s, RestoreResult? result) =>
        s.RestoreRequestedAt is not null && (result?.FinishedAt is null || result.FinishedAt <= s.RestoreRequestedAt);

    private static BackupListResponse BackupList(BackupSettings s, string? directory)
    {
        var (items, listedAt) = ScanBackupList(directory);
        return new BackupListResponse(items, listedAt, new RestoreState(s.RestoreRequestedAt, s.RestoreFile, ScanRestoreResult(directory)));
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
        backup.MapGet("/", async (EbtDbContext db, IConfiguration config, CancellationToken ct) => Results.Ok(BackupSettingsDto.From(await LoadBackupSettings(db, ct), ScanProgress(config["Backup:Directory"]))));
        backup.MapPut("/", async (BackupSettingsInput i, EbtDbContext db, IConfiguration config, CancellationToken ct) =>
        {
            var errors = Errors()
                .Require(Enum.TryParse<BackupFrequency>(i.Frequency, out _) && Enum.IsDefined(Enum.Parse<BackupFrequency>(i.Frequency!)), "frequency", "Hourly, Every6Hours, Daily or Weekly")
                .Require(TimeOnly.TryParseExact(i.TimeOfDay, "HH:mm", out _), "timeOfDay", "Use HH:mm, for example 22:00")
                .Require(i.Weekday is >= 0 and <= 6, "weekday", "Between 0 (Sunday) and 6 (Saturday)")
                .Require(i.Keep is >= 1 and <= 365, "keep", "Between 1 and 365");
            if (i.Enabled && string.IsNullOrWhiteSpace(i.Destination)) errors.Require(false, "destination", "Choose the destination folder before turning on automatic backup");
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
            return Results.Ok(BackupSettingsDto.From(s, ScanProgress(config["Backup:Directory"])));
        });
        backup.MapPost("/cancel", async (EbtDbContext db, IConfiguration config, CancellationToken ct) =>
        {
            var s = await LoadBackupSettings(db, ct);
            var progress = ScanProgress(config["Backup:Directory"]);
            var waiting = s.RunRequestedAt is not null && (s.LastRunAt is null || s.RunRequestedAt > s.LastRunAt);
            if (progress is { Running: true } || waiting)
            {
                s.CancelRequestedAt = DateTimeOffset.UtcNow;
                if (waiting) s.RunRequestedAt = null; // not started yet: drop the request; a run that just started sees this and stops
                await db.SaveChangesAsync(ct);
            }
            return Results.Ok(BackupSettingsDto.From(s, progress));
        });
        backup.MapPost("/run-now", async (EbtDbContext db, IConfiguration config, CancellationToken ct) =>
        {
            var s = await LoadBackupSettings(db, ct);
            if (string.IsNullOrWhiteSpace(s.Destination)) return Results.ValidationProblem(Errors().Require(false, "destination", "Choose the destination folder before running a backup"));
            s.RunRequestedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
            return Results.Ok(BackupSettingsDto.From(s, ScanProgress(config["Backup:Directory"])));
        });

        var backups = app.MapGroup("/api/admin/backups").WithTags("System").RequireAuthorization(Policies.Admin);
        backups.MapGet("/", async (EbtDbContext db, IConfiguration config, CancellationToken ct) => Results.Ok(BackupList(await LoadBackupSettings(db, ct), config["Backup:Directory"])));
        backups.MapPost("/restore", async (RestoreRequest r, EbtDbContext db, IConfiguration config, CancellationToken ct) =>
        {
            var dir = config["Backup:Directory"];
            var (items, _) = ScanBackupList(dir);
            var name = r.File?.Trim() ?? "";
            var shaped = DumpName.IsMatch(name);
            var errors = Errors()
                .Require(shaped, "file", "Not a backup file name")
                .Require(!shaped || items.Any(i => i.Name == name), "file", "Backup not found in the list published by the backup agent")
                .Require(r.Confirm == "RESTAURAR", "confirm", "Type RESTAURAR to confirm");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var s = await LoadBackupSettings(db, ct);
            if (ScanProgress(dir) is { Running: true }) return Results.Problem("A backup or restore is running; wait for it to finish", statusCode: StatusCodes.Status409Conflict);
            if (RestorePending(s, ScanRestoreResult(dir))) return Results.Problem("A restore is already requested and has not finished", statusCode: StatusCodes.Status409Conflict);
            s.RestoreFile = name;
            s.RestoreRequestedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
            return Results.Json(BackupList(s, dir), new JsonSerializerOptions(JsonSerializerDefaults.Web), statusCode: StatusCodes.Status202Accepted);
        });
        backups.MapPost("/restore/cancel", async (EbtDbContext db, IConfiguration config, CancellationToken ct) =>
        {
            var dir = config["Backup:Directory"];
            var s = await LoadBackupSettings(db, ct);
            if (RestorePending(s, ScanRestoreResult(dir)))
            {
                if (ScanProgress(dir) is { Running: true }) return Results.Problem("The restore is already running and cannot be cancelled", statusCode: StatusCodes.Status409Conflict);
                s.RestoreFile = null;
                s.RestoreRequestedAt = null;
                await db.SaveChangesAsync(ct);
            }
            return Results.Ok(BackupList(s, dir));
        });
    }

    private static async Task<BackupSettings> LoadBackupSettings(EbtDbContext db, CancellationToken ct) =>
        await db.BackupSettings.SingleOrDefaultAsync(x => x.Id == 1, ct) ?? db.BackupSettings.Add(new BackupSettings { Id = 1 }).Entity;
}
