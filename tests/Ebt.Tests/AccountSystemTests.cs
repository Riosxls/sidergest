using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;

namespace Ebt.Tests;

[Collection("api")]
public class AccountSystemTests(ApiFixture api)
{
    private async Task<string> NewUser()
    {
        var admin = await api.AdminAsync();
        var name = $"acct{Guid.NewGuid():N}"[..18];
        (await admin.Post("/api/users", new CreateUserRequest(name, "user-password-123", UserRole.Reader))).EnsureSuccessStatusCode();
        return name;
    }

    private async Task<(HttpClient Client, LoginResponse Login)> Device(string user, string? device)
    {
        var res = await api.Anonymous().PostAsJsonAsync("/api/auth/login", new LoginRequest(user, "user-password-123", device));
        var login = await res.Read<LoginResponse>();
        var client = api.Anonymous();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.Token);
        return (client, login);
    }

    private static async Task<List<SessionDto>> Sessions(HttpClient c, string refresh) =>
        await (await c.Post("/api/auth/sessions", new SessionsRequest(refresh))).Read<List<SessionDto>>();

    [Fact]
    public async Task Sessions_list_own_devices_and_mark_the_current_one()
    {
        var user = await NewUser();
        var (pc, pcLogin) = await Device(user, "Balcao");
        var (_, phoneLogin) = await Device(user, "Celular");
        var list = await Sessions(pc, pcLogin.RefreshToken);
        Assert.Equal(2, list.Count);
        Assert.Equal("Celular", list[0].Device); // newest first
        Assert.False(list[0].Current);
        Assert.Equal("Balcao", list.Single(s => s.Current).Device);

        // a refresh keeps the device label on the rotated row
        var rotated = await (await api.Anonymous().PostAsJsonAsync("/api/auth/refresh", new RefreshRequest(phoneLogin.RefreshToken))).Read<LoginResponse>();
        var after = await Sessions(pc, rotated.RefreshToken);
        Assert.Equal(2, after.Count);
        Assert.Equal("Celular", after.Single(s => s.Current).Device);
    }

    [Fact]
    public async Task A_device_can_be_removed_but_only_by_its_owner()
    {
        var user = await NewUser();
        var (pc, pcLogin) = await Device(user, "Balcao");
        var (_, phoneLogin) = await Device(user, "Celular");
        var other = await api.UserAsync(UserRole.Reader);
        var phoneId = (await Sessions(pc, pcLogin.RefreshToken)).Single(s => s.Device == "Celular").Id;

        Assert.Equal(HttpStatusCode.NotFound, (await other.DeleteAsync($"/api/auth/sessions/{phoneId}")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await pc.DeleteAsync($"/api/auth/sessions/{phoneId}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await pc.DeleteAsync($"/api/auth/sessions/{phoneId}")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().PostAsJsonAsync("/api/auth/refresh", new RefreshRequest(phoneLogin.RefreshToken))).StatusCode);
    }

    [Fact]
    public async Task Revoke_others_keeps_this_device_and_kills_the_rest()
    {
        var user = await NewUser();
        var (pc, pcLogin) = await Device(user, "Balcao");
        var (phone, phoneLogin) = await Device(user, "Celular");

        Assert.Equal(HttpStatusCode.BadRequest, (await pc.Post("/api/auth/sessions/revoke-others", new SessionsRequest("not-a-token"))).StatusCode);
        var fresh = await (await pc.Post("/api/auth/sessions/revoke-others", new SessionsRequest(pcLogin.RefreshToken))).Read<LoginResponse>();

        // the old access token died with the version bump; the fresh one works
        Assert.Equal(HttpStatusCode.Unauthorized, (await pc.GetAsync("/api/auth/me")).StatusCode);
        pc.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", fresh.Token);
        var list = await Sessions(pc, fresh.RefreshToken);
        Assert.Single(list);
        Assert.Equal("Balcao", list[0].Device);
        Assert.Equal(HttpStatusCode.OK, (await pc.GetAsync("/api/auth/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await phone.GetAsync("/api/auth/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().PostAsJsonAsync("/api/auth/refresh", new RefreshRequest(phoneLogin.RefreshToken))).StatusCode);
    }

    [Fact]
    public async Task Profile_is_saved_trimmed_returned_by_me_and_validated()
    {
        var c = await api.UserAsync(UserRole.Reader);
        var me0 = await c.GetFromJsonAsync<JsonElement>("/api/auth/me");
        Assert.Equal(JsonValueKind.Null, me0.GetProperty("displayName").ValueKind);

        var saved = await (await c.Put("/api/auth/profile", new ProfileRequest("  Ana Souza ", " ana@ebt.com.br "))).Read<JsonElement>();
        Assert.Equal("Ana Souza", saved.GetProperty("displayName").GetString());
        Assert.Equal("ana@ebt.com.br", saved.GetProperty("email").GetString());
        var me = await c.GetFromJsonAsync<JsonElement>("/api/auth/me");
        Assert.Equal("ana@ebt.com.br", me.GetProperty("email").GetString());
        Assert.True(me.GetProperty("permissions").GetArrayLength() > 0);

        Assert.Equal(HttpStatusCode.BadRequest, (await c.Put("/api/auth/profile", new ProfileRequest("Ana", "sem-arroba"))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await c.Put("/api/auth/profile", new ProfileRequest("Ana", "a b@c.com"))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await c.Put("/api/auth/profile", new ProfileRequest(new string('x', 121), null))).StatusCode);

        var cleared = await (await c.Put("/api/auth/profile", new ProfileRequest("", " "))).Read<JsonElement>();
        Assert.Equal(JsonValueKind.Null, cleared.GetProperty("displayName").ValueKind);
        Assert.Equal(JsonValueKind.Null, cleared.GetProperty("email").ValueKind);
    }

    [Fact]
    public async Task About_reports_version_runtime_and_database()
    {
        var c = await api.UserAsync(UserRole.Reader);
        var about = await c.GetFromJsonAsync<JsonElement>("/api/system/about");
        Assert.False(string.IsNullOrWhiteSpace(about.GetProperty("version").GetString()));
        Assert.DoesNotContain('+', about.GetProperty("version").GetString()!);
        Assert.Contains(".NET", about.GetProperty("runtime").GetString());
        Assert.True(about.GetProperty("databaseOk").GetBoolean());
        Assert.False(string.IsNullOrWhiteSpace(about.GetProperty("lastMigration").GetString()));
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().GetAsync("/api/system/about")).StatusCode);
    }

    [Fact]
    public async Task Backup_status_is_admin_only_and_unconfigured_by_default()
    {
        var reader = await api.UserAsync(UserRole.Reader);
        Assert.Equal(HttpStatusCode.Forbidden, (await reader.GetAsync("/api/admin/backup-status")).StatusCode);
        var s = await (await api.AdminAsync()).GetFromJsonAsync<BackupStatus>("/api/admin/backup-status", ApiFixture.Json);
        Assert.False(s!.Configured);
        Assert.Equal(0, s.Count);
    }

    [Fact]
    public async Task Backup_status_reports_the_newest_dump_of_the_configured_folder()
    {
        var dir = Directory.CreateTempSubdirectory("ebt-backups-").FullName;
        try
        {
            var older = Path.Combine(dir, "ebt-nightly-20261030-220000.dump");
            var newest = Path.Combine(dir, "ebt-nightly-20261031-220000.dump");
            File.WriteAllText(older, "old");
            File.WriteAllText(newest, "newest dump");
            File.WriteAllText(Path.Combine(dir, "notes.txt"), "ignored");
            File.SetLastWriteTimeUtc(older, DateTime.UtcNow.AddDays(-2));
            File.SetLastWriteTimeUtc(newest, DateTime.UtcNow.AddDays(-1));

            var host = api.Anonymous(new Dictionary<string, string> { ["Backup:Directory"] = dir });
            var login = await (await host.PostAsJsonAsync("/api/auth/login", new LoginRequest(ApiFixture.AdminUser, ApiFixture.AdminPassword))).Read<LoginResponse>();
            host.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.Token);
            var s = (await host.GetFromJsonAsync<BackupStatus>("/api/admin/backup-status", ApiFixture.Json))!;
            Assert.True(s.Configured);
            Assert.Equal(2, s.Count);
            Assert.Equal("ebt-nightly-20261031-220000.dump", s.LastBackupFile);
            Assert.Equal("newest dump".Length, s.LastBackupSizeBytes);
            Assert.InRange((DateTimeOffset.UtcNow - s.LastBackupAt!.Value).TotalHours, 23, 25);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Data_source_all_from_turns_test_records_back_into_manual()
    {
        var admin = await api.AdminAsync();
        int id;
        await using (var db = api.NewDb())
        {
            var supplier = new Supplier { Name = $"Fonte {Guid.NewGuid():N}", Source = DataSource.Test };
            db.Suppliers.Add(supplier);
            await db.SaveChangesAsync();
            id = supplier.Id;
        }
        async Task<int> Rows(object body) => (await (await admin.Post("/api/admin/data-source", body)).Read<JsonElement>()).GetProperty("rows").GetInt32();

        Assert.True(await Rows(new { entity = "Supplier", allManual = true, from = "Test", target = "Manual", apply = false }) >= 1);
        Assert.Equal(0, await Rows(new { entity = "Supplier", allManual = true, from = "Test", target = "Test", apply = true }));
        await using (var db = api.NewDb()) Assert.Equal(DataSource.Test, db.Suppliers.Single(x => x.Id == id).Source);

        Assert.True(await Rows(new { entity = "Supplier", allManual = true, from = "Test", target = "Manual", apply = true }) >= 1);
        await using (var db = api.NewDb()) Assert.Equal(DataSource.Manual, db.Suppliers.Single(x => x.Id == id).Source);
    }

    [Fact]
    public void Scanning_a_missing_folder_is_unconfigured()
    {
        Assert.False(SystemEndpoints.ScanBackups(null).Configured);
        Assert.False(SystemEndpoints.ScanBackups(Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"))).Configured);
    }
}
