namespace Ebt.Core.Entities;

/// <summary>How often the automatic database backup runs.</summary>
public enum BackupFrequency { Hourly = 0, Every6Hours = 1, Daily = 2, Weekly = 3 }

/// <summary>
/// The single row (Id 1) that tells the backup agent on the server computer what to do. The API container cannot run
/// <c>pg_dump</c> itself, so the app only stores the wish; <c>scripts/backup-agent.ps1</c> reads this row, runs the backup
/// and writes the <c>LastRun*</c> and <c>AgentSeenAt</c> columns back.
/// </summary>
public class BackupSettings
{
    public int Id { get; set; }
    public bool Enabled { get; set; }
    public BackupFrequency Frequency { get; set; } = BackupFrequency.Daily;
    /// <summary>Local (business-zone) time of day for daily and weekly backups.</summary>
    public TimeOnly TimeOfDay { get; set; } = new(22, 0);
    /// <summary>Day of the week for weekly backups.</summary>
    public DayOfWeek Weekday { get; set; } = DayOfWeek.Sunday;
    /// <summary>Folder, drive or share where each dump is also copied; null keeps it on the server computer only.</summary>
    public string? Destination { get; set; }
    /// <summary>How many dumps to keep in the local folder.</summary>
    public int Keep { get; set; } = 14;
    /// <summary>Set by "Fazer backup agora"; the agent runs as soon as this is newer than <see cref="LastRunAt"/>.</summary>
    public DateTimeOffset? RunRequestedAt { get; set; }
    public DateTimeOffset? LastRunAt { get; set; }
    public bool? LastRunOk { get; set; }
    public string? LastRunMessage { get; set; }
    /// <summary>Heartbeat of the agent; the app warns when it is old, because then nothing runs the backups.</summary>
    public DateTimeOffset? AgentSeenAt { get; set; }
}
