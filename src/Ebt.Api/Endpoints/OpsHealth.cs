using System.Text.Json;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Api.Endpoints;

/// <summary>
/// Readiness for the operator and for <c>scripts/update.ps1</c>: <c>GET /health/ready</c> (anonymous, no secrets) answers 200 when the database is reachable and has no
/// pending migration and 503 otherwise. Backup problems (no recent backup, silent agent, failed run, failed restore drill) are warnings: they never turn it into 503,
/// but <see cref="AlertService"/> mails them. Read-only use of the backup settings row and of the files <c>scripts/*.ps1</c> write to <c>Backup:Directory</c>.
/// </summary>
public static class OpsHealth
{
    /// <summary>A backup older than this counts as stale while the automatic plan is on.</summary>
    public static readonly TimeSpan BackupStaleAfter = TimeSpan.FromHours(26);

    /// <summary>The agent heartbeat is written every minute; older than this the plan is not being carried out.</summary>
    public static readonly TimeSpan AgentSilentAfter = TimeSpan.FromMinutes(10);

    public record DrillStatus(bool Ok, DateTimeOffset? FinishedAt);

    public record BackupHealth(DateTimeOffset? LastOkAt, double? AgeHours, DateTimeOffset? AgentSeenAt, DrillStatus? Drill);

    /// <summary>Status is <c>ok</c>, <c>degraded</c> (ready, with warnings) or <c>unavailable</c>. Db is <c>ok</c> or <c>down</c>; PendingMigrations is null when the database cannot be asked.</summary>
    public record ReadyReport(string Status, string Db, int? PendingMigrations, BackupHealth Backup, IReadOnlyList<string> Warnings)
    {
        public bool Ready => Db == "ok" && PendingMigrations == 0;
    }

    private record DrillFile(bool Ok, DateTimeOffset? FinishedAt);

    /// <summary>Reads <c>drill.json</c> (written by <c>scripts/restore-drill.ps1</c>); null when there is none or it is unreadable.</summary>
    public static DrillStatus? ScanDrill(string? directory)
    {
        if (string.IsNullOrWhiteSpace(directory)) return null;
        var path = Path.Combine(directory, "drill.json");
        if (!File.Exists(path)) return null;
        try
        {
            var d = JsonSerializer.Deserialize<DrillFile>(File.ReadAllText(path), new JsonSerializerOptions(JsonSerializerDefaults.Web));
            return d is null ? null : new DrillStatus(d.Ok, d.FinishedAt);
        }
        catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException) { return null; }
    }

    /// <summary>The decision, free of I/O so it can be tested: what is wrong given the database state, the backup plan, status.json and drill.json.</summary>
    public static ReadyReport Evaluate(bool dbUp, int? pending, BackupSettings? plan, DateTimeOffset? statusLastBackupAt, DrillStatus? drill, DateTimeOffset now)
    {
        var warnings = new List<string>();
        var enabled = plan?.Enabled ?? false;
        var lastOk = statusLastBackupAt;
        if (plan is { LastRunOk: true, LastRunAt: { } ran } && (lastOk is null || ran > lastOk)) lastOk = ran;
        double? age = lastOk is { } t ? Math.Round((now - t).TotalHours, 1) : null;

        if (plan is { LastRunOk: false }) warnings.Add("backup_failed");
        if (enabled && (lastOk is null || now - lastOk.Value > BackupStaleAfter)) warnings.Add("backup_stale");
        if (enabled && (plan!.AgentSeenAt is null || now - plan.AgentSeenAt.Value > AgentSilentAfter)) warnings.Add("agent_silent");
        if (drill is { Ok: false }) warnings.Add("drill_failed");

        var ready = dbUp && pending == 0;
        var status = !ready ? "unavailable" : warnings.Count > 0 ? "degraded" : "ok";
        return new ReadyReport(status, dbUp ? "ok" : "down", pending, new BackupHealth(lastOk, age, plan?.AgentSeenAt, drill), warnings);
    }

    /// <summary>Asks the database and reads the backup files. Never throws: an unreachable database is reported as <c>down</c>.</summary>
    public static async Task<ReadyReport> EvaluateAsync(EbtDbContext db, IConfiguration config, DateTimeOffset now, CancellationToken ct)
    {
        var dir = config["Backup:Directory"];
        var drill = ScanDrill(dir);
        var statusAt = SystemEndpoints.ScanBackups(dir).LastBackupAt;
        try
        {
            if (!await db.Database.CanConnectAsync(ct)) return Evaluate(false, null, null, statusAt, drill, now);
            var pending = (await db.Database.GetPendingMigrationsAsync(ct)).Count();
            var plan = await db.BackupSettings.AsNoTracking().SingleOrDefaultAsync(x => x.Id == 1, ct);
            return Evaluate(true, pending, plan, statusAt, drill, now);
        }
        catch (Exception e) when (e is not OperationCanceledException) { return Evaluate(false, null, null, statusAt, drill, now); }
    }

    public static void MapOpsHealth(this WebApplication app) =>
        app.MapGet("/health/ready", async (EbtDbContext db, IConfiguration config, CancellationToken ct) =>
        {
            var report = await EvaluateAsync(db, config, DateTimeOffset.UtcNow, ct);
            return Results.Json(report, new JsonSerializerOptions(JsonSerializerDefaults.Web), statusCode: report.Ready ? StatusCodes.Status200OK : StatusCodes.Status503ServiceUnavailable);
        }).AllowAnonymous().ExcludeFromDescription();
}
