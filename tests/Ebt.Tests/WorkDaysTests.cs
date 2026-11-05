using Ebt.Core.Services;
using Xunit;

namespace Ebt.Tests;

public class WorkDaysTests
{
    [Fact]
    public void Weekends_are_skipped()
    {
        var friday = new DateOnly(2026, 10, 30);
        Assert.Equal(new DateOnly(2026, 11, 3), WorkDays.Add(friday, 1)); // Mon 2 Nov is Finados, so Tuesday
        Assert.Equal(new DateOnly(2026, 11, 9), WorkDays.Add(new DateOnly(2026, 11, 3), 4)); // Tue + 4 working days
    }

    [Fact]
    public void Zero_days_is_the_start_date_on_a_working_day_and_rolls_forward_from_a_weekend_or_holiday()
    {
        var saturday = new DateOnly(2026, 10, 24);
        var monday = new DateOnly(2026, 10, 26);
        Assert.Equal(monday, WorkDays.Add(saturday, 0)); // never a non-working day
        Assert.Equal(monday, WorkDays.Add(monday, 0));
        Assert.Equal(monday, WorkDays.Add(saturday, 1));
        Assert.Equal(new DateOnly(2026, 11, 3), WorkDays.Add(new DateOnly(2026, 11, 2), 0)); // Finados (holiday) -> next working day
        Assert.Equal(monday, WorkDays.Add(saturday, -5)); // negative counts as 0
    }

    [Fact]
    public void National_holidays_are_skipped_including_good_friday()
    {
        Assert.True(WorkDays.IsHoliday(new DateOnly(2026, 4, 3))); // Sexta-feira Santa 2026
        Assert.True(WorkDays.IsHoliday(new DateOnly(2026, 9, 7)));
        Assert.True(WorkDays.IsHoliday(new DateOnly(2026, 11, 20)));
        Assert.False(WorkDays.IsHoliday(new DateOnly(2023, 11, 20))); // not national before 2024
        Assert.Equal(new DateOnly(2026, 4, 6), WorkDays.Add(new DateOnly(2026, 4, 2), 1)); // Thu -> skip Good Friday and weekend
    }

    [Fact]
    public void Between_is_the_inverse_of_add()
    {
        var start = new DateOnly(2026, 10, 30);
        for (var n = 0; n <= 40; n++) Assert.Equal(n, WorkDays.Between(start, WorkDays.Add(start, n)));
        Assert.Equal(0, WorkDays.Between(start, start.AddDays(-3)));
    }

    [Fact]
    public void A_huge_input_is_capped_instead_of_walking_millions_of_days()
    {
        var start = new DateOnly(2026, 10, 30);
        var sw = System.Diagnostics.Stopwatch.StartNew();
        var end = WorkDays.Add(start, int.MaxValue);
        Assert.True(WorkDays.Between(start, DateOnly.MaxValue) > 0);
        Assert.True(sw.ElapsedMilliseconds < 2000);
        Assert.True(end > start);
    }
}
