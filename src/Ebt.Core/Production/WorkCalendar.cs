namespace Ebt.Core.Production;

/// <summary>Working-day calendar of the shop floor: hours per day, optional Saturdays and a holiday set.</summary>
public sealed class WorkCalendar(decimal hoursPerDay, bool workSaturdays, IReadOnlySet<DateOnly> holidays)
{
    public decimal HoursPerDay { get; } = hoursPerDay;

    public bool IsWorkingDay(DateOnly d) => d.DayOfWeek != DayOfWeek.Sunday && (workSaturdays || d.DayOfWeek != DayOfWeek.Saturday) && !holidays.Contains(d);

    public DateOnly OnOrBefore(DateOnly d)
    {
        for (var i = 0; i < 400 && !IsWorkingDay(d); i++) d = d.AddDays(-1);
        return d;
    }

    public DateOnly OnOrAfter(DateOnly d)
    {
        for (var i = 0; i < 400 && !IsWorkingDay(d); i++) d = d.AddDays(1);
        return d;
    }

    public DateOnly Previous(DateOnly d) => OnOrBefore(d.AddDays(-1));
    public DateOnly Next(DateOnly d) => OnOrAfter(d.AddDays(1));

    public static DateOnly WeekStart(DateOnly d) => d.AddDays(-(((int)d.DayOfWeek + 6) % 7));
}
