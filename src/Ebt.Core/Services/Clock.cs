namespace Ebt.Core.Services;

/// <summary>Business-day clock. Uses a fixed zone so "today" does not depend on the server's local timezone.</summary>
public static class Clock
{
    private static TimeZoneInfo zone = Resolve("America/Sao_Paulo");

    public static void Configure(string? zoneId)
    {
        if (!string.IsNullOrWhiteSpace(zoneId)) zone = Resolve(zoneId.Trim());
    }

    public static DateOnly Today() => DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, zone).DateTime);

    /// <summary>The calendar day of an instant in the business zone.</summary>
    public static DateOnly DateOf(DateTimeOffset at) => DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(at, zone).DateTime);

    private static TimeZoneInfo Resolve(string id)
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById(id); }
        catch (Exception e) when (e is TimeZoneNotFoundException or InvalidTimeZoneException)
        {
            return TimeZoneInfo.CreateCustomTimeZone("fallback-utc-3", TimeSpan.FromHours(-3), "UTC-3", "UTC-3");
        }
    }
}
