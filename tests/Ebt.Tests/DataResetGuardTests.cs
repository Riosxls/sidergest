using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Maintenance;

namespace Ebt.Tests;

[Collection("api")]
public class DataResetGuardTests(ApiFixture api)
{
    [Fact]
    public async Task Wipe_needs_the_admin_password()
    {
        var admin = await api.AdminAsync();
        var body = new DataResetIn([ResetScope.Sales], MaintenanceEndpoints.ConfirmWord);
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Post("/api/admin/data-reset", body)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await admin.Post("/api/admin/data-reset", body with { Password = "wrong-password" })).StatusCode);
    }

    [Fact]
    public async Task Wrong_passwords_on_a_destructive_action_lock_the_account_like_the_login_page()
    {
        var admin = await api.UserAsync(Ebt.Core.Entities.UserRole.Admin);
        var body = new DataResetIn([ResetScope.Sales], MaintenanceEndpoints.ConfirmWord, "wrong-password");
        for (var i = 0; i < AuthEndpoints.MaxFailedLogins; i++)
            Assert.Equal(HttpStatusCode.Forbidden, (await admin.Post("/api/admin/data-reset", body)).StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests, (await admin.Post("/api/admin/data-reset", body with { Password = "user-password-123" })).StatusCode);
    }

    [Fact]
    public async Task Parallel_wrong_passwords_are_all_counted()
    {
        var admin = await api.AdminAsync();
        var name = $"racer{Guid.NewGuid():N}"[..16];
        (await admin.Post("/api/users", new CreateUserRequest(name, "user-password-123", Ebt.Core.Entities.UserRole.Reader))).EnsureSuccessStatusCode();
        var anon = api.Anonymous();
        var attempts = await Task.WhenAll(Enumerable.Range(0, AuthEndpoints.MaxFailedLogins).Select(_ => anon.Post("/api/auth/login", new LoginRequest(name, "wrong-password-x"))));
        Assert.All(attempts, r => Assert.Equal(HttpStatusCode.Unauthorized, r.StatusCode));
        // Five simultaneous failures lock the account: the right password is refused too.
        Assert.Equal(HttpStatusCode.Unauthorized, (await anon.Post("/api/auth/login", new LoginRequest(name, "user-password-123"))).StatusCode);
    }

    [Fact]
    public void Wipe_is_refused_without_a_backup_made_in_the_last_hour()
    {
        var now = DateTimeOffset.UtcNow;
        Assert.Null(MaintenanceEndpoints.BackupBlock(null, now));
        var dir = Directory.CreateTempSubdirectory().FullName;
        try
        {
            Assert.NotNull(MaintenanceEndpoints.BackupBlock(dir, now));
            File.WriteAllText(Path.Combine(dir, "status.json"), $"{{\"count\":1,\"lastBackupAt\":\"{now.AddMinutes(-30):O}\"}}");
            Assert.Null(MaintenanceEndpoints.BackupBlock(dir, now));
            File.WriteAllText(Path.Combine(dir, "status.json"), $"{{\"count\":1,\"lastBackupAt\":\"{now.AddHours(-2):O}\"}}");
            Assert.NotNull(MaintenanceEndpoints.BackupBlock(dir, now));
        }
        finally { Directory.Delete(dir, true); }
    }
}
