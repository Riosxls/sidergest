using System.Text;
using System.Text.Json.Serialization;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Ebt.Core.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

var jwt = builder.Configuration.GetSection("Jwt").Get<JwtOptions>() ?? new JwtOptions();
if (Encoding.UTF8.GetByteCount(jwt.SigningKey) < 32)
    throw new InvalidOperationException("Jwt:SigningKey must be at least 32 bytes. Set it via configuration or the Jwt__SigningKey environment variable.");

builder.Services.AddDbContext<EbtDbContext>(o => o
    .UseNpgsql(builder.Configuration.GetConnectionString("Ebt") ?? throw new InvalidOperationException("ConnectionStrings:Ebt is not set."))
    .UseSnakeCaseNamingConvention());
builder.Services.AddScoped<BomService>();
builder.Services.AddScoped<StockService>();
builder.Services.AddPurchasing();
builder.Services.AddProduction();
builder.Services.AddSingleton(jwt);
builder.Services.AddSingleton<TokenService>();
builder.Services.AddExceptionHandler<StockExceptionHandler>();
builder.Services.AddExceptionHandler<DatabaseExceptionHandler>();
builder.Services.AddProblemDetails();
builder.Services.ConfigureHttpJsonOptions(o => o.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(o =>
{
    o.MapInboundClaims = false;
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
builder.Services.AddAuthorizationBuilder()
    .AddPolicy(Policies.Read, p => p.RequireAuthenticatedUser())
    .AddPolicy(Policies.Write, p => p.RequireRole(nameof(UserRole.Admin), nameof(UserRole.Engineering)))
    .AddPolicy(Policies.Admin, p => p.RequireRole(nameof(UserRole.Admin)))
    .AddPolicy(Policies.Stock, p => p.RequireRole(nameof(UserRole.Admin), nameof(UserRole.Stock)));

builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
{
    var origins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? [];
    if (origins.Length > 0) p.WithOrigins(origins).AllowAnyHeader().AllowAnyMethod();
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

app.UseExceptionHandler();
app.UseCors();
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
    await AuthEndpoints.EnsureBootstrapAdminAsync(db, app.Configuration, app.Logger);
}

app.MapGet("/", (IConfiguration c, IWebHostEnvironment e) => Results.Redirect(c.GetValue("Swagger:Enabled", e.IsDevelopment()) ? "/swagger" : "/health")).AllowAnonymous().ExcludeFromDescription();
app.MapGet("/health", async (EbtDbContext db) => await db.Database.CanConnectAsync() ? Results.Ok(new { status = "ok" }) : Results.StatusCode(503)).AllowAnonymous();
app.MapAuth();
app.MapMasterData();
app.MapProducts();
app.MapInventory();
app.MapPurchasing();
app.MapProduction();

app.Run();

public partial class Program;
