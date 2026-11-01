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
}

public class JwtOptions
{
    public string Issuer { get; set; } = "ebt-erp";
    public string Audience { get; set; } = "ebt-erp-clients";
    public string SigningKey { get; set; } = "";
    public int ExpiresMinutes { get; set; } = 60;
    public int RefreshDays { get; set; } = 14;
    public int ClockSkewSeconds { get; set; } = 60;
}

public class TokenService(JwtOptions options)
{
    public const string VersionClaim = "tv";

    public static string HashRefresh(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token))).ToLowerInvariant();

    /// <summary>Creates, stores and returns a new opaque refresh token for the user (only its hash is persisted).</summary>
    public async Task<(string Token, DateTimeOffset ExpiresAt)> NewRefreshAsync(AppUser user, EbtDbContext db, CancellationToken ct, DeviceInfo? device = null)
    {
        var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        var now = DateTimeOffset.UtcNow;
        var expires = now.AddDays(options.RefreshDays);
        db.RefreshTokens.Add(new RefreshToken { UserId = user.Id, TokenHash = HashRefresh(token), CreatedAt = now, ExpiresAt = expires, Device = device?.Device, UserAgent = device?.UserAgent, Ip = device?.Ip });
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
        var user = await db.Users.AsNoTracking().Where(u => u.Id == id).Select(u => new { u.Active, u.TokenVersion }).FirstOrDefaultAsync(ctx.HttpContext.RequestAborted);
        if (user is null || !user.Active || user.TokenVersion != version) ctx.Fail("Token revoked");
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
public record ProfileRequest(string? DisplayName, string? Email);
public record LoginResponse(string Token, DateTimeOffset ExpiresAt, string Username, UserRole Role, string[] Permissions, string RefreshToken, DateTimeOffset RefreshExpiresAt);
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
    private static readonly PasswordHasher<AppUser> Hasher = new();
    private static readonly AppUser Dummy = new() { Username = "", PasswordHash = "" };
    private static readonly string DummyHash = Hasher.HashPassword(Dummy, "dummy-password-for-timing");


    public static bool VerifyPassword(AppUser user, string password) => Hasher.VerifyHashedPassword(user, user.PasswordHash, password) != PasswordVerificationResult.Failed;

    public static void MapAuth(this WebApplication app)
    {
        var auth = app.MapGroup("/api/auth").WithTags("Auth");

        auth.MapPost("/login", async (LoginRequest req, EbtDbContext db, TokenService tokens, IPasswordHasher<AppUser> hasher, ILoggerFactory logs, HttpContext http, CancellationToken ct) =>
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
                log.LogWarning("Login refused for locked user {User} from {Ip}", name, http.Connection.RemoteIpAddress);
                return Results.Unauthorized();
            }
            var result = user.Active ? hasher.VerifyHashedPassword(user, user.PasswordHash, req.Password) : PasswordVerificationResult.Failed;
            if (result == PasswordVerificationResult.Failed)
            {
                if (user.Active && ++user.FailedLogins >= MaxFailedLogins)
                {
                    user.LockedUntil = now + LockoutDuration;
                    user.FailedLogins = 0;
                    log.LogWarning("User {User} locked until {Until} after repeated failures from {Ip}", name, user.LockedUntil, http.Connection.RemoteIpAddress);
                }
                await db.SaveChangesAsync(ct);
                return Results.Unauthorized();
            }
            if (result == PasswordVerificationResult.SuccessRehashNeeded) user.PasswordHash = hasher.HashPassword(user, req.Password);
            user.FailedLogins = 0;
            user.LockedUntil = null;
            await db.SaveChangesAsync(ct);
            var (token, expires) = tokens.Issue(user);
            log.LogInformation("User {User} logged in from {Ip}", user.Username, http.Connection.RemoteIpAddress);
            var (refresh, refreshExpires) = await tokens.NewRefreshAsync(user, db, ct, DeviceInfo.From(req.Device, http));
            return Results.Ok(new LoginResponse(token, expires, user.Username, user.Role, Access.PoliciesFor(user.Role), refresh, refreshExpires));
        }).AllowAnonymous().RequireRateLimiting(Policies.LoginLimiter);

        auth.MapPost("/refresh", async (RefreshRequest req, EbtDbContext db, TokenService tokens, ILoggerFactory logs, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(req.RefreshToken)) return Results.Unauthorized();
            var hash = TokenService.HashRefresh(req.RefreshToken.Trim());
            var stored = await db.RefreshTokens.Include(r => r.User).FirstOrDefaultAsync(r => r.TokenHash == hash, ct);
            if (stored?.User is not { } user) return Results.Unauthorized();
            var now = DateTimeOffset.UtcNow;
            if (stored.RevokedAt is not null)
            {
                // A rotated token came back: treat it as stolen and sign the user out everywhere.
                user.TokenVersion++;
                await db.RefreshTokens.Where(r => r.UserId == user.Id).ExecuteDeleteAsync(ct);
                await db.SaveChangesAsync(ct);
                logs.CreateLogger("Ebt.Auth").LogWarning("Refresh token reuse detected for {User}; all sessions revoked", user.Username);
                return Results.Unauthorized();
            }
            if (stored.ExpiresAt <= now || !user.Active) return Results.Unauthorized();
            // Claim the token atomically: two parallel refreshes of the same token must not both succeed, or rotation protects nothing.
            var claimed = await db.RefreshTokens.Where(r => r.Id == stored.Id && r.RevokedAt == null).ExecuteUpdateAsync(s => s.SetProperty(r => r.RevokedAt, now), ct);
            if (claimed == 0) return Results.Unauthorized();
            var (token, expires) = tokens.Issue(user);
            var (refresh, refreshExpires) = await tokens.NewRefreshAsync(user, db, ct, new DeviceInfo(stored.Device, stored.UserAgent, stored.Ip));
            return Results.Ok(new LoginResponse(token, expires, user.Username, user.Role, Access.PoliciesFor(user.Role), refresh, refreshExpires));
        }).AllowAnonymous().RequireRateLimiting(Policies.LoginLimiter);

        auth.MapPost("/logout", async (RefreshRequest req, EbtDbContext db, CancellationToken ct) =>
        {
            if (!string.IsNullOrWhiteSpace(req.RefreshToken))
            {
                var hash = TokenService.HashRefresh(req.RefreshToken.Trim());
                await db.RefreshTokens.Where(r => r.TokenHash == hash).ExecuteDeleteAsync(ct);
            }
            return Results.NoContent();
        }).AllowAnonymous().RequireRateLimiting(Policies.LoginLimiter);

        static object Me(ClaimsPrincipal principal, AppUser? user) => new
        {
            username = principal.Identity!.Name,
            role = principal.FindFirstValue(ClaimTypes.Role),
            permissions = Enum.TryParse<UserRole>(principal.FindFirstValue(ClaimTypes.Role), out var r) ? Access.PoliciesFor(r) : [Policies.Read],
            displayName = user?.DisplayName,
            email = user?.Email
        };

        auth.MapGet("/me", async (EbtDbContext db, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            var user = int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id) ? await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == id, ct) : null;
            return Results.Ok(Me(principal, user));
        }).RequireAuthorization(Policies.Read);

        auth.MapPut("/profile", async (ProfileRequest req, EbtDbContext db, ClaimsPrincipal principal, CancellationToken ct) =>
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
            return Results.Ok(Me(principal, user));
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
            return removed == 0 ? Results.NotFound() : Results.NoContent();
        }).RequireAuthorization(Policies.Read);

        // Signs every other device out at once: bumping the token version also kills their access tokens; this device gets fresh tokens.
        auth.MapPost("/sessions/revoke-others", async (SessionsRequest req, EbtDbContext db, TokenService tokens, ILoggerFactory logs, ClaimsPrincipal principal, CancellationToken ct) =>
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
            await db.SaveChangesAsync(ct);
            var (token, expires) = tokens.Issue(user);
            var (refresh, refreshExpires) = await tokens.NewRefreshAsync(user, db, ct, new DeviceInfo(current.Device, current.UserAgent, current.Ip));
            await tx.CommitAsync(ct);
            logs.CreateLogger("Ebt.Auth").LogInformation("{User} signed out all other devices", user.Username);
            return Results.Ok(new LoginResponse(token, expires, user.Username, user.Role, Access.PoliciesFor(user.Role), refresh, refreshExpires));
        }).RequireAuthorization(Policies.Read).RequireRateLimiting(Policies.AccountLimiter);

        // Own password: needs the current one, signs every other session out and returns fresh tokens for this one.
        auth.MapPost("/password", async (ChangePasswordRequest req, EbtDbContext db, TokenService tokens, IPasswordHasher<AppUser> hasher, ILoggerFactory logs, ClaimsPrincipal principal, CancellationToken ct) =>
        {
            if (!int.TryParse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id)) return Results.Unauthorized();
            var user = await db.Users.FindAsync([id], ct);
            if (user is null || !user.Active) return Results.Unauthorized();
            var now = DateTimeOffset.UtcNow;
            if (user.LockedUntil is { } until && until > now) return Results.Problem("Too many wrong attempts; try again later", statusCode: StatusCodes.Status429TooManyRequests);
            if (!VerifyPassword(user, req.CurrentPassword ?? ""))
            {
                // A stolen session must not be able to guess the current password without limit.
                if (++user.FailedLogins >= MaxFailedLogins)
                {
                    user.LockedUntil = now + LockoutDuration;
                    user.FailedLogins = 0;
                }
                await db.SaveChangesAsync(ct);
                return Results.ValidationProblem(Crud.Errors().Require(false, "currentPassword", "Incorrect password"));
            }
            var errors = Crud.Errors()
                .Require((req.NewPassword ?? "").Length >= MinPasswordLength, "newPassword", $"At least {MinPasswordLength} characters")
                .Require(req.NewPassword != req.CurrentPassword, "newPassword", "Must differ from the current password");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            user.PasswordHash = hasher.HashPassword(user, req.NewPassword!);
            user.FailedLogins = 0;
            user.LockedUntil = null;
            user.TokenVersion++;
            await db.RefreshTokens.Where(r => r.UserId == user.Id).ExecuteDeleteAsync(ct);
            await db.SaveChangesAsync(ct);
            logs.CreateLogger("Ebt.Auth").LogInformation("User {User} changed their own password; other sessions revoked", user.Username);
            var (token, expires) = tokens.Issue(user);
            var (refresh, refreshExpires) = await tokens.NewRefreshAsync(user, db, ct);
            return Results.Ok(new LoginResponse(token, expires, user.Username, user.Role, Access.PoliciesFor(user.Role), refresh, refreshExpires));
        }).RequireAuthorization(Policies.Read).RequireRateLimiting(Policies.LoginLimiter);

        var users = app.MapGroup("/api/users").WithTags("Users").RequireAuthorization(Policies.Admin);

        users.MapGet("/", async (EbtDbContext db, CancellationToken ct) =>
            await db.Users.AsNoTracking().OrderBy(u => u.Username).Select(u => new UserDto(u.Id, u.Username, u.Role, u.Active, u.LockedUntil != null && u.LockedUntil > DateTimeOffset.UtcNow, u.DisplayName, u.Email)).ToListAsync(ct));

        users.MapPost("/", async (CreateUserRequest req, EbtDbContext db, IPasswordHasher<AppUser> hasher, CancellationToken ct) =>
        {
            var errors = Crud.Errors()
                .Require(Crud.Has(req.Username), "username", "Required")
                .Require((req.Password ?? "").Length >= MinPasswordLength, "password", $"At least {MinPasswordLength} characters");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var user = new AppUser { Username = req.Username.Trim().ToLower(), PasswordHash = "", Role = req.Role };
            user.PasswordHash = hasher.HashPassword(user, req.Password!);
            db.Users.Add(user);
            await db.SaveChangesAsync(ct);
            return Results.Created($"/api/users/{user.Id}", new UserDto(user.Id, user.Username, user.Role, user.Active));
        });

        users.MapPut("/{id:int}", async (int id, UpdateUserRequest req, EbtDbContext db, IPasswordHasher<AppUser> hasher, ILoggerFactory logs, ClaimsPrincipal actor, CancellationToken ct) =>
        {
            var user = await db.Users.FindAsync([id], ct);
            if (user is null) return Results.NotFound();
            if (req.Password is not null && req.Password.Length < MinPasswordLength)
                return Results.ValidationProblem(Crud.Errors().Require(false, "password", $"At least {MinPasswordLength} characters"));
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
            }
            await db.SaveChangesAsync(ct);
            return Results.Ok(new UserDto(user.Id, user.Username, user.Role, user.Active));
        });

        users.MapPost("/{id:int}/unlock", async (int id, EbtDbContext db, ILoggerFactory logs, ClaimsPrincipal actor, CancellationToken ct) =>
        {
            var user = await db.Users.FindAsync([id], ct);
            if (user is null) return Results.NotFound();
            user.FailedLogins = 0;
            user.LockedUntil = null;
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

    public static async Task EnsureBootstrapAdminAsync(EbtDbContext db, IPasswordHasher<AppUser> hasher, IConfiguration config, ILogger logger)
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
        if (password == "sidergest123")
            logger.LogWarning("Bootstrap admin created with the well-known development password; change it in Configurações before real use.");
        var admin = new AppUser { Username = username.Trim().ToLower(), PasswordHash = "", Role = UserRole.Admin };
        admin.PasswordHash = hasher.HashPassword(admin, password);
        db.Users.Add(admin);
        await db.SaveChangesAsync();
        logger.LogInformation("Created bootstrap admin user {User}", admin.Username);
    }
}
