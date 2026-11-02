using System.Net;
using System.Net.Http.Json;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;

namespace Ebt.Tests;

[Collection("api")]
public class BackupRestoreTests(ApiFixture api)
{
    private const string Url = "/api/admin/backups";
    private const string Newest = "ebt-manual-20261101-204459.dump";
    private const string Older = "ebt-scheduled-20261031-220000.dump";

    private static string ListJson(DateTimeOffset listed) =>
        "{\"listedAt\":\"" + listed.ToString("o") + "\",\"items\":["
        + "{\"name\":\"" + Older + "\",\"sizeBytes\":500000,\"createdAt\":\"2026-10-31T22:00:00Z\",\"location\":\"both\",\"hasChecksum\":true},"
        + "{\"name\":\"" + Newest + "\",\"sizeBytes\":617000,\"createdAt\":\"2026-11-01T20:44:59Z\",\"location\":\"local\",\"hasChecksum\":false}]}";

    private static string ProgressJson(bool running) =>
        "{\"running\":" + (running ? "true" : "false") + ",\"percent\":10,\"stage\":\"Restaurando\",\"startedAt\":\"" + DateTimeOffset.UtcNow.AddSeconds(-5).ToString("o") + "\",\"updatedAt\":\"" + DateTimeOffset.UtcNow.ToString("o") + "\"}";

    private async Task<(HttpClient Admin, string Dir)> Setup(bool withList = true)
    {
        var dir = Directory.CreateTempSubdirectory("ebt-restore-").FullName;
        if (withList) File.WriteAllText(Path.Combine(dir, "backups.json"), ListJson(DateTimeOffset.UtcNow));
        var host = api.Anonymous(new Dictionary<string, string> { ["Backup:Directory"] = dir });
        var login = await (await host.PostAsJsonAsync("/api/auth/login", new LoginRequest(ApiFixture.AdminUser, ApiFixture.AdminPassword))).Read<LoginResponse>();
        host.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", login.Token);
        (await host.PostAsync(Url + "/restore/cancel", null)).EnsureSuccessStatusCode(); // other tests leave a request pending in the shared row
        return (host, dir);
    }

    private static Task<HttpResponseMessage> Restore(HttpClient c, string? file, string? confirm = "RESTAURAR") =>
        c.PostAsJsonAsync(Url + "/restore", new SystemEndpoints.RestoreRequest(file, confirm));

    [Fact]
    public async Task Everything_is_admin_only()
    {
        var reader = await api.UserAsync(UserRole.Reader);
        Assert.Equal(HttpStatusCode.Forbidden, (await reader.GetAsync(Url)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Restore(reader, Newest)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await reader.PostAsync(Url + "/restore/cancel", null)).StatusCode);
    }

    [Fact]
    public async Task Without_files_the_list_is_empty()
    {
        var (admin, dir) = await Setup(withList: false);
        try
        {
            File.WriteAllText(Path.Combine(dir, "restore-result.json"), "{ not json");
            var r = (await admin.GetFromJsonAsync<SystemEndpoints.BackupListResponse>(Url, ApiFixture.Json))!;
            Assert.Empty(r.Items);
            Assert.Null(r.ListedAt);
            Assert.Null(r.Restore.Result);
            Assert.Null(r.Restore.RequestedAt);
            File.WriteAllText(Path.Combine(dir, "backups.json"), "garbage");
            Assert.Empty((await admin.GetFromJsonAsync<SystemEndpoints.BackupListResponse>(Url, ApiFixture.Json))!.Items);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task The_list_comes_newest_first()
    {
        var (admin, dir) = await Setup();
        try
        {
            var r = (await admin.GetFromJsonAsync<SystemEndpoints.BackupListResponse>(Url, ApiFixture.Json))!;
            Assert.Equal([Newest, Older], r.Items.Select(i => i.Name));
            Assert.Equal(617000, r.Items[0].SizeBytes);
            Assert.Equal("local", r.Items[0].Location);
            Assert.False(r.Items[0].HasChecksum);
            Assert.True(r.Items[1].HasChecksum);
            Assert.NotNull(r.ListedAt);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Theory]
    [InlineData("not-a-backup.dump")]
    [InlineData("ebt-manual-20261101-999999.txt")]
    [InlineData("../ebt-manual-20261101-204459.dump")]
    [InlineData("..")]
    [InlineData("sub/ebt-manual-20261101-204459.dump")]
    [InlineData("sub\ebt-manual-20261101-204459.dump")]
    [InlineData("ebt-manual-20250101-000000.dump")] // well formed but not in the agent's list
    [InlineData(null)]
    public async Task A_bad_file_is_refused(string? file)
    {
        var (admin, dir) = await Setup();
        try
        {
            var res = await Restore(admin, file);
            Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
            Assert.Contains("\"file\"", await res.Content.ReadAsStringAsync());
            Assert.Null((await admin.GetFromJsonAsync<SystemEndpoints.BackupListResponse>(Url, ApiFixture.Json))!.Restore.RequestedAt);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Theory]
    [InlineData("restaurar")]
    [InlineData("")]
    [InlineData(null)]
    public async Task The_typed_word_must_match_exactly(string? confirm)
    {
        var (admin, dir) = await Setup();
        try
        {
            var res = await Restore(admin, Newest, confirm);
            Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
            Assert.Contains("\"confirm\"", await res.Content.ReadAsStringAsync());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_running_backup_blocks_the_request()
    {
        var (admin, dir) = await Setup();
        try
        {
            File.WriteAllText(Path.Combine(dir, "progress.json"), ProgressJson(true));
            Assert.Equal(HttpStatusCode.Conflict, (await Restore(admin, Newest)).StatusCode);
            Assert.Null((await admin.GetFromJsonAsync<SystemEndpoints.BackupListResponse>(Url, ApiFixture.Json))!.Restore.RequestedAt);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_request_is_recorded_audited_and_blocks_a_second_one()
    {
        var (admin, dir) = await Setup();
        try
        {
            var res = await Restore(admin, Newest);
            Assert.Equal(HttpStatusCode.Accepted, res.StatusCode);
            var r = await res.Read<SystemEndpoints.BackupListResponse>();
            Assert.Equal(Newest, r.Restore.File);
            Assert.InRange((DateTimeOffset.UtcNow - r.Restore.RequestedAt!.Value).TotalMinutes, -1, 1);
            Assert.Equal(2, r.Items.Count);
            var again = await admin.GetFromJsonAsync<SystemEndpoints.BackupListResponse>(Url, ApiFixture.Json);
            Assert.Equal(Newest, again!.Restore.File);

            Assert.Equal(HttpStatusCode.Conflict, (await Restore(admin, Older)).StatusCode);

            var page = await (await admin.GetAsync("/api/audit?entity=BackupSettings")).Read<Page<AuditOut>>();
            Assert.Contains(page.Items, a => a.Action == "Update" && a.Changes.Contains("RestoreFile") && a.User == ApiFixture.AdminUser);

            // The plan screen's save must not wipe the request.
            (await admin.PutAsJsonAsync("/api/admin/backup-settings", new BackupSettingsInput(false, "Daily", "22:00", 0, null, 5))).EnsureSuccessStatusCode();
            Assert.Equal(Newest, (await admin.GetFromJsonAsync<SystemEndpoints.BackupListResponse>(Url, ApiFixture.Json))!.Restore.File);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task The_result_is_returned_and_a_finished_restore_allows_a_new_request()
    {
        var (admin, dir) = await Setup();
        try
        {
            Assert.Equal(HttpStatusCode.Accepted, (await Restore(admin, Newest)).StatusCode);
            var done = DateTimeOffset.UtcNow.AddSeconds(5).ToString("o");
            File.WriteAllText(Path.Combine(dir, "restore-result.json"),
                "{\"ok\":true,\"message\":\"Restaurado\",\"file\":\"" + Newest + "\",\"safetyDump\":\"ebt-before-restore-20261101-210000.dump\",\"finishedAt\":\"" + done + "\"}");
            var r = (await admin.GetFromJsonAsync<SystemEndpoints.BackupListResponse>(Url, ApiFixture.Json))!;
            Assert.True(r.Restore.Result!.Ok);
            Assert.Equal("Restaurado", r.Restore.Result.Message);
            Assert.Equal(Newest, r.Restore.Result.File);
            Assert.Equal("ebt-before-restore-20261101-210000.dump", r.Restore.Result.SafetyDump);
            Assert.NotNull(r.Restore.Result.FinishedAt);

            Assert.Equal(HttpStatusCode.Accepted, (await Restore(admin, Older)).StatusCode); // the earlier one finished
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Cancel_clears_a_pending_request_but_not_a_running_restore()
    {
        var (admin, dir) = await Setup();
        try
        {
            Assert.Equal(HttpStatusCode.Accepted, (await Restore(admin, Newest)).StatusCode);
            File.WriteAllText(Path.Combine(dir, "progress.json"), ProgressJson(true));
            Assert.Equal(HttpStatusCode.Conflict, (await admin.PostAsync(Url + "/restore/cancel", null)).StatusCode);
            Assert.Equal(Newest, (await admin.GetFromJsonAsync<SystemEndpoints.BackupListResponse>(Url, ApiFixture.Json))!.Restore.File);

            File.WriteAllText(Path.Combine(dir, "progress.json"), ProgressJson(false));
            var r = await (await admin.PostAsync(Url + "/restore/cancel", null)).Read<SystemEndpoints.BackupListResponse>();
            Assert.Null(r.Restore.RequestedAt);
            Assert.Null(r.Restore.File);
            Assert.Equal(HttpStatusCode.Accepted, (await Restore(admin, Newest)).StatusCode);
        }
        finally { Directory.Delete(dir, true); }
    }
}
