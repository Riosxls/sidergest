using System.IdentityModel.Tokens.Jwt;
using System.Net.Mail;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

namespace Ebt.Api.Infrastructure;

public static class Policies
{
    public const string Read = "read";
    public const string Write = "write";
    public const string Admin = "admin";
    public const string Stock = "stock";
    public const string LoginLimiter = "login";
    public const string AccountLimiter = "account";
    public const string RefreshLimiter = "refresh";
    public const string PasswordLimiter = "password";
}

public class JwtOptions
{
    public string Issuer { get; set; } = "ebt-erp";
    public string Audience { get; set; } = "ebt-erp-clients";
    public string SigningKey { get; set; } = "";
    public int ExpiresMinutes { get; set; } = 15;
    public int RefreshDays { get; set; } = 14;
    public int ClockSkewSeconds { get; set; } = 60;

    /// <summary>A just-rotated refresh token that comes back within this many seconds is a second tab or a retry, not theft.</summary>
    public int RefreshReuseGraceSeconds { get; set; } = 20;
}

public class TokenService(JwtOptions options)
{
    public const string VersionClaim = "tv";

    /// <summary>Clients report activity about once a minute; this much lateness is not idleness.</summary>
    public static readonly TimeSpan IdleSlack = TimeSpan.FromMinutes(2);

    public const int MaxIdleMinutesLimit = 480;

    /// <summary>The cap the admin set (Security:MaxIdleMinutes); 0 = no cap.</summary>
    public static int MaxIdle(IConfiguration config) => Math.Clamp(config.GetValue("Security:MaxIdleMinutes", 0), 0, MaxIdleMinutesLimit);

    /// <summary>The user's choice, except that with a cap "never" (0) and anything above the cap become the cap.</summary>
    public static int EffectiveIdle(int userMinutes, int cap) => cap > 0 && (userMinutes <= 0 || userMinutes > cap) ? cap : userMinutes;

    public static bool IsIdle(int idleLockMinutes, DateTimeOffset? lastActivity, DateTimeOffset now) =>
        idleLockMinutes > 0 && lastActivity is { } last && now - last > TimeSpan.FromMinutes(idleLockMinutes) + IdleSlack;

    public TimeSpan ReuseGrace => TimeSpan.FromSeconds(Math.Max(0, options.RefreshReuseGraceSeconds));

    public static string HashRefresh(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token))).ToLowerInvariant();

    /// <summary>Creates, stores and returns a new opaque refresh token for the user (only its hash is persisted).</summary>
    public async Task<(string Token, DateTimeOffset ExpiresAt)> NewRefreshAsync(AppUser user, EbtDbContext db, CancellationToken ct, DeviceInfo? device = null, bool isLogin = false)
    {
        var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        var now = DateTimeOffset.UtcNow;
        var expires = now.AddDays(options.RefreshDays);
        db.RefreshTokens.Add(new RefreshToken { UserId = user.Id, TokenHash = HashRefresh(token), CreatedAt = now, ExpiresAt = expires, Device = device?.Device, UserAgent = device?.UserAgent, Ip = device?.Ip, IsLogin = isLogin });
        await db.RefreshTokens.Where(r => r.UserId == user.Id && r.ExpiresAt < now).ExecuteDeleteAsync(ct);
        await db.SaveChangesAsync(ct);
        return (token, expires);
    }

    public (string Token, DateTimeOffset ExpiresAt) Issue(AppUser user)
    {
        var expires = DateTimeOffset.UtcNow.AddMinutes(options.ExpiresMinutes);
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.Username),
            new Claim(ClaimTypes.Role, user.Role.ToString()),
            new Claim(VersionClaim, user.TokenVersion.ToString())
        };
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(options.SigningKey));
        var token = new JwtSecurityToken(options.Issuer, options.Audience, claims, expires: expires.UtcDateTime,
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return (new JwtSecurityTokenHandler().WriteToken(token), expires);
    }

    /// <summary>Rejects tokens of deactivated users, or issued before a password, role or status change.</summary>
    public static async Task ValidateAsync(TokenValidatedContext ctx)
    {
        var principal = ctx.Principal;
        var db = ctx.HttpContext.RequestServices.GetRequiredService<EbtDbContext>();
        if (!int.TryParse(principal?.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id)
            || !int.TryParse(principal.FindFirstValue(VersionClaim), out var version))
        {
            ctx.Fail("Invalid token");
            return;
        }
        var cap = MaxIdle(ctx.HttpContext.RequestServices.GetRequiredService<IConfiguration>());
        var cache = ctx.HttpContext.RequestServices.GetRequiredService<UserCache>();
        var user = cache.TryGet(id);
        if (user is null)
        {
            var readAt = cache.Generation;
            user = await db.Users.AsNoTracking().Where(u => u.Id == id).Select(u => new UserCache.Entry(u.Active, u.TokenVersion, u.IdleLockMinutes, u.LastActivityAt)).FirstOrDefaultAsync(ctx.HttpContext.RequestAborted);
            if (user is not null) cache.Set(id, user, readAt);
        }
        if (user is null || !user.Active || user.TokenVersion != version) ctx.Fail("Token revoked");
        else if (IsIdle(EffectiveIdle(user.IdleLockMinutes, cap), user.LastActivityAt, DateTimeOffset.UtcNow)) ctx.Fail("Idle session");
    }
}

/// <summary>
/// The few user columns that token validation needs, kept for a few seconds so a burst of requests does not query the same row each time
/// (Auth:UserCacheSeconds, 0 = off). Every writer of these columns calls <see cref="Invalidate"/> after saving, so a password change, role or
/// status change, revoke or idle-lock edit takes effect at once; the lock time itself tolerates the same few seconds (the idle slack is minutes).
/// In-process: valid because a single API instance serves the database.
/// </summary>
public sealed class UserCache(IConfiguration config)
{
    public sealed record Entry(bool Active, int TokenVersion, int IdleLockMinutes, DateTimeOffset? LastActivityAt);

    private readonly TimeSpan ttl = TimeSpan.FromSeconds(Math.Clamp(config.GetValue("Auth:UserCacheSeconds", 10), 0, 60));
    private readonly System.Collections.Concurrent.ConcurrentDictionary<int, (Entry Value, DateTime Expires)> items = new();

    public Entry? TryGet(int id) =>
        ttl > TimeSpan.Zero && items.TryGetValue(id, out var hit) && hit.Expires > DateTime.UtcNow ? hit.Value : null;

    private long generation;

    /// <summary>Read before querying the row and pass to <see cref="Set"/>: an invalidation in between (a write racing the read) makes the stale row be dropped.</summary>
    public long Generation => Interlocked.Read(ref generation);

    public void Set(int id, Entry value, long readAt)
    {
        if (ttl <= TimeSpan.Zero || readAt != Generation) return;
        if (items.Count > 1000) items.Clear(); // a few dozen users in practice; never grows without bound
        items[id] = (value, DateTime.UtcNow + ttl);
    }

    public void Invalidate(int id)
    {
        Interlocked.Increment(ref generation);
        items.TryRemove(id, out _);
    }
}

public record DeviceInfo(string? Device, string? UserAgent, string? Ip)
{
    public static DeviceInfo From(string? device, HttpContext http)
    {
        // Client-controlled text: drop control characters (log injection, broken layouts) before trimming and cutting.
        static string? Cut(string? s, int max)
        {
            var clean = s is null ? "" : new string(s.Where(c => !char.IsControl(c)).ToArray()).Trim();
            return clean.Length == 0 ? null : clean[..Math.Min(max, clean.Length)];
        }
        return new(Cut(device, 120), Cut(http.Request.Headers.UserAgent.ToString(), 200), Cut(http.Connection.RemoteIpAddress?.ToString(), 45));
    }
}

public record LoginRequest(string? Username, string? Password, string? Device = null);
public record SessionsRequest(string? RefreshToken);
public record SessionDto(long Id, string? Device, string? UserAgent, string? Ip, DateTimeOffset CreatedAt, DateTimeOffset ExpiresAt, bool Current);
public record IdleLockRequest(int Minutes);
public record ProfileRequest(string? DisplayName, string? Email);
public record LoginResponse(string Token, DateTimeOffset ExpiresAt, string Username, UserRole Role, string[] Permissions, string RefreshToken, DateTimeOffset RefreshExpiresAt, int IdleLockMinutes = 0, int MaxIdleMinutes = 0, DateTimeOffset? PreviousLoginAt = null);
public record LoginEntryDto(DateTimeOffset At, string? Device, string? UserAgent, string? Ip, bool Current);
public record MyChangeDto(DateTimeOffset At, string Entity, string? EntityId, string Action, string? Summary);
public record MyActivityDto(List<LoginEntryDto> Logins, List<MyChangeDto> Changes);
public record NotificationPrefsDto(string[]? MutedAlerts, bool HideLegacy);
public record RefreshRequest(string? RefreshToken);
public record ChangePasswordRequest(string? CurrentPassword, string? NewPassword);
public record UserDto(int Id, string Username, UserRole Role, bool Active, bool Locked = false, string? DisplayName = null, string? Email = null);
public record CreateUserRequest(string Username, string Password, UserRole Role);
public record UpdateUserRequest(UserRole Role, bool Active, string? Password);

public static class AuthEndpoints
{
    public const int MinPasswordLength = 10;
    public const int MaxFailedLogins = 5;
    public static readonly TimeSpan LockoutDuration = TimeSpan.FromMinutes(15);

    /// <summary>
    /// Counts one wrong password. The increment runs in the database, so parallel guesses are all counted (a read-modify-write on a loaded
    /// entity would let ten simultaneous attempts count as one). Returns true when this failure locked the account.
    /// </summary>
    public static async Task<bool> RecordFailureAsync(EbtDbContext db, int userId, DateTimeOffset now, CancellationToken ct)
    {
        await db.Users.Where(u => u.Id == userId).ExecuteUpdateAsync(s => s.SetProperty(u => u.FailedLogins, u => u.FailedLogins + 1), ct);
        var locked = await db.Users.Where(u => u.Id == userId && u.FailedLogins >= MaxFailedLogins)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.LockedUntil, now + LockoutDuration).SetProperty(u => u.FailedLogins, 0), ct);
        if (locked == 0) return false;
        var name = await db.Users.AsNoTracking().Where(u => u.Id == userId).Select(u => u.Username).FirstOrDefaultAsync(ct);
        AuditSecurity(db, name, userId, "Lockout", new { until = now + LockoutDuration });
        await db.SaveChangesAsync(ct);
        return true;
    }

    /// <summary>
    /// Writes one audit row for a security event. The generic audit skips password, lockout and token columns, so a reset, an unlock or a
    /// sign-out of other devices would otherwise leave no trace. Added to the context only: the caller's SaveChanges writes it.
    /// </summary>
    public static void AuditSecurity(EbtDbContext db, string? actor, int targetId, string action, object details) =>
        db.AuditLog.Add(new AuditEntry
        {
            At = DateTimeOffset.UtcNow, User = actor, Entity = "AppUser", EntityId = targetId.ToString(), Action = action,
            Changes = JsonSerializer.Serialize(details)
        });

    /// <summary>
    /// Asks again for the signed-in user's password before a destructive action (cancel an NF, wipe data). Wrong attempts count toward the same
    /// lockout as the login page, so a stolen access token cannot be used to guess the password. Null means the password was right.
    /// </summary>
    public static async Task<IResult?> ReauthAsync(EbtDbContext db, ClaimsPrincipal principal, string? password, CancellationToken ct)
    {
        var who = principal.Identity?.Name;
        var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Username == who && u.Active, ct);
        if (user is null) return Results.Problem("Wrong password", statusCode: StatusCodes.Status403Forbidden);
        var now = DateTimeOffset.UtcNow;
        if (user.LockedUntil is { } until && until > now) return Results.Problem("Too many wrong attempts; try again later", statusCode: StatusCodes.Status429TooManyRequests);
        if (VerifyPassword(user, password ?? ""))
        {
            if (user.FailedLogins > 0) await db.Users.Where(u => u.Id == user.Id).ExecuteUpdateAsync(s => s.SetProperty(u => u.FailedLogins, 0), ct);
            return null;
        }
        await RecordFailureAsync(db, user.Id, now, ct);
        return Results.Problem("Wrong password", statusCode: StatusCodes.Status403Forbidden);
    }
    private static readonly PasswordHasher<AppUser> Hasher = new();
    private static readonly AppUser Dummy = new() { Username = "", PasswordHash = "" };
    private static readonly string DummyHash = Hasher.HashPassword(Dummy, "dummy-password-for-timing");


    public const string DefaultPassword = "sidergest123";
    public const string TooEasyMessage = "Password too easy to guess";

    private static bool TooEasy(string? password, string? username) =>
        password is not null && (password == DefaultPassword || (username is not null && string.Equals(password, username, StringComparison.OrdinalIgnoreCase)));

    /// <summary>The sign-in before the newest one (the newest is the current session); null on a first login.</summary>
    public static async Task<DateTimeOffset?> PreviousLoginAsync(EbtDbContext db, int userId, CancellationToken ct) =>
        await db.RefreshTokens.AsNoTracking().Where(r => r.UserId == userId && r.IsLogin).OrderByDescending(r => r.CreatedAt).Skip(1)
            .Select(r => (DateTimeOffset?)r.CreatedAt).FirstOrDefaultAsync(ct);

    private static readonly System.Text.RegularExpressions.Regex AlertKey = new("^[a-z0-9_-]{1,40}$");

    private static string? Summarize(string changes)
    {
        try
        {
            using var doc = JsonDocument.Parse(changes);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return null;
            var parts = new List<string>();
            foreach (var p in doc.RootElement.EnumerateObject())
            {
                if (p.Value.ValueKind == JsonValueKind.Object && p.Value.TryGetProperty("from", out var from) && p.Value.TryGetProperty("to", out var to))
                    parts.Add($"{p.Name}: {Show(from)} -> {Show(to)}");
                else if (p.Value.ValueKind is JsonValueKind.String or JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False)
                    parts.Add($"{p.Name}: {Show(p.Value)}");
                if (parts.Count == 3) break;
            }
            if (parts.Count == 0) return null;
            var text = string.Join("; ", parts);
            return text.Length > 200 ? text[..200] : text;
        }
        catch (JsonException) { return null; }
        static string Show(JsonElement e) => e.ValueKind == JsonValueKind.Null ? "-" : e.ValueKind == JsonValueKind.String ? e.GetString() ?? "-" : e.ToString();
    }

    public static bool VerifyPassword(AppUser user, string password) => Hasher.VerifyHashedPassword(user, user.PasswordHash, password) != PasswordVerificationResult.Failed;

    public static void MapAuth(this WebApplication app)
    {
        var auth = app.MapGroup("/api/auth").WithTags("Auth");

        auth.MapPost("/login", async (LoginRequest req, EbtDbContext db, TokenService tokens, IPasswordHasher<AppUser> hasher, ILoggerFactory logs, HttpContext http, IConfiguration config, UserCache cache, CancellationToken ct) =>
        {
            var log = logs.CreateLogger("Ebt.Auth");
            if (!Crud.Has(req.Username) || string.IsNullOrEmpty(req.Password)) return Results.Unauthorized();
            var name = req.Username!.Trim().ToLower();
            var user = await db.Users.FirstOrDefaultAsync(u => u.Username == name, ct);
            if (user is null)
            {
                hasher.VerifyHashedPassword(Dummy, DummyHash, req.Password); // same cost as a real check, so timing does not reveal usernames
                // The typed name can be a mistyped password, so it is never written to the log.
                log.LogWarning("Login failed for an unknown user (name length {Length}) from {Ip}", name.Length, http.Connection.RemoteIpAddress);
                return Results.Unauthorized();
            }
            var now = DateTimeOffset.UtcNow;
            if (user.LockedUntil is { } until && until > now)
            {
                hasher.VerifyHashedPassword(user, user.PasswordHash, req.Password); // result ignored: a locked account must cost the same time as an open one
                log.LogWarning("Login refused for locked user {User} from {Ip}", name, http.Connection.RemoteIpAddress);
                return Results.Unauthorized();
            }
            var verified = hasher.VerifyHashedPassword(user, user.PasswordHash, req.Password); // also for inactive users, so timing does not reveal them
            var result = user.Active ? verified : PasswordVerificationResult.Failed;
            if (result == PasswordVerificationResult.Failed)
            {
                if (user.Active && await RecordFailureAsync(db, user.Id, now, ct))
                    log.LogWarning("User {User} locked until {Until} after repeated failures from {Ip}", name, now + LockoutDuration, http.Connection.RemoteIpAddress);
                return Results.Unauthorized();
            }
            if (result == PasswordVerificationResult.SuccessRehashNeeded) user.PasswordHash = hasher.HashPassword(user, req.Password);
            user.FailedLogins = 0;
            user.LockedUntil = null;
            user.LastActivityAt = now;
            await db.SaveChangesAsync(ct);
            cache.Invalidate(user.Id);
            var (token, expires) = tokens.Issue(user);
            log.LogInformation("User {User} logged in from {Ip}", user.Username, http.Connection.RemoteIpAddress);
            var (refresh, refreshExpires) = await tokens.NewRefreshAsync(user, db, ct, DeviceInfo.From(req.Device, http), isLogin: true);
            return Results.Ok(new LoginResponse(token, expires, user.Username, user.Role, Access.PoliciesFor(user.Role), refresh, refreshExpires, TokenService.EffectiveIdle(user.IdleLockMinutes, TokenService.MaxIdle(config)), TokenService.MaxIdle(config), await PreviousLoginAsync(db, user.Id, ct)));
        }).AllowAnonymous().RequireRateLimiting(Policies.LoginLimiter);

        auth.MapPost("/refresh", async (RefreshRequest req, EbtDbContext db, TokenService tokens, ILoggerFactory logs, IConfiguration config, UserCache cache, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(req.RefreshToken)) return Results.Unauthorized();
            var hash = TokenService.HashRefresh(req.RefreshToken.Trim());
            var stored = await db.RefreshTokens.Include(r => r.User).FirstOrDefaultAsync(r => r.TokenHash == hash, ct);
            if (stored?.User is not { } user) return Results.Unauthorized();
            var now = DateTimeOffset.UtcNow;
            if (stored.RevokedAt is { } rotatedAt)
            {
                // Two tabs (or a retry) refreshing at once: the loser holds a token that was rotated a moment ago. Refuse it, but do not sign the user out everywhere.
                if (now - rotatedAt <= tokens.ReuseGrace) return Results.Unauthorized();
                // A rotated token came back: treat it as stolen and sign the user out everywhere.
                user.TokenVersion++;
                await db.RefreshTokens.Where(r => r.UserId == user.Id).ExecuteDeleteAsync(ct);
                await db.SaveChangesAsync(ct);
                cache.Invalidate(user.Id);
                logs.CreateLogger("Ebt.Auth").LogWarning("Refresh token reuse detected for {User}; all sessions revoked", user.Username);
                return Results.Unauthorized();
            }
            if (stored.ExpiresAt <= now || !user.Active || TokenService.IsIdle(TokenService.EffectiveIdle(user.IdleLockMinutes, TokenService.MaxIdle(config)), user.LastActivityAt, now)) return Results.Unauthorized();
            // Claim the token atomically: two parallel refreshes of the same token must not both succeed, or rotation protects nothing.
            var claimed = await db.RefreshTokens.Where(r => r.Id == stored.Id && r.RevokedAt == null).ExecuteUpdateAsync(s => s.SetProperty(r => r.RevokedAt, now), ct);
            if (claimed == 0) return Results.Unauthorized();
            var (token, expires) = tokens.Issue(user);
            var (refresh, refreshExpires) = await tokens.NewRefreshAsync(user, db, ct, new DeviceInfo(stored.Device, stored.UserAgent, stored.Ip));
            return Results.Ok(new LoginResponse(token, expires, user.Username, user.Role, Access.PoliciesFor(user.Role), refresh, refreshExpires, TokenService.EffectiveIdle(user.IdleLockMinutes, TokenService.MaxIdle(config)), TokenService.MaxIdle(config), await PreviousLoginAsync(db, user.Id, ct)));
        }).AllowAnonymous().RequireRateLimiting(Policies.RefreshLimiter);

        auth.MapPost("/logout", async (RefreshRequest req, EbtDbContext db, CancellationToken ct) =>
        {
            if (!string.IsNullOrWhiteSpace(req.RefreshToken))
            {
                var hash = TokenService.HashRefresh(req.RefreshToken.Trim());
                await db.RefreshTokens.Where(r => r.TokenHash == hash).ExecuteDeleteAsync(ct);
            }
            return Results.NoContent();
        }).AllowAnonymous().RequireRateLimiting(Policies.RefreshLimiter);

        static object Me(ClaimsPrincipal principal, AppUser? user, IConfiguration config, DateTimeOffset? previousLoginAt = null) => new
        {
            previousLoginAt,
            username = principal.Identity!.Name,
            role = principal.FindFirstValue(ClaimTypes.Role),
            permissions = Enum.TryParse<UserRole>(principal.FindFirstValue(ClaimTypes.Role), out var r) ? Access.PoliciesFor(r) : [Policies.Read],
            displayName = user?.DisplayName,
            email = user?.Email,
            idleLockMinutes = TokenService.EffectiveIdle(user?.IdleLockMinutes ?? 0, TokenService.MaxIdle(config)),
            maxIdleMinutes = TokenService.MaxIdle(config)
        };

        auth.MapGet("/me", async (EbtDbContext db, IConfiguration config, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            var user = int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id) ? await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == id, ct) : null;
            return Results.Ok(Me(principal, user, config, user is null ? null : await PreviousLoginAsync(db, user.Id, ct)));
        }).RequireAuthorization(Policies.Read);

        // The signed-in user's own recent activity: sign-ins (newest first) and the audit rows written under their name.
        auth.MapGet("/my-activity", async (EbtDbContext db, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            if (!int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id)) return Results.Unauthorized();
            var name = principal.Identity?.Name;
            var logins = (await db.RefreshTokens.AsNoTracking().Where(r => r.UserId == id && r.IsLogin).OrderByDescending(r => r.CreatedAt).Take(20).ToListAsync(ct))
                .Select(r => new LoginEntryDto(r.CreatedAt, r.Device, r.UserAgent, r.Ip, false)).ToList();
            var rows = name is null ? [] : await db.AuditLog.AsNoTracking().Where(a => a.User == name).OrderByDescending(a => a.At).Take(30).ToListAsync(ct);
            var changes = rows.Select(a => new MyChangeDto(a.At, a.Entity, a.EntityId, a.Action, Summarize(a.Changes))).ToList();
            return Results.Ok(new MyActivityDto(logins, changes));
        }).RequireAuthorization(Policies.Read);

        // Personal alert preferences. Written with ExecuteUpdate (like the idle lock): a preference is not an audited change.
        auth.MapGet("/notification-prefs", async (EbtDbContext db, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            if (!int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id)) return Results.Unauthorized();
            var u = await db.Users.AsNoTracking().Where(x => x.Id == id).Select(x => new { x.MutedAlerts, x.HideLegacyAlerts }).FirstOrDefaultAsync(ct);
            if (u is null) return Results.Unauthorized();
            return Results.Ok(new NotificationPrefsDto(string.IsNullOrEmpty(u.MutedAlerts) ? [] : u.MutedAlerts.Split(','), u.HideLegacyAlerts));
        }).RequireAuthorization(Policies.Read);

        auth.MapPut("/notification-prefs", async (NotificationPrefsDto req, EbtDbContext db, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            if (!int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id)) return Results.Unauthorized();
            var keys = (req.MutedAlerts ?? []).Select(k => k?.Trim() ?? "").Distinct().ToArray();
            var errors = Crud.Errors()
                .Require(keys.Length <= 30, "mutedAlerts", "No máximo 30 alertas silenciados")
                .Require(keys.All(k => AlertKey.IsMatch(k)), "mutedAlerts", "Cada chave deve ter de 1 a 40 caracteres: letras minúsculas, números, - ou _");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var joined = keys.Length == 0 ? null : string.Join(',', keys);
            var n = await db.Users.Where(u => u.Id == id).ExecuteUpdateAsync(s => s.SetProperty(u => u.MutedAlerts, joined).SetProperty(u => u.HideLegacyAlerts, req.HideLegacy), ct);
            if (n == 0) return Results.Unauthorized();
            return Results.Ok(new NotificationPrefsDto(keys, req.HideLegacy));
        }).RequireAuthorization(Policies.Read).RequireRateLimiting(Policies.AccountLimiter);

        // The client reports real activity (not background polling). Only the time is recorded: the limit is server-side (PUT /idle-lock, Security:MaxIdleMinutes);
        // a body from older clients is accepted and ignored, so one device cannot change the lock of another.
        auth.MapPost("/activity", async (EbtDbContext db, UserCache cache, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            if (!int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id)) return Results.Unauthorized();
            await db.Users.Where(u => u.Id == id).ExecuteUpdateAsync(s => s.SetProperty(u => u.LastActivityAt, DateTimeOffset.UtcNow), ct);
            cache.Invalidate(id);
            return Results.NoContent();
        }).RequireAuthorization(Policies.Read).RequireRateLimiting(Policies.AccountLimiter);

        auth.MapPut("/idle-lock", async (IdleLockRequest req, EbtDbContext db, IConfiguration config, UserCache cache, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            if (!int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id)) return Results.Unauthorized();
            if (req.Minutes is < 0 or > TokenService.MaxIdleMinutesLimit) return Results.ValidationProblem(Crud.Errors().Require(false, "minutes", "Between 0 and 480"));
            var cap = TokenService.MaxIdle(config);
            await db.Users.Where(u => u.Id == id).ExecuteUpdateAsync(s => s.SetProperty(u => u.IdleLockMinutes, req.Minutes).SetProperty(u => u.LastActivityAt, DateTimeOffset.UtcNow), ct);
            cache.Invalidate(id);
            return Results.Ok(new { idleLockMinutes = TokenService.EffectiveIdle(req.Minutes, cap), maxIdleMinutes = cap });
        }).RequireAuthorization(Policies.Read).RequireRateLimiting(Policies.AccountLimiter);

        auth.MapPut("/profile", async (ProfileRequest req, EbtDbContext db, IConfiguration config, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            if (!int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id)) return Results.Unauthorized();
            var user = await db.Users.FindAsync([id], ct);
            if (user is null || !user.Active) return Results.Unauthorized();
            var name = string.IsNullOrWhiteSpace(req.DisplayName) ? null : req.DisplayName.Trim();
            var email = string.IsNullOrWhiteSpace(req.Email) ? null : req.Email.Trim();
            var errors = Crud.Errors()
                .Require(name is null || name.Length <= 120, "displayName", "At most 120 characters")
                .Require(email is null || (email.Length <= 200 && MailAddress.TryCreate(email, out var parsed) && parsed.Address == email), "email", "Invalid email");
            if (errors.Count == 0 && email is not null && await db.Users.AnyAsync(u => u.Id != id && u.Email != null && u.Email.ToLower() == email.ToLower(), ct))
                errors.Require(false, "email", "Email already used by another user");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            user.DisplayName = name;
            user.Email = email;
            db.AuditLog.Add(new AuditEntry
            {
                At = DateTimeOffset.UtcNow, User = user.Username, Entity = "User", EntityId = id.ToString(), Action = "Update",
                Changes = JsonSerializer.Serialize(new { profile = true, displayName = name, email })
            });
            await db.SaveChangesAsync(ct);
            return Results.Ok(Me(principal, user, config, await PreviousLoginAsync(db, id, ct)));
        }).RequireAuthorization(Policies.Read);

        // Devices: each login chain keeps one active refresh row (rotation replaces it), so the rows are the user's signed-in devices.
        auth.MapPost("/sessions", async (SessionsRequest req, EbtDbContext db, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            if (!int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id)) return Results.Unauthorized();
            var now = DateTimeOffset.UtcNow;
            var mine = string.IsNullOrWhiteSpace(req.RefreshToken) ? null : TokenService.HashRefresh(req.RefreshToken.Trim());
            var rows = await db.RefreshTokens.AsNoTracking().Where(r => r.UserId == id && r.RevokedAt == null && r.ExpiresAt > now).OrderByDescending(r => r.CreatedAt).ToListAsync(ct);
            return Results.Ok(rows.Select(r => new SessionDto(r.Id, r.Device, r.UserAgent, r.Ip, r.CreatedAt, r.ExpiresAt, mine != null && r.TokenHash == mine)));
        }).RequireAuthorization(Policies.Read);

        // The other device keeps working until its access token expires (up to ExpiresMinutes); it cannot refresh any more.
        auth.MapDelete("/sessions/{id:long}", async (long id, EbtDbContext db, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            if (!int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var uid)) return Results.Unauthorized();
            var removed = await db.RefreshTokens.Where(r => r.Id == id && r.UserId == uid).ExecuteDeleteAsync(ct);
            if (removed == 0) return Results.NotFound();
            AuditSecurity(db, principal.Identity?.Name, uid, "SessionRevoked", new { sessionId = id });
            await db.SaveChangesAsync(ct);
            return Results.NoContent();
        }).RequireAuthorization(Policies.Read);

        // Signs every other device out at once: bumping the token version also kills their access tokens; this device gets fresh tokens.
        auth.MapPost("/sessions/revoke-others", async (SessionsRequest req, EbtDbContext db, TokenService tokens, ILoggerFactory logs, IConfiguration config, UserCache cache, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            if (!int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id)) return Results.Unauthorized();
            var user = await db.Users.FindAsync([id], ct);
            if (user is null || !user.Active) return Results.Unauthorized();
            var now = DateTimeOffset.UtcNow;
            var hash = string.IsNullOrWhiteSpace(req.RefreshToken) ? null : TokenService.HashRefresh(req.RefreshToken.Trim());
            var current = hash is null ? null : await db.RefreshTokens.AsNoTracking().FirstOrDefaultAsync(r => r.UserId == id && r.TokenHash == hash && r.RevokedAt == null && r.ExpiresAt > now, ct);
            if (current is null) return Results.ValidationProblem(Crud.Errors().Require(false, "refreshToken", "Not an active session of this user"));
            // One transaction: a failure after the delete must not leave the user with no session at all.
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            user.TokenVersion++;
            await db.RefreshTokens.Where(r => r.UserId == id).ExecuteDeleteAsync(ct);
            AuditSecurity(db, user.Username, id, "SessionsRevoked", new { others = true });
            await db.SaveChangesAsync(ct);
            cache.Invalidate(id);
            var (token, expires) = tokens.Issue(user);
            var (refresh, refreshExpires) = await tokens.NewRefreshAsync(user, db, ct, new DeviceInfo(current.Device, current.UserAgent, current.Ip));
            await tx.CommitAsync(ct);
            logs.CreateLogger("Ebt.Auth").LogInformation("{User} signed out all other devices", user.Username);
            return Results.Ok(new LoginResponse(token, expires, user.Username, user.Role, Access.PoliciesFor(user.Role), refresh, refreshExpires, TokenService.EffectiveIdle(user.IdleLockMinutes, TokenService.MaxIdle(config)), TokenService.MaxIdle(config), await PreviousLoginAsync(db, user.Id, ct)));
        }).RequireAuthorization(Policies.Read).RequireRateLimiting(Policies.AccountLimiter);

        // Own password: needs the current one, signs every other session out and returns fresh tokens for this one.
        auth.MapPost("/password", async (ChangePasswordRequest req, EbtDbContext db, TokenService tokens, IPasswordHasher<AppUser> hasher, ILoggerFactory logs, IConfiguration config, UserCache cache, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            if (!int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id)) return Results.Unauthorized();
            var user = await db.Users.FindAsync([id], ct);
            if (user is null || !user.Active) return Results.Unauthorized();
            var now = DateTimeOffset.UtcNow;
            if (user.LockedUntil is { } until && until > now) return Results.Problem("Too many wrong attempts; try again later", statusCode: StatusCodes.Status429TooManyRequests);
            if (!VerifyPassword(user, req.CurrentPassword ?? ""))
            {
                // A stolen session must not be able to guess the current password without limit.
                await RecordFailureAsync(db, user.Id, now, ct);
                return Results.ValidationProblem(Crud.Errors().Require(false, "currentPassword", "Incorrect password"));
            }
            var errors = Crud.Errors()
                .Require((req.NewPassword ?? "").Length >= MinPasswordLength, "newPassword", $"At least {MinPasswordLength} characters")
                .Require(req.NewPassword != req.CurrentPassword, "newPassword", "Must differ from the current password")
                .Require(!TooEasy(req.NewPassword, user.Username), "newPassword", TooEasyMessage);
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            user.PasswordHash = hasher.HashPassword(user, req.NewPassword!);
            user.FailedLogins = 0;
            user.LockedUntil = null;
            user.TokenVersion++;
            await db.RefreshTokens.Where(r => r.UserId == user.Id).ExecuteDeleteAsync(ct);
            AuditSecurity(db, user.Username, user.Id, "PasswordChange", new { self = true, sessionsRevoked = true });
            await db.SaveChangesAsync(ct);
            cache.Invalidate(user.Id);
            logs.CreateLogger("Ebt.Auth").LogInformation("User {User} changed their own password; other sessions revoked", user.Username);
            var (token, expires) = tokens.Issue(user);
            var (refresh, refreshExpires) = await tokens.NewRefreshAsync(user, db, ct);
            return Results.Ok(new LoginResponse(token, expires, user.Username, user.Role, Access.PoliciesFor(user.Role), refresh, refreshExpires, TokenService.EffectiveIdle(user.IdleLockMinutes, TokenService.MaxIdle(config)), TokenService.MaxIdle(config), await PreviousLoginAsync(db, user.Id, ct)));
        }).RequireAuthorization(Policies.Read).RequireRateLimiting(Policies.PasswordLimiter);

        var users = app.MapGroup("/api/users").WithTags("Users").RequireAuthorization(Policies.Admin);

        users.MapGet("/", async (EbtDbContext db, CancellationToken ct) =>
            await db.Users.AsNoTracking().OrderBy(u => u.Username).Select(u => new UserDto(u.Id, u.Username, u.Role, u.Active, u.LockedUntil != null && u.LockedUntil > DateTimeOffset.UtcNow, u.DisplayName, u.Email)).ToListAsync(ct));

        users.MapPost("/", async (CreateUserRequest req, EbtDbContext db, IPasswordHasher<AppUser> hasher, CancellationToken ct) =>
        {
            var errors = Crud.Errors()
                .Require(Crud.Has(req.Username), "username", "Required")
                .Require((req.Password ?? "").Length >= MinPasswordLength, "password", $"At least {MinPasswordLength} characters")
                .Require(!TooEasy(req.Password, req.Username?.Trim()), "password", TooEasyMessage);
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var user = new AppUser { Username = req.Username!.Trim().ToLower(), PasswordHash = "", Role = req.Role };
            user.PasswordHash = hasher.HashPassword(user, req.Password!);
            db.Users.Add(user);
            await db.SaveChangesAsync(ct);
            return Results.Created($"/api/users/{user.Id}", new UserDto(user.Id, user.Username, user.Role, user.Active));
        });

        users.MapPut("/{id:int}", async (int id, UpdateUserRequest req, EbtDbContext db, IPasswordHasher<AppUser> hasher, ILoggerFactory logs, UserCache cache, ClaimsPrincipal actor, CancellationToken ct) =>
        {
            var user = await db.Users.FindAsync([id], ct);
            if (user is null) return Results.NotFound();
            if (req.Password is not null && req.Password.Length < MinPasswordLength)
                return Results.ValidationProblem(Crud.Errors().Require(false, "password", $"At least {MinPasswordLength} characters"));
            if (TooEasy(req.Password, user.Username)) return Results.ValidationProblem(Crud.Errors().Require(false, "password", TooEasyMessage));
            var staysAdmin = req.Role == UserRole.Admin && req.Active;
            if (user.Role == UserRole.Admin && user.Active && !staysAdmin
                && !await db.Users.AnyAsync(u => u.Id != id && u.Role == UserRole.Admin && u.Active, ct))
                return Results.Problem("At least one active Admin must remain", statusCode: StatusCodes.Status409Conflict);
            var revoke = req.Role != user.Role || req.Active != user.Active || req.Password is not null;
            user.Role = req.Role;
            user.Active = req.Active;
            if (req.Password is not null) user.PasswordHash = hasher.HashPassword(user, req.Password);
            if (revoke)
            {
                user.TokenVersion++;
                await db.RefreshTokens.Where(r => r.UserId == user.Id).ExecuteDeleteAsync(ct);
                user.FailedLogins = 0;
                user.LockedUntil = null;
                logs.CreateLogger("Ebt.Auth").LogInformation("User {Target} changed by {Actor}: role {Role}, active {Active}, password changed {Pwd}", user.Username, actor.Identity?.Name, user.Role, user.Active, req.Password is not null);
                AuditSecurity(db, actor.Identity?.Name, user.Id, req.Password is not null ? "PasswordReset" : "AccessChanged",
                    new { passwordChanged = req.Password is not null, role = user.Role.ToString(), active = user.Active, sessionsRevoked = true });
            }
            await db.SaveChangesAsync(ct);
            cache.Invalidate(user.Id);
            return Results.Ok(new UserDto(user.Id, user.Username, user.Role, user.Active));
        });

        users.MapPost("/{id:int}/unlock", async (int id, EbtDbContext db, ILoggerFactory logs, ClaimsPrincipal actor, CancellationToken ct) =>
        {
            var user = await db.Users.FindAsync([id], ct);
            if (user is null) return Results.NotFound();
            user.FailedLogins = 0;
            user.LockedUntil = null;
            AuditSecurity(db, actor.Identity?.Name, user.Id, "Unlock", new { });
            await db.SaveChangesAsync(ct);
            logs.CreateLogger("Ebt.Auth").LogInformation("User {Target} unlocked by {Actor}", user.Username, actor.Identity?.Name);
            return Results.Ok(new UserDto(user.Id, user.Username, user.Role, user.Active));
        });

        app.MapGet("/api/access/matrix", () => Results.Ok(new
        {
            policies = Access.Matrix.Keys.Prepend(Policies.Read).Order().ToArray(),
            roles = Enum.GetValues<UserRole>().ToDictionary(r => r.ToString(), r => Access.PoliciesFor(r))
        })).WithTags("Users").RequireAuthorization(Policies.Admin);
    }

    public static async Task EnsureBootstrapAdminAsync(EbtDbContext db, IPasswordHasher<AppUser> hasher, IConfiguration config, ILogger logger, bool allowDefaultPassword = true)
    {
        if (await db.Users.AnyAsync()) return;
        var username = config["Bootstrap:AdminUser"];
        var password = config["Bootstrap:AdminPassword"];
        if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(password))
        {
            logger.LogWarning("No users exist and Bootstrap:AdminUser/AdminPassword are not set; nobody can log in.");
            return;
        }
        if (password.Length < MinPasswordLength)
            throw new InvalidOperationException($"Bootstrap:AdminPassword must have at least {MinPasswordLength} characters.");
        if (password == DefaultPassword && !allowDefaultPassword)
            throw new InvalidOperationException("Bootstrap:AdminPassword is the well-known default password; set a real one (EBT_ADMIN_PASSWORD) outside Development.");
        if (password == DefaultPassword)
            logger.LogWarning("Bootstrap admin created with the well-known development password; change it in Configurações before real use.");
        var admin = new AppUser { Username = username.Trim().ToLower(), PasswordHash = "", Role = UserRole.Admin };
        admin.PasswordHash = hasher.HashPassword(admin, password);
        db.Users.Add(admin);
        await db.SaveChangesAsync();
        logger.LogInformation("Created bootstrap admin user {User}", admin.Username);
    }
}
