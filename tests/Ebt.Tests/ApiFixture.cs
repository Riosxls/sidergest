using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Ebt.Tests;

public sealed class ApiFixture : IAsyncLifetime
{
    public const string AdminUser = "admin";
    public const string AdminPassword = "test-admin-password";
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { Converters = { new JsonStringEnumConverter() } };

    private readonly string server = Environment.GetEnvironmentVariable("EBT_TEST_PG") ?? "Host=localhost;Username=postgres";
    private readonly string database = $"ebt_test_{Guid.NewGuid():N}";
    private WebApplicationFactory<Program> factory = null!;

    public string ConnectionString => new NpgsqlConnectionStringBuilder(server) { Database = database }.ConnectionString;

    public Task InitializeAsync()
    {
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(b => b
            .UseEnvironment("Testing")
            .UseSetting("ConnectionStrings:Ebt", ConnectionString)
            .UseSetting("Jwt:SigningKey", "test-signing-key-that-is-at-least-32-bytes-long")
            .UseSetting("Database:MigrateOnStartup", "true")
            .UseSetting("Logging:LogLevel:Default", Environment.GetEnvironmentVariable("EBT_TEST_LOG") ?? "None")
            .UseSetting("RateLimit:LoginPerMinute", "100000")
            .UseSetting("Bootstrap:AdminUser", AdminUser)
            .UseSetting("Bootstrap:AdminPassword", AdminPassword));
        factory.CreateClient().Dispose();
        return Task.CompletedTask;
    }

    public async Task DisposeAsync()
    {
        await factory.DisposeAsync();
        NpgsqlConnection.ClearAllPools();
        await using var conn = new NpgsqlConnection(server);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{database}\" WITH (FORCE)", conn);
        await cmd.ExecuteNonQueryAsync();
    }

    public EbtDbContext NewDb() => new(DesignTimeFactory.Create(ConnectionString));

    public HttpClient Anonymous() => factory.CreateClient();

    public async Task<HttpClient> AdminAsync() => await LoginAsync(AdminUser, AdminPassword);

    public async Task<HttpClient> LoginAsync(string username, string password)
    {
        var client = factory.CreateClient();
        var res = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, password));
        res.EnsureSuccessStatusCode();
        var login = (await res.Content.ReadFromJsonAsync<LoginResponse>(Json))!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.Token);
        return client;
    }

    public async Task<HttpClient> UserAsync(UserRole role)
    {
        var admin = await AdminAsync();
        var name = $"{role.ToString().ToLower()}{Guid.NewGuid():N}"[..20];
        (await admin.PostAsJsonAsync("/api/users", new CreateUserRequest(name, "user-password-123", role), Json)).EnsureSuccessStatusCode();
        return await LoginAsync(name, "user-password-123");
    }
}

[CollectionDefinition("api")]
public class ApiCollection : ICollectionFixture<ApiFixture>;

public static class HttpExtensions
{
    public static async Task<T> Read<T>(this HttpResponseMessage res)
    {
        if (!res.IsSuccessStatusCode) throw new HttpRequestException($"{(int)res.StatusCode}: {await res.Content.ReadAsStringAsync()}");
        return (await res.Content.ReadFromJsonAsync<T>(ApiFixture.Json))!;
    }

    public static Task<HttpResponseMessage> Post<T>(this HttpClient c, string url, T body) => c.PostAsJsonAsync(url, body, ApiFixture.Json);
    public static Task<HttpResponseMessage> Put<T>(this HttpClient c, string url, T body) => c.PutAsJsonAsync(url, body, ApiFixture.Json);
}
