using System.Net;
using System.Net.Http.Json;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Ebt.Tests;

/// <summary>Fallback authorization, rate-limit buckets, the user cache, audit coverage and idempotency keys.</summary>
[Collection("api")]
public class SecurityHardeningTests(ApiFixture api)
{
    private static string Name() => $"sec{Guid.NewGuid():N}"[..16];

    // ---- fallback authorization -------------------------------------------------------------------------------------------------------------

    /// <summary>The only endpoints a visitor without a token may call. Anything else must be rejected by the fallback policy.</summary>
    private static readonly string[] AnonymousAllowList = ["GET /", "GET /health", "GET /health/ready", "POST /api/auth/login", "POST /api/auth/refresh", "POST /api/auth/logout"];

    [Fact]
    public async Task Every_endpoint_requires_sign_in_except_the_explicit_allow_list()
    {
        using var scope = api.CreateScope();
        var fallback = await scope.ServiceProvider.GetRequiredService<IAuthorizationPolicyProvider>().GetFallbackPolicyAsync();
        Assert.NotNull(fallback);
        Assert.Contains(fallback!.Requirements, r => r is Microsoft.AspNetCore.Authorization.Infrastructure.DenyAnonymousAuthorizationRequirement);

        var anonymous = new List<string>();
        var total = 0;
        foreach (var e in scope.ServiceProvider.GetRequiredService<EndpointDataSource>().Endpoints.OfType<RouteEndpoint>())
        {
            total++;
            if (e.Metadata.GetMetadata<IAllowAnonymous>() is null) continue;
            var methods = e.Metadata.GetMetadata<Microsoft.AspNetCore.Routing.HttpMethodMetadata>()?.HttpMethods ?? ["*"];
            foreach (var m in methods) anonymous.Add($"{m} /{e.RoutePattern.RawText?.TrimStart('/')}");
        }
        Assert.True(total > 100, "the endpoint list should not be empty");
        Assert.Empty(anonymous.Where(a => !AnonymousAllowList.Contains(a)).ToList());
        Assert.Equal(AnonymousAllowList.Order(), anonymous.Order()); // and the allow-list holds nothing that no longer exists
    }

    [Fact]
    public async Task A_visitor_without_a_token_is_turned_away()
    {
        var visitor = api.Anonymous();
        Assert.Equal(HttpStatusCode.Unauthorized, (await visitor.GetAsync("/api/search?q=abc")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await visitor.GetAsync("/api/customers")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await visitor.GetAsync("/health")).StatusCode);
    }

    // ---- rate limiting -------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task Login_attempts_are_limited_per_username_and_do_not_use_up_the_refresh_bucket()
    {
        var host = api.Anonymous(new Dictionary<string, string> { ["RateLimit:LoginPerMinute"] = "3" });
        var a = Name();
        var b = Name();
        for (var i = 0; i < 3; i++) Assert.Equal(HttpStatusCode.Unauthorized, (await host.PostAsJsonAsync("/api/auth/login", new LoginRequest(a, "wrong-password-1"))).StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests, (await host.PostAsJsonAsync("/api/auth/login", new LoginRequest(a, "wrong-password-1"))).StatusCode);
        // Same IP, another account: its own bucket.
        Assert.Equal(HttpStatusCode.Unauthorized, (await host.PostAsJsonAsync("/api/auth/login", new LoginRequest(b, "wrong-password-1"))).StatusCode);
        // Refresh has a bucket of its own.
        Assert.Equal(HttpStatusCode.Unauthorized, (await host.PostAsJsonAsync("/api/auth/refresh", new RefreshRequest("not-a-token"))).StatusCode);
        // The username is read case-insensitively and trimmed, so a variant does not get a fresh bucket.
        Assert.Equal(HttpStatusCode.TooManyRequests, (await host.PostAsJsonAsync("/api/auth/login", new LoginRequest("  " + a.ToUpperInvariant() + " ", "wrong-password-1"))).StatusCode);
    }

    [Fact]
    public async Task Password_change_is_limited_per_user()
    {
        var admin = await api.AdminAsync();
        var name = Name();
        (await admin.Post("/api/users", new CreateUserRequest(name, "user-password-123", UserRole.Reader))).EnsureSuccessStatusCode();
        var host = api.Anonymous(new Dictionary<string, string> { ["RateLimit:LoginPerMinute"] = "2" });
        var login = await (await host.PostAsJsonAsync("/api/auth/login", new LoginRequest(name, "user-password-123"))).Read<LoginResponse>();
        host.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", login.Token);
        for (var i = 0; i < 2; i++) Assert.Equal(HttpStatusCode.BadRequest, (await host.Post("/api/auth/password", new ChangePasswordRequest("wrong-current-pw", "another-password-9"))).StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests, (await host.Post("/api/auth/password", new ChangePasswordRequest("wrong-current-pw", "another-password-9"))).StatusCode);
    }

    // ---- user cache ----------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task Deactivating_a_user_through_the_api_takes_effect_at_once_even_with_the_cache_on()
    {
        var name = Name();
        var host = api.Anonymous(new Dictionary<string, string> { ["Auth:UserCacheSeconds"] = "60" });
        // A single HttpClient cannot hold two identities, so the admin acts with per-request headers on the same host.
        var adminLogin = await (await host.PostAsJsonAsync("/api/auth/login", new LoginRequest(ApiFixture.AdminUser, ApiFixture.AdminPassword))).Read<LoginResponse>();
        HttpRequestMessage As(string token, HttpMethod method, string url, object? body = null) =>
            new(method, url) { Headers = { Authorization = new("Bearer", token) }, Content = body is null ? null : JsonContent.Create(body, options: ApiFixture.Json) };
        var created = await (await host.SendAsync(As(adminLogin.Token, HttpMethod.Post, "/api/users", new CreateUserRequest(name, "user-password-123", UserRole.Reader)))).Read<UserDto>();
        var userLogin = await (await host.PostAsJsonAsync("/api/auth/login", new LoginRequest(name, "user-password-123"))).Read<LoginResponse>();

        Assert.Equal(HttpStatusCode.OK, (await host.SendAsync(As(userLogin.Token, HttpMethod.Get, "/api/auth/me"))).StatusCode);
        // Behind the API's back: still served from the cache.
        await using (var db = api.NewDb())
            await db.Users.Where(u => u.Id == created.Id).ExecuteUpdateAsync(s => s.SetProperty(u => u.Active, false));
        Assert.Equal(HttpStatusCode.OK, (await host.SendAsync(As(userLogin.Token, HttpMethod.Get, "/api/auth/me"))).StatusCode);
        await using (var db = api.NewDb())
            await db.Users.Where(u => u.Id == created.Id).ExecuteUpdateAsync(s => s.SetProperty(u => u.Active, true));

        // Through the API: effective at once.
        (await host.SendAsync(As(adminLogin.Token, HttpMethod.Put, $"/api/users/{created.Id}", new UpdateUserRequest(UserRole.Reader, false, null)))).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await host.SendAsync(As(userLogin.Token, HttpMethod.Get, "/api/auth/me"))).StatusCode);    }

    // ---- audit ---------------------------------------------------------------------------------------------------------------------------------

    private sealed class FakeUser(string? name) : ICurrentUser { public string? Name { get; } = name; }

    private EbtDbContext AuditedDb(string? user)
    {
        var options = new DbContextOptionsBuilder<EbtDbContext>().UseNpgsql(api.ConnectionString).UseSnakeCaseNamingConvention()
            .AddInterceptors(new AuditInterceptor(new FakeUser(user))).Options;
        return new EbtDbContext(options);
    }

    [Fact]
    public async Task Quote_and_stock_document_status_changes_and_a_quote_delete_are_audited()
    {
        var customerName = "Cliente " + Name();
        int quoteId, docId;
        await using (var db = AuditedDb("auditor"))
        {
            var customer = new Customer { Name = customerName };
            db.Customers.Add(customer);
            await db.SaveChangesAsync();
            var quote = new Quote { Reference = "PROP T" + Name(), Number = Random.Shared.Next(900_000, int.MaxValue), CustomerId = customer.Id, Status = QuoteStatus.Draft };
            var doc = new StockDocument { Type = MovementType.AdjustmentIn, Date = DateOnly.FromDateTime(DateTime.UtcNow), Reference = "DOC " + Name(), CreatedBy = "auditor", CreatedAt = DateTimeOffset.UtcNow };
            db.Quotes.Add(quote);
            db.StockDocuments.Add(doc);
            await db.SaveChangesAsync();
            quoteId = quote.Id;
            docId = doc.Id;
            quote.Status = QuoteStatus.Cancelled;
            doc.Reversed = true;
            await db.SaveChangesAsync();
            db.Quotes.Remove(quote);
            await db.SaveChangesAsync();
        }
        await using var read = api.NewDb();
        var quoteRows = await read.AuditLog.Where(a => a.Entity == "Quote" && a.EntityId == quoteId.ToString()).OrderBy(a => a.Id).ToListAsync();
        Assert.Equal(["Status", "Delete"], quoteRows.Select(a => a.Action));
        Assert.All(quoteRows, a => Assert.Equal("auditor", a.User));
        Assert.Contains($"\"to\":{(int)QuoteStatus.Cancelled}", quoteRows[0].Changes.Replace(" ", ""));
        Assert.Contains("PROP T", quoteRows[1].Changes);
        var docRows = await read.AuditLog.Where(a => a.Entity == "StockDocument" && a.EntityId == docId.ToString()).ToListAsync();
        var status = Assert.Single(docRows);
        Assert.Equal("Status", status.Action);
        Assert.Contains("Reversed", status.Changes);
    }

    [Fact]
    public async Task An_insert_and_its_audit_row_commit_together_or_not_at_all()
    {
        // The audit row is written by a second SaveChanges; a user name longer than the column makes that one fail.
        var customerName = "Atomico " + Name();
        await using (var db = AuditedDb(new string('x', 300)))
        {
            db.Customers.Add(new Customer { Name = customerName });
            await Assert.ThrowsAnyAsync<Exception>(() => db.SaveChangesAsync());
        }
        await using var read = api.NewDb();
        Assert.False(await read.Customers.AnyAsync(c => c.Name == customerName), "the customer must not stay behind without its audit row");

        await using (var db = AuditedDb("auditor"))
        {
            db.Customers.Add(new Customer { Name = customerName });
            await db.SaveChangesAsync();
        }
        var id = (await read.Customers.SingleAsync(c => c.Name == customerName)).Id;
        Assert.True(await read.AuditLog.AnyAsync(a => a.Entity == "Customer" && a.EntityId == id.ToString() && a.Action == "Insert"));
    }

    // ---- idempotency ---------------------------------------------------------------------------------------------------------------------------

    private static HttpRequestMessage Keyed(string key, string name) =>
        new(HttpMethod.Post, "/api/customers") { Headers = { { "Idempotency-Key", key } }, Content = JsonContent.Create(new CustomerIn(name, null, null, ConsumerType.Normal), options: ApiFixture.Json) };

    private static async Task<int> CountAsync(HttpClient admin, string name) =>
        (await (await admin.GetAsync("/api/customers?q=" + Uri.EscapeDataString(name))).Read<Page<CustomerOut>>()).Items.Count(c => c.Name == name);

    [Fact]
    public async Task A_repeated_idempotency_key_returns_the_stored_response_without_running_again()
    {
        var admin = await api.AdminAsync();
        var name = "Idem " + Name();
        var key = Guid.NewGuid().ToString();

        var first = await admin.SendAsync(Keyed(key, name));
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        Assert.False(first.Headers.Contains("Idempotent-Replay"));
        var firstBody = await first.Content.ReadAsStringAsync();

        var second = await admin.SendAsync(Keyed(key, name));
        Assert.Equal(HttpStatusCode.Created, second.StatusCode);
        Assert.Equal("true", second.Headers.GetValues("Idempotent-Replay").Single());
        Assert.Equal(firstBody, await second.Content.ReadAsStringAsync());
        Assert.Equal(1, await CountAsync(admin, name));

        // No header: nothing changes, the request runs each time.
        var plain = () => admin.PostAsJsonAsync("/api/customers", new CustomerIn(name + " b", null, null, ConsumerType.Normal), ApiFixture.Json);
        Assert.Equal(HttpStatusCode.Created, (await plain()).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await plain()).StatusCode);
        Assert.Equal(2, await CountAsync(admin, name + " b"));
    }

    [Fact]
    public async Task The_same_key_with_another_body_or_path_is_refused_and_keys_belong_to_one_user()
    {
        var admin = await api.AdminAsync();
        var key = Guid.NewGuid().ToString();
        var name = "Idem " + Name();
        Assert.Equal(HttpStatusCode.Created, (await admin.SendAsync(Keyed(key, name))).StatusCode);

        var otherBody = await admin.SendAsync(Keyed(key, name + " changed"));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, otherBody.StatusCode);
        Assert.Contains("idempot", (await otherBody.Content.ReadAsStringAsync()).ToLowerInvariant());
        Assert.Equal(0, await CountAsync(admin, name + " changed"));

        var otherPath = new HttpRequestMessage(HttpMethod.Post, "/api/suppliers") { Headers = { { "Idempotency-Key", key } }, Content = JsonContent.Create(new { name }) };
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await admin.SendAsync(otherPath)).StatusCode);

        // Another user may use the same value: the key is scoped to the signed-in user.
        var sales = await api.UserAsync(UserRole.SalesManager);
        var fresh = await sales.SendAsync(Keyed(key, name + " sales"));
        Assert.Equal(HttpStatusCode.Created, fresh.StatusCode);
        Assert.False(fresh.Headers.Contains("Idempotent-Replay"));
    }

    [Fact]
    public async Task A_key_still_in_flight_gets_409_and_a_dead_one_does_not_block()
    {
        var admin = await api.AdminAsync();
        var name = "Idem " + Name();
        var key = Guid.NewGuid().ToString();
        int userId;
        await using (var db = api.NewDb())
        {
            userId = await db.Users.Where(u => u.Username == ApiFixture.AdminUser).Select(u => u.Id).SingleAsync();
            var body = JsonContent.Create(new CustomerIn(name, null, null, ConsumerType.Normal), options: ApiFixture.Json);
            var hash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(await body.ReadAsByteArrayAsync())).ToLowerInvariant();
            db.IdempotencyKeys.Add(new IdempotencyKey { UserId = userId, Key = key, Method = "POST", Path = "/api/customers", BodyHash = hash, CreatedAt = DateTimeOffset.UtcNow, ExpiresAt = DateTimeOffset.UtcNow.AddHours(24) });
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.Conflict, (await admin.SendAsync(Keyed(key, name))).StatusCode);
        Assert.Equal(0, await CountAsync(admin, name));

        // The request that owned the key died (older than the in-flight limit): the retry runs.
        await using (var db = api.NewDb())
            await db.IdempotencyKeys.Where(k => k.Key == key).ExecuteUpdateAsync(s => s.SetProperty(k => k.CreatedAt, DateTimeOffset.UtcNow.AddMinutes(-10)));
        Assert.Equal(HttpStatusCode.Created, (await admin.SendAsync(Keyed(key, name))).StatusCode);
        Assert.Equal(1, await CountAsync(admin, name));
    }

    [Fact]
    public async Task Failed_requests_are_replayed_too_but_a_malformed_key_is_rejected()
    {
        var admin = await api.AdminAsync();
        var key = Guid.NewGuid().ToString();
        HttpRequestMessage Bad() => new(HttpMethod.Post, "/api/customers") { Headers = { { "Idempotency-Key", key } }, Content = JsonContent.Create(new CustomerIn("", null, null, ConsumerType.Normal), options: ApiFixture.Json) };
        var first = await admin.SendAsync(Bad());
        Assert.Equal(HttpStatusCode.BadRequest, first.StatusCode);
        var second = await admin.SendAsync(Bad());
        Assert.Equal(HttpStatusCode.BadRequest, second.StatusCode);
        Assert.Equal("true", second.Headers.GetValues("Idempotent-Replay").Single());

        var bad = new HttpRequestMessage(HttpMethod.Post, "/api/customers") { Headers = { { "Idempotency-Key", "x y" } }, Content = JsonContent.Create(new CustomerIn("n", null, null, ConsumerType.Normal), options: ApiFixture.Json) };
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.SendAsync(bad)).StatusCode);

        // Reads ignore the header.
        var get = new HttpRequestMessage(HttpMethod.Get, "/api/customers") { Headers = { { "Idempotency-Key", key } } };
        var res = await admin.SendAsync(get);
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        Assert.False(res.Headers.Contains("Idempotent-Replay"));
    }
}
