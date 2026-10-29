using System.Text;
using System.Threading.RateLimiting;
using System.Text.Json.Serialization;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;

if (args.Contains("--healthcheck"))
{
    // Used by the container HEALTHCHECK: the runtime image has no curl/wget.
    var port = (Environment.GetEnvironmentVariable("ASPNETCORE_HTTP_PORTS") ?? "8080").Split(';')[0];
    using var probe = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
    try { Environment.Exit((await probe.GetAsync($"http://localhost:{port}/health")).IsSuccessStatusCode ? 0 : 1); }
    catch { Environment.Exit(1); }
}

var builder = WebApplication.CreateBuilder(args);

var jwt = builder.Configuration.GetSection("Jwt").Get<JwtOptions>() ?? new JwtOptions();
if (Encoding.UTF8.GetByteCount(jwt.SigningKey) < 32)
    throw new InvalidOperationException("Jwt:SigningKey must be at least 32 bytes. Set it via configuration or the Jwt__SigningKey environment variable.");
if (!builder.Environment.IsDevelopment() && !builder.Environment.IsEnvironment("Testing")
    && (jwt.SigningKey.Contains("change-me", StringComparison.OrdinalIgnoreCase) || jwt.SigningKey.Contains("dev-only", StringComparison.OrdinalIgnoreCase)))
    throw new InvalidOperationException("Jwt:SigningKey is a placeholder value; set a real random secret (Jwt__SigningKey / EBT_JWT_KEY).");
Ebt.Core.Services.Clock.Configure(builder.Configuration["Clock:TimeZone"]);

builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentUser, HttpCurrentUser>();
builder.Services.AddScoped<AuditInterceptor>();
builder.Services.AddDbContext<EbtDbContext>((sp, o) => o
    .UseNpgsql(builder.Configuration.GetConnectionString("Ebt") ?? throw new InvalidOperationException("ConnectionStrings:Ebt is not set."))
    .UseSnakeCaseNamingConvention()
    .AddInterceptors(sp.GetRequiredService<AuditInterceptor>()));
builder.Services.AddScoped<BomService>();
builder.Services.AddScoped<StockService>();
builder.Services.AddPurchasing();
builder.Services.AddProduction();
builder.Services.AddFiscal(builder.Configuration);
builder.Services.AddSales();
builder.Services.AddCertificates();
builder.Services.AddViability();
builder.Services.AddSteel();
builder.Services.AddSingleton(jwt);
builder.Services.AddSingleton<TokenService>();
builder.Services.AddSingleton<IPasswordHasher<AppUser>, PasswordHasher<AppUser>>();
builder.Services.AddHostedService<QuoteExpiryService>();
builder.Services.AddExceptionHandler<StockExceptionHandler>();
builder.Services.AddExceptionHandler<DatabaseExceptionHandler>();
builder.Services.AddProblemDetails();
builder.Services.ConfigureHttpJsonOptions(o => o.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(o =>
{
    o.MapInboundClaims = false;
    o.Events = new JwtBearerEvents { OnTokenValidated = TokenService.ValidateAsync };
    o.TokenValidationParameters = new TokenValidationParameters
    {
        ValidIssuer = jwt.Issuer,
        ValidAudience = jwt.Audience,
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey)),
        NameClaimType = System.Security.Claims.ClaimTypes.Name,
        RoleClaimType = System.Security.Claims.ClaimTypes.Role,
        ClockSkew = TimeSpan.FromMinutes(1)
    };
});
builder.Services.AddAuthorization(Access.Register);

builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    var perMinute = builder.Configuration.GetValue("RateLimit:LoginPerMinute", 10);
    o.AddPolicy(Policies.LoginLimiter, ctx => RateLimitPartition.GetFixedWindowLimiter(ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = perMinute, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
});
if (builder.Configuration.GetValue("Proxy:Trusted", false))
    builder.Services.Configure<ForwardedHeadersOptions>(o =>
    {
        o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
        o.KnownNetworks.Clear();
        o.KnownProxies.Clear();
    });

builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
{
    var origins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? [];
    if (origins.Length > 0) p.WithOrigins(origins).AllowAnyHeader().AllowAnyMethod().WithExposedHeaders("ETag");
}));

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(o =>
{
    o.SwaggerDoc("v1", new OpenApiInfo { Title = "EBT ERP API", Version = "v1" });
    o.CustomSchemaIds(t => t.FullName!.Replace("+", "."));
    var scheme = new OpenApiSecurityScheme { Type = SecuritySchemeType.Http, Scheme = "bearer", BearerFormat = "JWT", Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" } };
    o.AddSecurityDefinition("Bearer", scheme);
    o.AddSecurityRequirement(new OpenApiSecurityRequirement { [scheme] = [] });
});

var app = builder.Build();

if (app.Configuration.GetValue("Proxy:Trusted", false)) app.UseForwardedHeaders();
if (!app.Environment.IsDevelopment()) app.UseHsts();
app.UseExceptionHandler();
app.Use(async (ctx, next) =>
{
    ctx.Response.Headers["X-Content-Type-Options"] = "nosniff";
    ctx.Response.Headers["X-Frame-Options"] = "DENY";
    ctx.Response.Headers["Referrer-Policy"] = "no-referrer";
    if (ctx.Request.Path.StartsWithSegments("/api")) ctx.Response.Headers.CacheControl = "no-store";
    await next();
});
app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

if (app.Configuration.GetValue("Swagger:Enabled", app.Environment.IsDevelopment()))
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<EbtDbContext>();
    if (app.Configuration.GetValue("Database:MigrateOnStartup", false)) await db.Database.MigrateAsync();
    await AuthEndpoints.EnsureBootstrapAdminAsync(db, scope.ServiceProvider.GetRequiredService<IPasswordHasher<AppUser>>(), app.Configuration, app.Logger);
}

app.MapGet("/", (IConfiguration c, IWebHostEnvironment e) => Results.Redirect(c.GetValue("Swagger:Enabled", e.IsDevelopment()) ? "/swagger" : "/health")).AllowAnonymous().ExcludeFromDescription();
app.MapGet("/health", async (EbtDbContext db) => await db.Database.CanConnectAsync() ? Results.Ok(new { status = "ok" }) : Results.StatusCode(503)).AllowAnonymous();
app.MapAuth();
app.MapAudit();
app.MapMasterData();
app.MapProducts();
app.MapInventory();
app.MapPurchasing();
app.MapProduction();
app.MapSales();
app.MapCertificates();
app.MapFiscal();
app.MapReports();
app.MapViability();
app.MapSteel();

app.Run();

public partial class Program;
