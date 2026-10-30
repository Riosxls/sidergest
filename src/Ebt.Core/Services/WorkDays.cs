namespace Ebt.Core.Services;

/// <summary>
/// Working-day calendar for delivery lead times. A working day is Monday to Friday that is not a national holiday;
/// state and municipal holidays are not known here. Keep in sync with <c>clients/flutter/lib/workdays.dart</c>.
/// </summary>
public static class WorkDays
{
    public static bool IsWorkDay(DateOnly d) => d.DayOfWeek is not (DayOfWeek.Saturday or DayOfWeek.Sunday) && !IsHoliday(d);

    /// <summary>The date <paramref name="days"/> working days after <paramref name="start"/> (day 0 is the start itself).</summary>
    public static DateOnly Add(DateOnly start, int days)
    {
        var d = start;
        while (days > 0)
        {
            d = d.AddDays(1);
            if (IsWorkDay(d)) days--;
        }
        return d;
    }

    /// <summary>Working days after <paramref name="start"/> up to and including <paramref name="end"/>; 0 when the end is not later.</summary>
    public static int Between(DateOnly start, DateOnly end)
    {
        var n = 0;
        for (var d = start; d < end;)
        {
            d = d.AddDays(1);
            if (IsWorkDay(d)) n++;
        }
        return n;
    }

    public static bool IsHoliday(DateOnly d)
    {
        if (d is { Month: 1, Day: 1 } or { Month: 4, Day: 21 } or { Month: 5, Day: 1 } or { Month: 9, Day: 7 } or { Month: 10, Day: 12 }
            or { Month: 11, Day: 2 } or { Month: 11, Day: 15 } or { Month: 12, Day: 25 }) return true;
        if (d is { Month: 11, Day: 20 } && d.Year >= 2024) return true;
        return d == Easter(d.Year).AddDays(-2); // Sexta-feira Santa
    }

    private static DateOnly Easter(int year)
    {
        int a = year % 19, b = year / 100, c = year % 100;
        int d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3;
        int h = (19 * a + b - d - g + 15) % 30;
        int i = c / 4, k = c % 4;
        int l = (32 + 2 * e + 2 * i - h - k) % 7;
        int m = (a + 11 * h + 22 * l) / 451;
        int month = (h + l - 7 * m + 114) / 31;
        int day = (h + l - 7 * m + 114) % 31 + 1;
        return new DateOnly(year, month, day);
    }
}
