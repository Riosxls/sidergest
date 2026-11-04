using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Tests;

[Collection("api")]
public class IdleLockTests(ApiFixture api)
{
    private const string Pw = "user-password-123";
    private static readonly Dictionary<string, string> Cap30 = new() { ["Security:MaxIdleMinutes"] = "30" };

    private async Task<(string Name, int Id)> NewUserAsync()
    {
        var admin = await api.AdminAsync();
        var name = $"idl{Guid.NewGuid():N}"[..18];
        var dto = await (await admin.Post("/api/users", new CreateUserRequest(name, Pw, UserRole.Reader))).Read<UserDto>();
        return (name, dto.Id);
    }

    private static async Task<HttpClient> SignIn(HttpClient c, string name)
    {
        var login = await (await c.PostAsJsonAsync("/api/auth/login", new LoginRequest(name, Pw))).Read<LoginResponse>();
        c.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.Token);
        return c;
    }

    private async Task SetAsync(int id, int? minutes, double? lastActivityMinutesAgo)
    {
        await using var db = api.NewDb();
        if (minutes is { } m) await db.Users.Where(u => u.Id == id).ExecuteUpdateAsync(s => s.SetProperty(u => u.IdleLockMinutes, m));
        if (lastActivityMinutesAgo is { } ago) await db.Users.Where(u => u.Id == id).ExecuteUpdateAsync(s => s.SetProperty(u => u.LastActivityAt, DateTimeOffset.UtcNow.AddMinutes(-ago)));
    }

    private static async Task<(int Idle, int Max)> Values(HttpResponseMessage res)
    {
        res.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var r = doc.RootElement;
        return (r.GetProperty("idleLockMinutes").GetInt32(), r.GetProperty("maxIdleMinutes").GetInt32());
    }

    [Fact]
    public async Task Activity_only_records_time_and_ignores_a_client_value()
    {
        var (name, id) = await NewUserAsync();
        var a = await SignIn(api.Anonymous(), name);
        var b = await SignIn(api.Anonymous(), name);
        Assert.Equal((15, 0), await Values(await a.PutAsJsonAsync("/api/auth/idle-lock", new { minutes = 15 })));

        // device B reports activity with "never" (legacy body shape): ignored
        Assert.Equal(HttpStatusCode.NoContent, (await b.PostAsJsonAsync("/api/auth/activity", new { idleLockMinutes = 0 })).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await b.PostAsync("/api/auth/activity", null)).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await b.PostAsJsonAsync("/api/auth/activity", new { idleLockMinutes = 999 })).StatusCode);
        Assert.Equal((15, 0), await Values(await b.GetAsync("/api/auth/me")));

        await SetAsync(id, null, 20);
        Assert.Equal(HttpStatusCode.Unauthorized, (await a.GetAsync("/api/products")).StatusCode);
    }

    [Fact]
    public async Task Idle_lock_endpoint_validates_and_returns_the_effective_value()
    {
        var (name, _) = await NewUserAsync();
        var c = await SignIn(api.Anonymous(), name);
        foreach (var bad in new[] { -1, 481 })
        {
            var res = await c.PutAsJsonAsync("/api/auth/idle-lock", new { minutes = bad });
            Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
            Assert.Contains("minutes", await res.Content.ReadAsStringAsync());
        }
        Assert.Equal((480, 0), await Values(await c.PutAsJsonAsync("/api/auth/idle-lock", new { minutes = 480 })));
        Assert.Equal((0, 0), await Values(await c.PutAsJsonAsync("/api/auth/idle-lock", new { minutes = 0 })));
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().PutAsJsonAsync("/api/auth/idle-lock", new { minutes = 5 })).StatusCode);
    }

    [Fact]
    public async Task Admin_cap_applies_to_never_and_to_larger_values()
    {
        var (name, id) = await NewUserAsync();
        var c = await SignIn(api.Anonymous(Cap30), name);
        Assert.Equal((10, 30), await Values(await c.PutAsJsonAsync("/api/auth/idle-lock", new { minutes = 10 })));
        Assert.Equal((30, 30), await Values(await c.PutAsJsonAsync("/api/auth/idle-lock", new { minutes = 120 })));
        Assert.Equal((30, 30), await Values(await c.PutAsJsonAsync("/api/auth/idle-lock", new { minutes = 0 })));
        Assert.Equal((30, 30), await Values(await c.GetAsync("/api/auth/me")));

        // the stored value is 0 ("never"), yet 20 idle minutes are fine and 40 are not
        await SetAsync(id, 0, 20);
        Assert.Equal(HttpStatusCode.OK, (await c.GetAsync("/api/products")).StatusCode);
        await SetAsync(id, null, 40);
        Assert.Equal(HttpStatusCode.Unauthorized, (await c.GetAsync("/api/products")).StatusCode);

        // login reports the effective value and the cap
        var login = await (await api.Anonymous(Cap30).PostAsJsonAsync("/api/auth/login", new LoginRequest(name, Pw))).Read<LoginResponse>();
        Assert.Equal(30, login.IdleLockMinutes);
        Assert.Equal(30, login.MaxIdleMinutes);

        // without the cap the same stored 0 never locks
        await SetAsync(id, 0, 3 * 24 * 60);
        var plain = api.Anonymous();
        plain.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.Token);
        Assert.Equal(HttpStatusCode.OK, (await plain.GetAsync("/api/products")).StatusCode);
    }

    [Fact]
    public async Task Background_requests_do_not_count_as_activity()
    {
        var (name, id) = await NewUserAsync();
        var c = await SignIn(api.Anonymous(), name);
        await c.PutAsJsonAsync("/api/auth/idle-lock", new { minutes = 15 });
        await SetAsync(id, null, 10);
        for (var i = 0; i < 3; i++) Assert.Equal(HttpStatusCode.OK, (await c.GetAsync("/api/products")).StatusCode);
        await using var db = api.NewDb();
        var last = await db.Users.Where(u => u.Id == id).Select(u => u.LastActivityAt).FirstAsync();
        Assert.True(DateTimeOffset.UtcNow - last > TimeSpan.FromMinutes(9));
    }

    [Fact]
    public async Task Login_and_activity_do_not_create_user_audit_rows()
    {
        var (name, id) = await NewUserAsync();
        var admin = await api.AdminAsync();
        var c = await SignIn(api.Anonymous(), name);
        await c.PostAsync("/api/auth/activity", null);
        await SignIn(api.Anonymous(), name);
        var page = await (await admin.GetAsync($"/api/audit?entity=AppUser&entityId={id}")).Read<Page<AuditOut>>();
        Assert.DoesNotContain(page.Items, a => a.Action == "Update");
        Assert.DoesNotContain(page.Items, a => a.Changes.Contains("LastActivityAt"));
    }

    [Fact]
    public async Task Purchasing_settings_changes_are_audited()
    {
        var admin = await api.AdminAsync();
        var cur = await (await admin.GetAsync("/api/purchasing/settings")).Read<PurchasingSettingsDto>();
        var tol = cur.ReceivingTolerancePercent == 7.5m ? 8.5m : 7.5m;
        (await admin.Put("/api/purchasing/settings", cur with { ReceivingTolerancePercent = tol })).EnsureSuccessStatusCode();
        var page = await (await admin.GetAsync("/api/audit?entity=PurchasingSettings")).Read<Page<AuditOut>>();
        Assert.Contains(page.Items, a => a.Action == "Update" && a.Changes.Contains("ReceivingTolerancePercent") && a.User == ApiFixture.AdminUser);
    }

    [Fact]
    public async Task Manual_nf_number_change_is_audited_explicitly()
    {
        var admin = await api.AdminAsync();
        var s = await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>();
        var next = s.NextNumber + 17;
        (await admin.Put("/api/fiscal/settings", s with { NextNumber = next })).EnsureSuccessStatusCode();
        var page = await (await admin.GetAsync("/api/audit?entity=FiscalSettings")).Read<Page<AuditOut>>();
        var row = page.Items.First(a => a.Changes.Contains("NextNumber") && a.Changes.Contains(next.ToString()));
        Assert.Equal(ApiFixture.AdminUser, row.User);
        using var doc = JsonDocument.Parse(row.Changes);
        Assert.Equal(s.NextNumber, doc.RootElement.GetProperty("NextNumber").GetProperty("from").GetInt32());
        Assert.Equal(next, doc.RootElement.GetProperty("NextNumber").GetProperty("to").GetInt32());

        // an unchanged number adds no row
        var before = (await (await admin.GetAsync("/api/audit?entity=FiscalSettings")).Read<Page<AuditOut>>()).Items.Count(a => a.Changes.Contains("NextNumber"));
        (await admin.Put("/api/fiscal/settings", s with { NextNumber = next })).EnsureSuccessStatusCode();
        var after = (await (await admin.GetAsync("/api/audit?entity=FiscalSettings")).Read<Page<AuditOut>>()).Items.Count(a => a.Changes.Contains("NextNumber"));
        Assert.Equal(before, after);
    }

    [Fact]
    public async Task Audit_filters_by_action_case_insensitively_and_lists_actions()
    {
        var admin = await api.AdminAsync();
        var s = await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>();
        (await admin.Put("/api/fiscal/settings", s with { NextNumber = s.NextNumber + 3 })).EnsureSuccessStatusCode();

        var actions = await (await admin.GetAsync("/api/audit/actions")).Read<List<string>>();
        Assert.Contains("Update", actions);
        Assert.Equal(actions.OrderBy(a => a).ToList(), actions);

        var page = await (await admin.GetAsync("/api/audit?entity=FiscalSettings&action=uPDATE")).Read<Page<AuditOut>>();
        Assert.NotEmpty(page.Items);
        Assert.All(page.Items, a => Assert.Equal("Update", a.Action));
        var none = await (await admin.GetAsync("/api/audit?entity=FiscalSettings&action=Delete")).Read<Page<AuditOut>>();
        Assert.Empty(none.Items);

        var reader = await api.UserAsync(UserRole.Reader);
        Assert.Equal(System.Net.HttpStatusCode.Forbidden, (await reader.GetAsync("/api/audit/actions")).StatusCode);
    }

    [Fact]
    public async Task Fiscal_settings_report_the_sefaz_mode()
    {
        var admin = await api.AdminAsync();
        var s = await (await admin.GetAsync("/api/fiscal/settings")).Read<FiscalSettingsDto>();
        Assert.Equal("Stub", s.SefazMode);
        Assert.True(s.SefazSimulated);
        var saved = await (await admin.Put("/api/fiscal/settings", s)).Read<FiscalSettingsDto>();
        Assert.Equal("Stub", saved.SefazMode);
    }

    [Fact]
    public async Task Easy_to_guess_passwords_are_rejected()
    {
        var admin = await api.AdminAsync();
        var res = await admin.Post("/api/users", new CreateUserRequest("easyuser-one", "sidergest123", UserRole.Reader));
        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
        Assert.Contains("too easy", await res.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post("/api/users", new CreateUserRequest("samename12345", "samename12345", UserRole.Reader))).StatusCode);

        var (name, id) = await NewUserAsync();
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Put($"/api/users/{id}", new UpdateUserRequest(UserRole.Reader, true, "sidergest123"))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Put($"/api/users/{id}", new UpdateUserRequest(UserRole.Reader, true, name))).StatusCode);

        var c = await SignIn(api.Anonymous(), name);
        var own = await c.PostAsJsonAsync("/api/auth/password", new ChangePasswordRequest(Pw, "sidergest123"));
        Assert.Equal(HttpStatusCode.BadRequest, own.StatusCode);
        Assert.Contains("too easy", await own.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, (await c.PostAsJsonAsync("/api/auth/password", new ChangePasswordRequest(Pw, name))).StatusCode);
    }
}
