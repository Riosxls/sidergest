using Ebt.Api.Endpoints;
using Ebt.Core.Entities;
using Microsoft.AspNetCore.Authorization;

namespace Ebt.Api.Infrastructure;

/// <summary>
/// Single source of truth for who may do what. Every authorization policy is registered from this matrix,
/// and /api/auth/me returns the policies the caller satisfies so clients do not duplicate role lists.
/// </summary>
public static class Access
{
    private const UserRole A = UserRole.Admin;

    public static readonly IReadOnlyDictionary<string, UserRole[]> Matrix = new Dictionary<string, UserRole[]>
    {
        [Policies.Write] = [A, UserRole.Engineering],
        [Policies.Admin] = [A],
        [Policies.Stock] = [A, UserRole.Stock],
        [PurchasingPolicies.Request] = [A, UserRole.Engineering, UserRole.Stock, UserRole.Purchasing],
        [PurchasingPolicies.Buy] = [A, UserRole.Purchasing],
        [PurchasingPolicies.Receive] = [A, UserRole.Purchasing, UserRole.Stock],
        [ProductionPolicies.Plan] = [A, UserRole.Production],
        [ProductionPolicies.Materials] = [A, UserRole.Production, UserRole.Stock],
        [CertificatePolicies.Manage] = [A, UserRole.Engineering, UserRole.Production, UserRole.Sales, UserRole.SalesManager],
        [FiscalPolicies.Prices] = [A, UserRole.SalesManager],
        [FiscalPolicies.Cancel] = [A, UserRole.SalesManager],
        [SteelPolicies.Write] = [A, UserRole.Stock, UserRole.Purchasing],
        [ViabilityPolicies.Quality] = [A, UserRole.Engineering],
        [ViabilityPolicies.Production] = [A, UserRole.Production],
        [ViabilityPolicies.Commercial] = [A, UserRole.Sales, UserRole.SalesManager],
        [SalesPolicies.Customers] = [A, UserRole.Engineering, UserRole.Sales, UserRole.SalesManager],
        [SalesPolicies.Sell] = [A, UserRole.Sales, UserRole.SalesManager],
        [SalesPolicies.Approve] = [A, UserRole.SalesManager],
        [SalesPolicies.Release] = [A, UserRole.Sales, UserRole.SalesManager, UserRole.Production],
        [SalesPolicies.Ship] = [A, UserRole.Sales, UserRole.SalesManager, UserRole.Stock],
    };

    public static void Register(AuthorizationOptions options)
    {
        options.AddPolicy(Policies.Read, p => p.RequireAuthenticatedUser());
        foreach (var (name, roles) in Matrix)
            options.AddPolicy(name, p => p.RequireRole(roles.Select(r => r.ToString())));
    }

    /// <summary>Policy names a user with this role satisfies (the read policy applies to everyone signed in).</summary>
    public static string[] PoliciesFor(UserRole role) =>
        [Policies.Read, .. Matrix.Where(kv => kv.Value.Contains(role)).Select(kv => kv.Key).Order()];
}
