using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;

namespace Ebt.Tests;

[Collection("api")]
public class MyActivityTests(ApiFixture api)
{
    private async Task<string> NewUser()
    {
        var admin = await api.AdminAsync();
        var name = $"act{Guid.NewGuid():N}"[..18];
        (await admin.Post("/api/users", new CreateUserRequest(name, "user-password-123", UserRole.Reader))).EnsureSuccessStatusCode();
        return name;
    }

    private async Task<(HttpClient Client, LoginResponse Login)> Login(string user, string? device = null)
    {
        var res = await api.Anonymous().PostAsJsonAsync("/api/auth/login", new LoginRequest(user, "user-password-123", device));
        var login = await res.Read<LoginResponse>();
        var client = api.Anonymous();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.Token);
        return (client, login);
    }

    private static async Task<JsonElement> Json(HttpResponseMessage res)
    {
        res.EnsureSuccessStatusCode();
        return JsonDocument.Parse(await res.Content.ReadAsStringAsync()).RootElement;
    }

    [Fact]
    public async Task PreviousLoginAt_is_null_on_first_login_and_set_after_a_second_one()
    {
        var user = await NewUser();
        var (first, firstLogin) = await Login(user, "Balcao");
        Assert.Null(firstLogin.PreviousLoginAt);
        Assert.Equal(JsonValueKind.Null, (await Json(await first.GetAsync("/api/auth/me"))).GetProperty("previousLoginAt").ValueKind);

        var (second, secondLogin) = await Login(user, "Celular");
        Assert.NotNull(secondLogin.PreviousLoginAt);
        Assert.True(secondLogin.PreviousLoginAt <= DateTimeOffset.UtcNow);
        Assert.NotEqual(JsonValueKind.Null, (await Json(await second.GetAsync("/api/auth/me"))).GetProperty("previousLoginAt").ValueKind);

        // a token rotation is not a sign-in
        var rotated = await (await api.Anonymous().PostAsJsonAsync("/api/auth/refresh", new RefreshRequest(secondLogin.RefreshToken))).Read<LoginResponse>();
        Assert.Equal(secondLogin.PreviousLoginAt, rotated.PreviousLoginAt);
    }

    [Fact]
    public async Task MyActivity_lists_only_own_logins_and_changes_and_caps_them()
    {
        var user = await NewUser();
        var (me, _) = await Login(user, "Balcao");
        for (var i = 0; i < 21; i++) await Login(user, $"Dev{i}");
        for (var i = 0; i < 32; i++)
            (await me.Put("/api/auth/profile", new ProfileRequest($"Nome {i}", null))).EnsureSuccessStatusCode();

        var other = await NewUser();
        var (otherClient, _) = await Login(other, "Outro");
        (await otherClient.Put("/api/auth/profile", new ProfileRequest("Somente do outro", null))).EnsureSuccessStatusCode();

        var mine = await Json(await me.GetAsync("/api/auth/my-activity"));
        var logins = mine.GetProperty("logins").EnumerateArray().ToList();
        var changes = mine.GetProperty("changes").EnumerateArray().ToList();
        Assert.Equal(20, logins.Count);
        Assert.Equal("Dev20", logins[0].GetProperty("device").GetString()); // newest first
        Assert.Equal(30, changes.Count);
        Assert.All(changes, c => Assert.Contains(c.GetProperty("entity").GetString(), new[] { "User", "AppUser" }));
        Assert.DoesNotContain(changes, c => (c.GetProperty("summary").GetString() ?? "").Contains("Somente do outro"));
        Assert.DoesNotContain("passwordHash", mine.GetRawText(), StringComparison.OrdinalIgnoreCase);

        var theirs = await Json(await otherClient.GetAsync("/api/auth/my-activity"));
        Assert.Single(theirs.GetProperty("logins").EnumerateArray());
        Assert.Equal(2, theirs.GetProperty("changes").GetArrayLength()); // profile writes an AppUser and a User row
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().GetAsync("/api/auth/my-activity")).StatusCode);
    }

    [Fact]
    public async Task NotificationPrefs_round_trip_per_user_without_audit_rows()
    {
        var user = await NewUser();
        var (me, _) = await Login(user);
        var empty = await Json(await me.GetAsync("/api/auth/notification-prefs"));
        Assert.Empty(empty.GetProperty("mutedAlerts").EnumerateArray());
        Assert.False(empty.GetProperty("hideLegacy").GetBoolean());

        var saved = await Json(await me.Put("/api/auth/notification-prefs", new { mutedAlerts = new[] { "low-stock", "overdue_po", "low-stock" }, hideLegacy = true }));
        Assert.Equal(new[] { "low-stock", "overdue_po" }, saved.GetProperty("mutedAlerts").EnumerateArray().Select(e => e.GetString()!).ToArray());
        Assert.True(saved.GetProperty("hideLegacy").GetBoolean());
        var again = await Json(await me.GetAsync("/api/auth/notification-prefs"));
        Assert.Equal(2, again.GetProperty("mutedAlerts").GetArrayLength());
        Assert.True(again.GetProperty("hideLegacy").GetBoolean());

        var other = await NewUser();
        var (otherClient, _) = await Login(other);
        var theirs = await Json(await otherClient.GetAsync("/api/auth/notification-prefs"));
        Assert.Empty(theirs.GetProperty("mutedAlerts").EnumerateArray());
        Assert.False(theirs.GetProperty("hideLegacy").GetBoolean());

        var activity = await Json(await me.GetAsync("/api/auth/my-activity"));
        Assert.Empty(activity.GetProperty("changes").EnumerateArray());

        var cleared = await Json(await me.Put("/api/auth/notification-prefs", new { mutedAlerts = Array.Empty<string>(), hideLegacy = false }));
        Assert.Empty(cleared.GetProperty("mutedAlerts").EnumerateArray());
    }

    [Theory]
    [InlineData("Maiuscula")]
    [InlineData("com espaco")]
    [InlineData("")]
    [InlineData("a1234567890123456789012345678901234567890")]
    public async Task NotificationPrefs_reject_bad_keys(string key)
    {
        var (me, _) = await Login(await NewUser());
        var res = await me.Put("/api/auth/notification-prefs", new { mutedAlerts = new[] { key }, hideLegacy = false });
        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
    }

    [Fact]
    public async Task NotificationPrefs_reject_more_than_30_keys()
    {
        var (me, _) = await Login(await NewUser());
        var keys = Enumerable.Range(0, 31).Select(i => $"k{i}").ToArray();
        Assert.Equal(HttpStatusCode.BadRequest, (await me.Put("/api/auth/notification-prefs", new { mutedAlerts = keys, hideLegacy = false })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await me.Put("/api/auth/notification-prefs", new { mutedAlerts = keys.Take(30).ToArray(), hideLegacy = false })).StatusCode);
    }
}
