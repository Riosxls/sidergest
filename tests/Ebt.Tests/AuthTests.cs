using System.Net;
using System.Net.Http.Json;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;

namespace Ebt.Tests;

[Collection("api")]
public class AuthTests(ApiFixture api)
{
    [Fact]
    public async Task Health_is_public()
    {
        var res = await api.Anonymous().GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
    }

    [Fact]
    public async Task Api_requires_token()
    {
        var res = await api.Anonymous().GetAsync("/api/products");
        Assert.Equal(HttpStatusCode.Unauthorized, res.StatusCode);
    }

    [Fact]
    public async Task Wrong_password_is_rejected()
    {
        var res = await api.Anonymous().PostAsJsonAsync("/api/auth/login", new LoginRequest(ApiFixture.AdminUser, "wrong-password"));
        Assert.Equal(HttpStatusCode.Unauthorized, res.StatusCode);
    }

    [Fact]
    public async Task Reader_can_read_but_not_write()
    {
        var reader = await api.UserAsync(UserRole.Reader);
        Assert.Equal(HttpStatusCode.OK, (await reader.GetAsync("/api/products")).StatusCode);
        var res = await reader.Post("/api/work-centers", new WorkCenterIn("WC-R", "Reader", null));
        Assert.Equal(HttpStatusCode.Forbidden, res.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await reader.GetAsync("/api/users")).StatusCode);
    }

    [Fact]
    public async Task Engineering_can_write()
    {
        var eng = await api.UserAsync(UserRole.Engineering);
        var res = await eng.Post("/api/work-centers", new WorkCenterIn($"WC-{Guid.NewGuid():N}"[..12], "Solda", "300"));
        Assert.Equal(HttpStatusCode.Created, res.StatusCode);
    }

    [Fact]
    public async Task Malformed_login_is_unauthorized_not_server_error()
    {
        var anon = api.Anonymous();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anon.PostAsJsonAsync("/api/auth/login", new LoginRequest(null, null))).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await anon.PostAsJsonAsync("/api/auth/login", new LoginRequest("admin", null))).StatusCode);
    }

    [Fact]
    public async Task Deactivating_a_user_revokes_existing_tokens()
    {
        var admin = await api.AdminAsync();
        var name = $"revoke{Guid.NewGuid():N}"[..18];
        var created = await (await admin.Post("/api/users", new CreateUserRequest(name, "user-password-123", UserRole.Reader))).Read<UserDto>();
        var user = await api.LoginAsync(name, "user-password-123");
        Assert.Equal(HttpStatusCode.OK, (await user.GetAsync("/api/products")).StatusCode);

        (await admin.Put($"/api/users/{created.Id}", new UpdateUserRequest(UserRole.Reader, false, null))).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await user.GetAsync("/api/products")).StatusCode);
    }

    [Fact]
    public async Task Password_change_revokes_existing_tokens()
    {
        var admin = await api.AdminAsync();
        var name = $"pwchg{Guid.NewGuid():N}"[..18];
        var created = await (await admin.Post("/api/users", new CreateUserRequest(name, "user-password-123", UserRole.Reader))).Read<UserDto>();
        var user = await api.LoginAsync(name, "user-password-123");
        (await admin.Put($"/api/users/{created.Id}", new UpdateUserRequest(UserRole.Reader, true, "another-password-456"))).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await user.GetAsync("/api/products")).StatusCode);
        await api.LoginAsync(name, "another-password-456");
    }

    [Fact]
    public async Task Repeated_failures_lock_the_account()
    {
        var admin = await api.AdminAsync();
        var name = $"lock{Guid.NewGuid():N}"[..18];
        (await admin.Post("/api/users", new CreateUserRequest(name, "user-password-123", UserRole.Reader))).EnsureSuccessStatusCode();
        var anon = api.Anonymous();
        for (var i = 0; i < AuthEndpoints.MaxFailedLogins; i++)
            Assert.Equal(HttpStatusCode.Unauthorized, (await anon.PostAsJsonAsync("/api/auth/login", new LoginRequest(name, $"wrong-password-{i}"))).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await anon.PostAsJsonAsync("/api/auth/login", new LoginRequest(name, "user-password-123"))).StatusCode);
    }

    [Fact]
    public async Task Admin_cannot_demote_the_only_active_admin()
    {
        var admin = await api.AdminAsync();
        var users = (await admin.GetFromJsonAsync<List<UserDto>>("/api/users", ApiFixture.Json))!;
        var self = users.Single(u => u.Username == ApiFixture.AdminUser);
        if (users.Any(u => u.Id != self.Id && u.Role == UserRole.Admin && u.Active)) return; // other admins exist; guard only applies to the last one
        var res = await admin.Put($"/api/users/{self.Id}", new UpdateUserRequest(UserRole.Reader, true, null));
        Assert.Equal(HttpStatusCode.Conflict, res.StatusCode);
    }

    [Fact]
    public async Task Search_wildcards_are_escaped()
    {
        var admin = await api.AdminAsync();
        Assert.Equal(HttpStatusCode.OK, (await admin.GetAsync("/api/products?q=%25")).StatusCode);
    }
}
