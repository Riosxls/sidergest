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
    public void Zero_days_is_the_start_date_and_a_weekend_start_counts_from_the_next_working_day()
    {
        var saturday = new DateOnly(2026, 10, 24);
        Assert.Equal(saturday, WorkDays.Add(saturday, 0));
        Assert.Equal(new DateOnly(2026, 10, 26), WorkDays.Add(saturday, 1));
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
}
