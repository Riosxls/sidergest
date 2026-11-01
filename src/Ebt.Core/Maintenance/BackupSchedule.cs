using Ebt.Core.Entities;
using Ebt.Core.Services;

namespace Ebt.Core.Maintenance;

/// <summary>
/// When the next automatic backup is due. <c>scripts/backup-agent.ps1</c> applies the same rules on the server computer;
/// keep the two in sync. Daily and weekly times are wall-clock times in the business zone (<see cref="Clock"/>).
/// </summary>
public static class BackupSchedule
{
    /// <summary>
    /// The instant the next backup is due: now when the app asked for one or nothing ran yet, null when automatic backup is off
    /// and no run was requested. A run request wins even while automatic backup is off.
    /// </summary>
    public static DateTimeOffset? NextRun(BackupSettings s, DateTimeOffset now)
    {
        if (s.RunRequestedAt is { } asked && (s.LastRunAt is null || asked > s.LastRunAt)) return now;
        if (!s.Enabled) return null;
        if (s.LastRunAt is not { } last) return now;
        var due = s.Frequency switch
        {
            BackupFrequency.Hourly => last.AddHours(1),
            BackupFrequency.Every6Hours => last.AddHours(6),
            BackupFrequency.Daily => SlotAfter(last, s.TimeOfDay, null),
            _ => SlotAfter(last, s.TimeOfDay, s.Weekday),
        };
        return due < now ? now : due;
    }

    /// <summary>The first wall-clock slot (time of day, optionally on a weekday) strictly after <paramref name="after"/>.</summary>
    private static DateTimeOffset SlotAfter(DateTimeOffset after, TimeOnly time, DayOfWeek? weekday)
    {
        var local = Clock.ToLocal(after);
        var day = DateOnly.FromDateTime(local);
        for (var i = 0; i <= 8; i++)
        {
            var d = day.AddDays(i);
            if (weekday is { } w && d.DayOfWeek != w) continue;
            var slot = Clock.FromLocal(d.ToDateTime(time));
            if (slot > after) return slot;
        }
        return after.AddDays(7); // unreachable: a slot always exists within 8 days
    }

    /// <summary>Why a destination is refused, or null when it is acceptable (empty means "keep on this computer only").</summary>
    public static string? DestinationError(string? destination)
    {
        if (string.IsNullOrWhiteSpace(destination)) return null;
        var d = destination.Trim();
        if (d.Length > 260) return "At most 260 characters";
        if (d.Any(char.IsControl) || d.IndexOfAny(['"', '*', '?', '<', '>', '|']) >= 0) return "Contains characters that are not allowed in a path";
        const char Bs = '\u005c';
        if (d.Split(Bs, '/').Contains("..")) return "Must not contain '..'";
        var drive = d.Length >= 3 && char.IsAsciiLetter(d[0]) && d[1] == ':' && (d[2] == Bs || d[2] == '/');
        var unc = d.Length > 4 && d[0] == Bs && d[1] == Bs && d[2] != '.' && d[2] != '?';
        return drive || unc ? null : "Use a full path such as D:\u005cbackups\u005cmetagest or \u005c\u005cserver\u005cbackups";
    }
}
