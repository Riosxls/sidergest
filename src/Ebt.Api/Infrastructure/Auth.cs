using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
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
    public (string Token, DateTimeOffset ExpiresAt) Issue(AppUser user)
    {
        var expires = DateTimeOffset.UtcNow.AddMinutes(options.ExpiresMinutes);
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.Username),
            new Claim(ClaimTypes.Role, user.Role.ToString())
        };
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(options.SigningKey));
        var token = new JwtSecurityToken(options.Issuer, options.Audience, claims, expires: expires.UtcDateTime,
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return (new JwtSecurityTokenHandler().WriteToken(token), expires);
    }
}

public record LoginRequest(string Username, string Password);
public record LoginResponse(string Token, DateTimeOffset ExpiresAt, string Username, UserRole Role);
public record UserDto(int Id, string Username, UserRole Role, bool Active);
public record CreateUserRequest(string Username, string Password, UserRole Role);
public record UpdateUserRequest(UserRole Role, bool Active, string? Password);

public static class AuthEndpoints
{
    public const int MinPasswordLength = 10;
    private static readonly PasswordHasher<AppUser> Hasher = new();

    public static string Hash(AppUser user, string password) => Hasher.HashPassword(user, password);

    public static void MapAuth(this WebApplication app)
    {
        var auth = app.MapGroup("/api/auth").WithTags("Auth");

        auth.MapPost("/login", async (LoginRequest req, EbtDbContext db, TokenService tokens, CancellationToken ct) =>
        {
            var user = await db.Users.FirstOrDefaultAsync(u => u.Username == req.Username.Trim().ToLower(), ct);
            if (user is null || !user.Active) return Results.Unauthorized();
            var result = Hasher.VerifyHashedPassword(user, user.PasswordHash, req.Password);
            if (result == PasswordVerificationResult.Failed) return Results.Unauthorized();
            if (result == PasswordVerificationResult.SuccessRehashNeeded)
            {
                user.PasswordHash = Hash(user, req.Password);
                await db.SaveChangesAsync(ct);
            }
            var (token, expires) = tokens.Issue(user);
            return Results.Ok(new LoginResponse(token, expires, user.Username, user.Role));
        }).AllowAnonymous();

        auth.MapGet("/me", (ClaimsPrincipal principal) => Results.Ok(new
        {
            username = principal.Identity!.Name,
            role = principal.FindFirstValue(ClaimTypes.Role)
        })).RequireAuthorization(Policies.Read);

        var users = app.MapGroup("/api/users").WithTags("Users").RequireAuthorization(Policies.Admin);

        users.MapGet("/", async (EbtDbContext db, CancellationToken ct) =>
            await db.Users.AsNoTracking().OrderBy(u => u.Username).Select(u => new UserDto(u.Id, u.Username, u.Role, u.Active)).ToListAsync(ct));

        users.MapPost("/", async (CreateUserRequest req, EbtDbContext db, CancellationToken ct) =>
        {
            var errors = Crud.Errors()
                .Require(Crud.Has(req.Username), "username", "Required")
                .Require((req.Password ?? "").Length >= MinPasswordLength, "password", $"At least {MinPasswordLength} characters");
            if (errors.Count > 0) return Results.ValidationProblem(errors);
            var user = new AppUser { Username = req.Username.Trim().ToLower(), PasswordHash = "", Role = req.Role };
            user.PasswordHash = Hash(user, req.Password!);
            db.Users.Add(user);
            await db.SaveChangesAsync(ct);
            return Results.Created($"/api/users/{user.Id}", new UserDto(user.Id, user.Username, user.Role, user.Active));
        });

        users.MapPut("/{id:int}", async (int id, UpdateUserRequest req, EbtDbContext db, CancellationToken ct) =>
        {
            var user = await db.Users.FindAsync([id], ct);
            if (user is null) return Results.NotFound();
            if (req.Password is not null && req.Password.Length < MinPasswordLength)
                return Results.ValidationProblem(Crud.Errors().Require(false, "password", $"At least {MinPasswordLength} characters"));
            user.Role = req.Role;
            user.Active = req.Active;
            if (req.Password is not null) user.PasswordHash = Hash(user, req.Password);
            await db.SaveChangesAsync(ct);
            return Results.Ok(new UserDto(user.Id, user.Username, user.Role, user.Active));
        });
    }

    public static async Task EnsureBootstrapAdminAsync(EbtDbContext db, IConfiguration config, ILogger logger)
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
        admin.PasswordHash = Hash(admin, password);
        db.Users.Add(admin);
        await db.SaveChangesAsync();
        logger.LogInformation("Created bootstrap admin user {User}", admin.Username);
    }
}
