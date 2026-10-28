using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Sales;

/// <summary>Adds the most common Brazilian payment terms when they are missing (matched by code).</summary>
public static class PaymentTermSeed
{
    static readonly (string Code, string Name, string Days)[] Terms =
    [
        ("AVISTA", "À vista", "0"),
        ("7D", "7 dias", "7"),
        ("14D", "14 dias", "14"),
        ("21D", "21 dias", "21"),
        ("28D", "28 dias", "28"),
        ("30D", "30 dias", "30"),
        ("45D", "45 dias", "45"),
        ("60D", "60 dias", "60"),
        ("90D", "90 dias", "90"),
        ("30-60", "30/60 dias", "30/60"),
        ("30-60-90", "30/60/90 dias", "30/60/90"),
        ("30-60-90-120", "30/60/90/120 dias", "30/60/90/120"),
    ];

    public static async Task EnsureAsync(EbtDbContext db, CancellationToken ct = default)
    {
        var existing = (await db.PaymentTerms.Select(p => p.Code).ToListAsync(ct)).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var missing = Terms.Where(t => !existing.Contains(t.Code)).ToList();
        if (missing.Count == 0) return;
        db.PaymentTerms.AddRange(missing.Select(t => new PaymentTerm { Code = t.Code, Name = t.Name, Days = t.Days }));
        await db.SaveChangesAsync(ct);
    }
}
