using System.Collections.Concurrent;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Purchasing;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Ebt.Api.Infrastructure;

namespace Ebt.Tests;

public sealed class RecordingReceiptHandler : IGoodsReceiptHandler
{
    public ConcurrentQueue<GoodsReceived> Events { get; } = new();
    public volatile bool Fail;

    public Task HandleAsync(GoodsReceived receipt, CancellationToken ct)
    {
        if (Fail) throw new InvalidOperationException("stock posting failed");
        Events.Enqueue(receipt);
        return Task.CompletedTask;
    }
}

public sealed class PurchasingFixture : IAsyncLifetime
{
    private readonly string server = Environment.GetEnvironmentVariable("EBT_TEST_PG") ?? "Host=localhost;Username=postgres";
    private readonly string database = $"ebt_test_{Guid.NewGuid():N}";
    private WebApplicationFactory<Program> factory = null!;

    public RecordingReceiptHandler Handler { get; } = new();
    public string ConnectionString => new NpgsqlConnectionStringBuilder(server) { Database = database }.ConnectionString;

    public int ReceivingLocationId { get; private set; }

    public async Task InitializeAsync()
    {
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(b => b
            .UseEnvironment("Testing")
            .UseSetting("ConnectionStrings:Ebt", ConnectionString)
            .UseSetting("Jwt:SigningKey", "test-signing-key-that-is-at-least-32-bytes-long")
            .UseSetting("Database:MigrateOnStartup", "true")
            .UseSetting("Logging:LogLevel:Default", "None")
            .UseSetting("Bootstrap:AdminUser", ApiFixture.AdminUser)
            .UseSetting("Bootstrap:AdminPassword", ApiFixture.AdminPassword)
            .ConfigureTestServices(s => s.AddSingleton<IGoodsReceiptHandler>(Handler)));
        factory.CreateClient().Dispose();
        await using var db = NewDb();
        var alm = new StockLocation { Code = StockReceiptHandler.DefaultLocationCode, Name = "Almoxarifado", Kind = StockLocationKind.Internal };
        db.StockLocations.Add(alm);
        await db.SaveChangesAsync();
        ReceivingLocationId = alm.Id;
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

    public Task<HttpClient> AdminAsync() => LoginAsync(ApiFixture.AdminUser, ApiFixture.AdminPassword);

    public async Task<HttpClient> LoginAsync(string username, string password)
    {
        var client = factory.CreateClient();
        var res = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(username, password));
        res.EnsureSuccessStatusCode();
        var login = (await res.Content.ReadFromJsonAsync<LoginResponse>(ApiFixture.Json))!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.Token);
        return client;
    }

    public async Task<HttpClient> UserAsync(UserRole role)
    {
        var admin = await AdminAsync();
        var name = $"{role.ToString().ToLower()}{Guid.NewGuid():N}"[..20];
        (await admin.Post("/api/users", new CreateUserRequest(name, "user-password-123", role))).EnsureSuccessStatusCode();
        return await LoginAsync(name, "user-password-123");
    }
}

[CollectionDefinition("purchasing")]
public class PurchasingCollection : ICollectionFixture<PurchasingFixture>;
