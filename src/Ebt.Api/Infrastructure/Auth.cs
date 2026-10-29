using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
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
}

public class JwtOptions
{
    public string Issuer { get; set; } = "ebt-erp";
    public string Audience { get; set; } = "ebt-erp-clients";
    public string SigningKey { get; set; } = "";
    public int ExpiresMinutes { get; set; } = 480;
}

public class TokenService(JwtOptions options)
{
    public const string VersionClaim = "tv";

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

public record LoginRequest(string? Username, string? Password);
public record LoginResponse(string Token, DateTimeOffset ExpiresAt, string Username, UserRole Role, string[] Permissions);
public record UserDto(int Id, string Username, UserRole Role, bool Active);
public record CreateUserRequest(string Username, string Password, UserRole Role);
public record UpdateUserRequest(UserRole Role, bool Active, string? Password);

public static class AuthEndpoints
{
    public const int MinPasswordLength = 10;
    public const int MaxFailedLogins = 5;
    public static readonly TimeSpan LockoutDuration = TimeSpan.FromMinutes(15);
    private static readonly PasswordHasher<AppUser> DummyHasher = new();
    private static readonly AppUser Dummy = new() { Username = "", PasswordHash = "" };
    private static readonly string DummyHash = DummyHasher.HashPassword(Dummy, "dummy-password-for-timing");


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
                log.LogWarning("Login failed for unknown user {User} from {Ip}", name, http.Connection.RemoteIpAddress);
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
            return Results.Ok(new LoginResponse(token, expires, user.Username, user.Role, Access.PoliciesFor(user.Role)));
        }).AllowAnonymous().RequireRateLimiting(Policies.LoginLimiter);

        auth.MapGet("/me", (ClaimsPrincipal principal) => Results.Ok(new
        {
            username = principal.Identity!.Name,
            role = principal.FindFirstValue(ClaimTypes.Role),
            permissions = Enum.TryParse<UserRole>(principal.FindFirstValue(ClaimTypes.Role), out var r) ? Access.PoliciesFor(r) : [Policies.Read]
        })).RequireAuthorization(Policies.Read);

        var users = app.MapGroup("/api/users").WithTags("Users").RequireAuthorization(Policies.Admin);

        users.MapGet("/", async (EbtDbContext db, CancellationToken ct) =>
            await db.Users.AsNoTracking().OrderBy(u => u.Username).Select(u => new UserDto(u.Id, u.Username, u.Role, u.Active)).ToListAsync(ct));

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
                user.FailedLogins = 0;
                user.LockedUntil = null;
                logs.CreateLogger("Ebt.Auth").LogInformation("User {Target} changed by {Actor}: role {Role}, active {Active}, password changed {Pwd}", user.Username, actor.Identity?.Name, user.Role, user.Active, req.Password is not null);
            }
            await db.SaveChangesAsync(ct);
            return Results.Ok(new UserDto(user.Id, user.Username, user.Role, user.Active));
        });
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
        var admin = new AppUser { Username = username.Trim().ToLower(), PasswordHash = "", Role = UserRole.Admin };
        admin.PasswordHash = hasher.HashPassword(admin, password);
        db.Users.Add(admin);
        await db.SaveChangesAsync();
        logger.LogInformation("Created bootstrap admin user {User}", admin.Username);
    }
}
