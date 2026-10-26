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
}
