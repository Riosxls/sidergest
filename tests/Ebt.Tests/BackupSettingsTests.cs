using System.Net;
using System.Net.Http.Json;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Ebt.Core.Maintenance;
using Ebt.Core.Services;

namespace Ebt.Tests;

[Collection("api")]
public class BackupSettingsTests(ApiFixture api)
{
    private const string Url = "/api/admin/backup-settings";
    private static readonly char Bs = '\u005c';

    private static BackupSettingsInput Valid(string? destination = null, string frequency = "Daily") =>
        new(true, frequency, "22:30", 3, destination ?? ("C:" + Bs + "backups"), 4);

    [Fact]
    public async Task Settings_are_admin_only()
    {
        var reader = await api.UserAsync(UserRole.Reader);
        Assert.Equal(HttpStatusCode.Forbidden, (await reader.GetAsync(Url)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await reader.PostAsync(Url + "/run-now", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().GetAsync(Url)).StatusCode);
    }

    [Fact]
    public async Task Settings_round_trip_with_a_destination()
    {
        var admin = await api.AdminAsync();
        var dest = "D:" + Bs + "backups" + Bs + "metagest";
        var put = await admin.PutAsJsonAsync(Url, Valid(dest, "Weekly"));
        put.EnsureSuccessStatusCode();
        var s = await admin.GetFromJsonAsync<BackupSettingsDto>(Url, ApiFixture.Json);
        Assert.True(s!.Enabled);
        Assert.Equal("Weekly", s.Frequency);
        Assert.Equal("22:30", s.TimeOfDay);
        Assert.Equal(3, s.Weekday);
        Assert.Equal(dest, s.Destination);
        Assert.Equal(4, s.Keep);
        Assert.NotNull(s.NextRunAt); // nothing ran yet, so it is due now
    }

    [Theory]
    [InlineData("Monthly", "22:00", 0, 5, null, "frequency")]
    [InlineData("Daily", "25:00", 0, 5, null, "timeOfDay")]
    [InlineData("Daily", "22:00", 7, 5, null, "weekday")]
    [InlineData("Daily", "22:00", 0, 0, null, "keep")]
    [InlineData("Daily", "22:00", 0, 6, null, "keep")]
    [InlineData("Daily", "22:00", 0, 5, "backups", "destination")]
    [InlineData("Daily", "22:00", 0, 5, "D:/x/../y", "destination")]
    [InlineData("Daily", "22:00", 0, 5, "D:/x*", "destination")]
    public async Task Invalid_settings_are_refused(string frequency, string time, int weekday, int keep, string? destination, string field)
    {
        var res = await (await api.AdminAsync()).PutAsJsonAsync(Url, new BackupSettingsInput(true, frequency, time, weekday, destination, keep));
        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
        Assert.Contains($"\"{field}\"", await res.Content.ReadAsStringAsync());
    }

    [Theory]
    [InlineData(1)]
    [InlineData(5)]
    public async Task The_keep_boundaries_are_accepted(int keep)
    {
        var res = await (await api.AdminAsync()).PutAsJsonAsync(Url, Valid() with { Keep = keep });
        res.EnsureSuccessStatusCode();
        Assert.Equal(keep, (await res.Read<BackupSettingsDto>()).Keep);
    }

    [Fact]
    public async Task Run_now_records_the_request()
    {
        var admin = await api.AdminAsync();
        (await admin.PutAsJsonAsync(Url, Valid(null))).EnsureSuccessStatusCode();
        var s = await (await admin.PostAsync(Url + "/run-now", null)).Read<BackupSettingsDto>();
        Assert.NotNull(s.RunRequestedAt);
        Assert.NotNull(s.Destination);
        Assert.InRange((DateTimeOffset.UtcNow - s.RunRequestedAt!.Value).TotalMinutes, -1, 1);
    }

    [Theory]
    [InlineData("D:" + "\u005c" + "backups", true)]
    [InlineData("d:/backups", true)]
    [InlineData("\u005c\u005cserver\u005cshare\u005cmetagest", true)]
    [InlineData("", true)]
    [InlineData(null, true)]
    [InlineData("backups", false)]
    [InlineData("\u005c\u005c.\u005cpipe\u005cx", false)]
    [InlineData("D:" + "\u005c" + "a" + "\u005c" + ".." + "\u005c" + "b", false)]
    [InlineData("D:" + "\u005c" + "a|b", false)]
    public void Destination_rules(string? destination, bool ok) => Assert.Equal(ok, BackupSchedule.DestinationError(destination) is null);

    private static BackupSettings Plan(BackupFrequency f, DateTimeOffset? last, bool enabled = true) =>
        new() { Enabled = enabled, Frequency = f, TimeOfDay = new TimeOnly(22, 0), Weekday = DayOfWeek.Sunday, LastRunAt = last };

    [Fact]
    public void Next_run_follows_the_frequency()
    {
        var last = Clock.FromLocal(new DateTime(2026, 11, 4, 22, 0, 0)); // a Wednesday evening
        var early = last.AddMinutes(1);
        Assert.Equal(last.AddHours(1), BackupSchedule.NextRun(Plan(BackupFrequency.Hourly, last), early));
        Assert.Equal(last.AddHours(6), BackupSchedule.NextRun(Plan(BackupFrequency.Every6Hours, last), early));
        Assert.Equal(Clock.FromLocal(new DateTime(2026, 11, 5, 22, 0, 0)), BackupSchedule.NextRun(Plan(BackupFrequency.Daily, last), early));
        Assert.Equal(Clock.FromLocal(new DateTime(2026, 11, 8, 22, 0, 0)), BackupSchedule.NextRun(Plan(BackupFrequency.Weekly, last), early)); // Sunday
    }

    [Fact]
    public void A_missed_slot_is_due_now_and_a_first_run_is_due_now()
    {
        var now = DateTimeOffset.UtcNow;
        Assert.Equal(now, BackupSchedule.NextRun(Plan(BackupFrequency.Daily, now.AddDays(-5)), now));
        Assert.Equal(now, BackupSchedule.NextRun(Plan(BackupFrequency.Daily, null), now));
    }

    [Fact]
    public void Disabled_means_never_unless_a_run_was_requested()
    {
        var now = DateTimeOffset.UtcNow;
        var s = Plan(BackupFrequency.Daily, now.AddHours(-1), enabled: false);
        Assert.Null(BackupSchedule.NextRun(s, now));
        s.RunRequestedAt = now;
        Assert.Equal(now, BackupSchedule.NextRun(s, now));
        s.LastRunAt = now.AddSeconds(1); // the run happened after the request
        Assert.Null(BackupSchedule.NextRun(s, now.AddSeconds(2)));
    }

    private static string ProgressJson(bool running, int percent, DateTimeOffset updated) =>
        "{\"running\":" + (running ? "true" : "false") + ",\"percent\":" + percent + ",\"stage\":\"Gravando\",\"startedAt\":\"" + updated.AddSeconds(-5).ToString("o") + "\",\"updatedAt\":\"" + updated.ToString("o") + "\"}";

    [Fact]
    public void Progress_is_read_from_the_file_and_clamped()
    {
        var dir = Directory.CreateTempSubdirectory("ebt-progress-").FullName;
        try
        {
            Assert.Null(SystemEndpoints.ScanProgress(dir));
            Assert.Null(SystemEndpoints.ScanProgress(null));
            var now = DateTimeOffset.UtcNow;
            File.WriteAllText(Path.Combine(dir, "progress.json"), ProgressJson(true, 140, now));
            var p = SystemEndpoints.ScanProgress(dir, now)!;
            Assert.True(p.Running);
            Assert.Equal(100, p.Percent);
            Assert.Equal("Gravando", p.Stage);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public void A_running_file_that_stopped_updating_is_reported_as_not_running()
    {
        var dir = Directory.CreateTempSubdirectory("ebt-progress-").FullName;
        try
        {
            var now = DateTimeOffset.UtcNow;
            File.WriteAllText(Path.Combine(dir, "progress.json"), ProgressJson(true, 42, now.AddMinutes(-5)));
            var p = SystemEndpoints.ScanProgress(dir, now)!;
            Assert.False(p.Running);
            Assert.Equal(42, p.Percent);
            File.WriteAllText(Path.Combine(dir, "progress.json"), "{ not json");
            Assert.Null(SystemEndpoints.ScanProgress(dir, now));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Settings_response_carries_the_progress_of_the_running_backup()
    {
        var dir = Directory.CreateTempSubdirectory("ebt-progress-").FullName;
        try
        {
            File.WriteAllText(Path.Combine(dir, "progress.json"), ProgressJson(true, 37, DateTimeOffset.UtcNow));
            var host = api.Anonymous(new Dictionary<string, string> { ["Backup:Directory"] = dir });
            var login = await (await host.PostAsJsonAsync("/api/auth/login", new LoginRequest(ApiFixture.AdminUser, ApiFixture.AdminPassword))).Read<LoginResponse>();
            host.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", login.Token);
            var s = (await host.GetFromJsonAsync<BackupSettingsDto>(Url, ApiFixture.Json))!;
            Assert.NotNull(s.Progress);
            Assert.True(s.Progress!.Running);
            Assert.Equal(37, s.Progress.Percent);
        }
        finally { Directory.Delete(dir, true); }
    }

    private async Task<HttpClient> AdminWithProgressDir(string dir)
    {
        var host = api.Anonymous(new Dictionary<string, string> { ["Backup:Directory"] = dir });
        var login = await (await host.PostAsJsonAsync("/api/auth/login", new LoginRequest(ApiFixture.AdminUser, ApiFixture.AdminPassword))).Read<LoginResponse>();
        host.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", login.Token);
        return host;
    }

    [Fact]
    public async Task Cancel_is_admin_only()
    {
        var reader = await api.UserAsync(UserRole.Reader);
        Assert.Equal(HttpStatusCode.Forbidden, (await reader.PostAsync(Url + "/cancel", null)).StatusCode);
    }

    [Fact]
    public async Task Cancel_of_a_running_backup_flags_it_and_keeps_the_request()
    {
        var dir = Directory.CreateTempSubdirectory("ebt-cancel-").FullName;
        try
        {
            var admin = await AdminWithProgressDir(dir);
            (await admin.PutAsJsonAsync(Url, Valid(null))).EnsureSuccessStatusCode();
            await admin.PostAsync(Url + "/run-now", null);
            File.WriteAllText(Path.Combine(dir, "progress.json"), ProgressJson(true, 20, DateTimeOffset.UtcNow));
            var s = await (await admin.PostAsync(Url + "/cancel", null)).Read<BackupSettingsDto>();
            Assert.NotNull(s.CancelRequestedAt);
            Assert.True(s.Progress!.Running);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Cancel_of_a_waiting_request_drops_it()
    {
        var dir = Directory.CreateTempSubdirectory("ebt-cancel-").FullName;
        try
        {
            var admin = await AdminWithProgressDir(dir);
            (await admin.PutAsJsonAsync(Url, Valid())).EnsureSuccessStatusCode();
            var asked = await (await admin.PostAsync(Url + "/run-now", null)).Read<BackupSettingsDto>();
            Assert.NotNull(asked.RunRequestedAt);
            var s = await (await admin.PostAsync(Url + "/cancel", null)).Read<BackupSettingsDto>();
            Assert.Null(s.RunRequestedAt);
            Assert.NotNull(s.CancelRequestedAt);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Cancel_with_nothing_to_stop_changes_nothing()
    {
        var dir = Directory.CreateTempSubdirectory("ebt-cancel-").FullName;
        try
        {
            var admin = await AdminWithProgressDir(dir);
            await admin.PostAsync(Url + "/cancel", null); // other tests leave a request waiting; this drops it so nothing is left to stop
            var before = await admin.GetFromJsonAsync<BackupSettingsDto>(Url, ApiFixture.Json);
            File.WriteAllText(Path.Combine(dir, "progress.json"), ProgressJson(false, 100, DateTimeOffset.UtcNow));
            var s = await (await admin.PostAsync(Url + "/cancel", null)).Read<BackupSettingsDto>();
            Assert.Equal(before!.CancelRequestedAt, s.CancelRequestedAt);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_destination_is_required_to_turn_on_automatic_backup_or_to_run_now()
    {
        var admin = await api.AdminAsync();
        var noFolder = new BackupSettingsInput(true, "Daily", "22:00", 0, null, 5);
        var res = await admin.PutAsJsonAsync(Url, noFolder);
        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
        Assert.Contains("\"destination\"", await res.Content.ReadAsStringAsync());

        // Off and without a folder is a valid plan, but then no backup can be started.
        (await admin.PutAsJsonAsync(Url, noFolder with { Enabled = false })).EnsureSuccessStatusCode();
        var run = await admin.PostAsync(Url + "/run-now", null);
        Assert.Equal(HttpStatusCode.BadRequest, run.StatusCode);
        Assert.Contains("\"destination\"", await run.Content.ReadAsStringAsync());
        var s = await admin.GetFromJsonAsync<BackupSettingsDto>(Url, ApiFixture.Json);
        Assert.Null(s!.Destination);
    }
}
