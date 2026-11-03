using System.Text.Json;
using System.Threading.RateLimiting;

namespace Ebt.Api.Infrastructure;

/// <summary>
/// Rate limiting. Each sensitive route gets its own bucket so one cannot starve another:
/// login per IP + username (a guesser cannot spend the quota of the real user, and a shared office IP is not locked out by one typo-prone user),
/// refresh per IP with a larger quota (every open client refreshes about every 15 minutes), password change strict per user,
/// signed-in account actions per user. <c>RateLimit:LoginPerMinute</c> (tests) overrides all of the quotas.
/// </summary>
public static class RateLimiting
{
    private const string LoginUserItem = "login-username";

    public static void AddAppRateLimiter(this IServiceCollection services, IConfiguration config) => services.AddRateLimiter(o =>
    {
        o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
        var forced = config.GetValue<int?>("RateLimit:LoginPerMinute");
        var login = forced ?? 10;
        var refresh = forced ?? 60;
        var password = forced ?? 5;
        var account = forced ?? 30;
        static string Ip(HttpContext c) => c.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        static FixedWindowRateLimiterOptions Window(int permits) => new() { PermitLimit = permits, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 };

        o.AddPolicy(Policies.LoginLimiter, c => RateLimitPartition.GetFixedWindowLimiter($"login:{Ip(c)}|{c.Items[LoginUserItem] as string}", _ => Window(login)));
        o.AddPolicy(Policies.RefreshLimiter, c => RateLimitPartition.GetFixedWindowLimiter($"refresh:{Ip(c)}", _ => Window(refresh)));
        o.AddPolicy(Policies.PasswordLimiter, c => RateLimitPartition.GetFixedWindowLimiter($"password:{c.User.Identity?.Name ?? Ip(c)}", _ => Window(password)));
        o.AddPolicy(Policies.AccountLimiter, c => RateLimitPartition.GetFixedWindowLimiter($"account:{c.User.Identity?.Name ?? Ip(c)}", _ => Window(account)));

        // Backstop for the login route: changing the username on every try must not make the per-username buckets unlimited.
        o.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(c =>
            c.Request.Path.Equals("/api/auth/login", StringComparison.OrdinalIgnoreCase)
                ? RateLimitPartition.GetFixedWindowLimiter($"login-ip:{Ip(c)}", _ => Window(login * 5))
                : RateLimitPartition.GetNoLimiter("none"));
    });

    /// <summary>
    /// Runs before the limiter: reads the username out of the (small) login body so the limiter can partition on it, then rewinds the body.
    /// </summary>
    public static IApplicationBuilder UseLoginUsernameKey(this IApplicationBuilder app) => app.Use(async (ctx, next) =>
    {
        if (HttpMethods.IsPost(ctx.Request.Method) && ctx.Request.Path.Equals("/api/auth/login", StringComparison.OrdinalIgnoreCase)
            && ctx.Request.ContentLength is > 0 and <= 4096)
        {
            ctx.Request.EnableBuffering();
            try
            {
                using var doc = await JsonDocument.ParseAsync(ctx.Request.Body, cancellationToken: ctx.RequestAborted);
                if (doc.RootElement.ValueKind == JsonValueKind.Object)
                    foreach (var p in doc.RootElement.EnumerateObject())
                        if (p.Value.ValueKind == JsonValueKind.String && p.Name.Equals("username", StringComparison.OrdinalIgnoreCase))
                            ctx.Items[LoginUserItem] = p.Value.GetString()!.Trim().ToLowerInvariant();
            }
            catch (JsonException) { /* the endpoint answers the malformed body */ }
            ctx.Request.Body.Position = 0;
        }
        await next();
    });
}
