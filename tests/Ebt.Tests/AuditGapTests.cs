using System.Net;
using System.Net.Http.Json;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;

namespace Ebt.Tests;

/// <summary>Events that used to leave no audit row: password reset/change, unlock, session sign-out, lockout and address removal.</summary>
[Collection("api")]
public class AuditGapTests(ApiFixture api)
{
    private async Task<List<AuditOut>> RowsAsync(HttpClient admin, string entity, string id) =>
        (await (await admin.GetAsync($"/api/audit?entity={entity}&entityId={id}")).Read<Page<AuditOut>>()).Items.ToList();

    private async Task<(string Name, int Id)> NewUserAsync(HttpClient admin)
    {
        var name = $"aud{Guid.NewGuid():N}"[..18];
        var created = await (await admin.Post("/api/users", new CreateUserRequest(name, "user-password-123", UserRole.Reader))).Read<UserDto>();
        return (name, created.Id);
    }

    [Fact]
    public async Task Password_reset_unlock_and_own_change_are_audited_without_secrets()
    {
        var admin = await api.AdminAsync();
        var (name, id) = await NewUserAsync(admin);

        (await admin.Put($"/api/users/{id}", new UpdateUserRequest(UserRole.Reader, true, "another-password-456"))).EnsureSuccessStatusCode();
        (await admin.PostAsync($"/api/users/{id}/unlock", null)).EnsureSuccessStatusCode();
        var user = await api.LoginAsync(name, "another-password-456");
        (await user.Post("/api/auth/password", new ChangePasswordRequest("another-password-456", "brand-new-pass-1"))).EnsureSuccessStatusCode();

        var rows = await RowsAsync(admin, "AppUser", id.ToString());
        Assert.Contains(rows, a => a.Action == "PasswordReset" && a.User == "admin");
        Assert.Contains(rows, a => a.Action == "Unlock" && a.User == "admin");
        Assert.Contains(rows, a => a.Action == "PasswordChange" && a.User == name);
        Assert.DoesNotContain(rows, a => a.Changes.Contains("another-password") || a.Changes.Contains("brand-new"));
    }

    [Fact]
    public async Task Lockout_and_signing_other_devices_out_are_audited()
    {
        var admin = await api.AdminAsync();
        var (name, id) = await NewUserAsync(admin);
        for (var i = 0; i < AuthEndpoints.MaxFailedLogins; i++)
            await api.Anonymous().PostAsJsonAsync("/api/auth/login", new LoginRequest(name, "wrong-password-x"));
        Assert.Contains(await RowsAsync(admin, "AppUser", id.ToString()), a => a.Action == "Lockout");

        (await admin.PostAsync($"/api/users/{id}/unlock", null)).EnsureSuccessStatusCode();
        var user = await api.LoginAsync(name, "user-password-123");
        var login = await (await api.Anonymous().PostAsJsonAsync("/api/auth/login", new LoginRequest(name, "user-password-123"))).Read<LoginResponse>();
        (await user.Post("/api/auth/sessions/revoke-others", new SessionsRequest(login.RefreshToken))).EnsureSuccessStatusCode();
        Assert.Contains(await RowsAsync(admin, "AppUser", id.ToString()), a => a.Action == "SessionsRevoked");
    }

    [Fact]
    public async Task Removing_an_address_is_audited()
    {
        var admin = await api.AdminAsync();
        var customer = await (await admin.Post("/api/customers", new CustomerIn("Cliente " + Guid.NewGuid().ToString("N")[..8], null, null, ConsumerType.Normal))).Read<CustomerOut>();
        var address = await (await admin.Post($"/api/customers/{customer.Id}/addresses", new CustomerAddressIn("26133636000103", "SP", null, "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", "3515004", "06800000", "5101", "Edilto", "compras@cliente.com", null))).Read<CustomerAddressOut>();
        Assert.Equal(HttpStatusCode.NoContent, (await admin.DeleteAsync($"/api/customers/{customer.Id}/addresses/{address.Id}")).StatusCode);
        Assert.Contains(await RowsAsync(admin, "CustomerAddress", address.Id.ToString()), a => a.Action == "Delete");
    }
}
