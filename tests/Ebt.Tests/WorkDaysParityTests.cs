using Ebt.Core.Services;
using Xunit;

namespace Ebt.Tests;

/// <summary>
/// Checks <see cref="WorkDays"/> against <c>tests/fixtures/workdays_golden.txt</c>. The Flutter test
/// <c>workdays_parity_test.dart</c> checks <c>workdays.dart</c> against the same file, so the calendars cannot drift apart.
/// </summary>
public class WorkDaysParityTests
{
    private static string[] GoldenLines()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null && !File.Exists(Path.Combine(dir.FullName, "Ebt.sln"))) dir = dir.Parent;
        Assert.NotNull(dir);
        return File.ReadAllLines(Path.Combine(dir.FullName, "tests", "fixtures", "workdays_golden.txt"))
            .Where(l => l.Length > 0 && !l.StartsWith('#')).ToArray();
    }

    [Fact]
    public void Holidays_match_the_golden_file_for_2020_to_2040()
    {
        var golden = GoldenLines().Where(l => l.StartsWith("H ")).Select(l => DateOnly.Parse(l[2..])).ToHashSet();
        Assert.NotEmpty(golden);
        for (var d = new DateOnly(2020, 1, 1); d <= new DateOnly(2040, 12, 31); d = d.AddDays(1))
            Assert.True(WorkDays.IsHoliday(d) == golden.Contains(d), $"holiday mismatch on {d:yyyy-MM-dd}");
    }

    [Fact]
    public void Add_and_Between_match_the_golden_file()
    {
        foreach (var l in GoldenLines())
        {
            var p = l.Split(' ');
            if (p[0] == "A") Assert.True(DateOnly.Parse(p[3]) == WorkDays.Add(DateOnly.Parse(p[1]), int.Parse(p[2])), l);
            if (p[0] == "B") Assert.True(int.Parse(p[3]) == WorkDays.Between(DateOnly.Parse(p[1]), DateOnly.Parse(p[2])), l);
        }
    }
}
