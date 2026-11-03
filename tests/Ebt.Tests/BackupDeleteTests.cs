using System.Net;
using System.Net.Http.Json;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;

namespace Ebt.Tests;

[Collection("api")]
public class BackupDeleteTests(ApiFixture api)
{
    private const string Url = "/api/admin/backups";
    private const string Newest = "ebt-manual-20261101-204459.dump";
    private const string Older = "ebt-scheduled-20261031-220000.dump";

    private static string ListJson() =>
        "{\"listedAt\":\"" + DateTimeOffset.UtcNow.ToString("o") + "\",\"items\":["
        + "{\"name\":\"" + Older + "\",\"sizeBytes\":500000,\"createdAt\":\"2026-10-31T22:00:00Z\",\"location\":\"both\",\"hasChecksum\":true},"
        + "{\"name\":\"" + Newest + "\",\"sizeBytes\":617000,\"createdAt\":\"2026-11-01T20:44:59Z\",\"location\":\"local\",\"hasChecksum\":false}]}";

    private static string ProgressJson(bool running) =>
        "{\"running\":" + (running ? "true" : "false") + ",\"percent\":10,\"stage\":\"Fazendo backup\",\"startedAt\":\"" + DateTimeOffset.UtcNow.AddSeconds(-5).ToString("o") + "\",\"updatedAt\":\"" + DateTimeOffset.UtcNow.ToString("o") + "\"}";

    private static void WriteResult(string dir, string file, bool ok = true, string message = "Excluido", int offsetSeconds = 5)
    {
        var done = DateTimeOffset.UtcNow.AddSeconds(offsetSeconds).ToString("o");
        File.WriteAllText(Path.Combine(dir, "delete-result.json"), "{\"ok\":" + (ok ? "true" : "false") + ",\"message\":\"" + message + "\",\"file\":\"" + file + "\",\"finishedAt\":\"" + done + "\"}");
    }

    /// <summary>Fresh directory; any request left in the shared settings row by other tests is first closed with a finished result.</summary>
    private async Task<(HttpClient Admin, string Dir)> Setup()
    {
        var dir = Directory.CreateTempSubdirectory("ebt-delete-").FullName;
        File.WriteAllText(Path.Combine(dir, "backups.json"), ListJson());
        var host = api.Anonymous(new Dictionary<string, string> { ["Backup:Directory"] = dir });
        var login = await (await host.PostAsJsonAsync("/api/auth/login", new LoginRequest(ApiFixture.AdminUser, ApiFixture.AdminPassword))).Read<LoginResponse>();
        host.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", login.Token);
        (await host.PostAsync(Url + "/restore/cancel", null)).EnsureSuccessStatusCode();
        var state = (await host.GetFromJsonAsync<SystemEndpoints.BackupListResponse>(Url, ApiFixture.Json))!;
        if (state.Delete.RequestedAt is not null) WriteResult(dir, state.Delete.File ?? Newest, offsetSeconds: 0);
        File.Delete(Path.Combine(dir, "progress.json"));
        return (host, dir);
    }

    private static Task<HttpResponseMessage> Delete(HttpClient c, string? file, string? confirm = "EXCLUIR", string? password = ApiFixture.AdminPassword) =>
        c.PostAsJsonAsync(Url + "/delete", new SystemEndpoints.DeleteRequest(file, confirm, password));

    private static async Task<SystemEndpoints.BackupListResponse> State(HttpClient c) =>
        (await c.GetFromJsonAsync<SystemEndpoints.BackupListResponse>(Url, ApiFixture.Json))!;

    [Fact]
    public async Task Deleting_asks_for_the_admin_password_again()
    {
        var (admin, dir) = await Setup();
        try
        {
            Assert.Equal(HttpStatusCode.Forbidden, (await Delete(admin, Newest, password: "not-the-password")).StatusCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await Delete(admin, Newest, password: null)).StatusCode);
            Assert.Equal(HttpStatusCode.Accepted, (await Delete(admin, Newest)).StatusCode);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Deleting_is_admin_only()
    {
        var reader = await api.UserAsync(UserRole.Reader);
        Assert.Equal(HttpStatusCode.Forbidden, (await Delete(reader, Newest)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().PostAsJsonAsync(Url + "/delete", new SystemEndpoints.DeleteRequest(Newest, "EXCLUIR"))).StatusCode);
    }

    [Fact]
    public async Task Without_a_result_file_the_delete_state_is_empty_and_a_broken_one_is_ignored()
    {
        var (admin, dir) = await Setup();
        try
        {
            File.Delete(Path.Combine(dir, "delete-result.json"));
            File.WriteAllText(Path.Combine(dir, "delete-result.json"), "{ not json");
            var d = (await State(admin)).Delete;
            Assert.Null(d.Result);
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
            var res = await Delete(admin, file);
            Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
            Assert.Contains("\"file\"", await res.Content.ReadAsStringAsync());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Theory]
    [InlineData("excluir")]
    [InlineData("RESTAURAR")]
    [InlineData("")]
    [InlineData(null)]
    public async Task The_typed_word_must_match_exactly(string? confirm)
    {
        var (admin, dir) = await Setup();
        try
        {
            var res = await Delete(admin, Newest, confirm);
            Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
            Assert.Contains("\"confirm\"", await res.Content.ReadAsStringAsync());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_running_backup_or_restore_blocks_the_request()
    {
        var (admin, dir) = await Setup();
        try
        {
            File.WriteAllText(Path.Combine(dir, "progress.json"), ProgressJson(true));
            Assert.Equal(HttpStatusCode.Conflict, (await Delete(admin, Newest)).StatusCode);
            File.WriteAllText(Path.Combine(dir, "progress.json"), ProgressJson(false));

            var restore = await admin.PostAsJsonAsync(Url + "/restore", new SystemEndpoints.RestoreRequest(Older, "RESTAURAR", ApiFixture.AdminPassword));
            Assert.Equal(HttpStatusCode.Accepted, restore.StatusCode);
            Assert.Equal(HttpStatusCode.Conflict, (await Delete(admin, Newest)).StatusCode); // restore pending
            (await admin.PostAsync(Url + "/restore/cancel", null)).EnsureSuccessStatusCode();
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_request_is_recorded_audited_and_blocks_a_second_one()
    {
        var (admin, dir) = await Setup();
        try
        {
            var res = await Delete(admin, Newest);
            Assert.Equal(HttpStatusCode.Accepted, res.StatusCode);
            var r = await res.Read<SystemEndpoints.BackupListResponse>();
            Assert.Equal(Newest, r.Delete.File);
            Assert.InRange((DateTimeOffset.UtcNow - r.Delete.RequestedAt!.Value).TotalMinutes, -1, 1);
            Assert.Equal(2, r.Items.Count);
            File.Delete(Path.Combine(dir, "delete-result.json")); // Setup left a result from an earlier test; the request is now unanswered
            Assert.Equal(Newest, (await State(admin)).Delete.File);

            Assert.Equal(HttpStatusCode.Conflict, (await Delete(admin, Older)).StatusCode);

            var page = await (await admin.GetAsync("/api/audit?entity=BackupSettings")).Read<Page<AuditOut>>();
            Assert.Contains(page.Items, a => a.Action == "Update" && a.Changes.Contains("DeleteFile") && a.User == ApiFixture.AdminUser);

            // The plan screen's save and a restore request must not wipe the deletion.
            (await admin.PutAsJsonAsync("/api/admin/backup-settings", new BackupSettingsInput(false, "Daily", "22:00", 0, null, 5))).EnsureSuccessStatusCode();
            var after = (await State(admin)).Delete;
            Assert.Equal(Newest, after.File);
            Assert.NotNull(after.RequestedAt);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task The_result_is_returned_and_a_finished_deletion_allows_a_new_request()
    {
        var (admin, dir) = await Setup();
        try
        {
            Assert.Equal(HttpStatusCode.Accepted, (await Delete(admin, Newest)).StatusCode);
            WriteResult(dir, Newest);
            var d = (await State(admin)).Delete;
            Assert.True(d.Result!.Ok);
            Assert.Equal("Excluido", d.Result.Message);
            Assert.Equal(Newest, d.Result.File);
            Assert.NotNull(d.Result.FinishedAt);

            Assert.Equal(HttpStatusCode.Accepted, (await Delete(admin, Older)).StatusCode);
            Assert.Equal(Older, (await State(admin)).Delete.File);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_failed_result_is_reported_and_a_stale_result_does_not_finish_a_new_request()
    {
        var (admin, dir) = await Setup();
        try
        {
            Assert.Equal(HttpStatusCode.Accepted, (await Delete(admin, Newest)).StatusCode);
            File.WriteAllText(Path.Combine(dir, "delete-result.json"), "{\"ok\":false,\"message\":\"Falhou\",\"file\":\"" + Older + "\",\"finishedAt\":\"2020-01-01T00:00:00Z\"}");
            Assert.Equal(HttpStatusCode.Conflict, (await Delete(admin, Older)).StatusCode); // the old result predates the request
            WriteResult(dir, Newest, ok: false, message: "Falhou");
            var d = (await State(admin)).Delete;
            Assert.False(d.Result!.Ok);
            Assert.Equal("Falhou", d.Result.Message);
        }
        finally { Directory.Delete(dir, true); }
    }
}