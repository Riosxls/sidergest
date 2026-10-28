using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Sales;

/// <summary>Keeps the standard sales terms (prazos) in the database, matched by code. Codes sort in display order.</summary>
public static class PaymentTermSeed
{
    static readonly (string Code, string Name, string Days)[] Terms =
    [
        ("01", "30 dias", "30"),
        ("02", "60 dias", "60"),
        ("03", "90 dias", "90"),
        ("04", "120 dias", "120"),
        ("05", "28 ddf (dias da data do faturamento)", "28"),
        ("06", "30 / 60 dias", "30/60"),
        ("07", "30 / 60 / 90 dias", "30/60/90"),
        ("08", "30 / 60 / 90 / 120 dias", "30/60/90/120"),
        ("09", "15 / 30 / 45 / 60 dias", "15/30/45/60"),
        ("10", "7 dias (para insumos de altíssimo giro)", "7"),
    ];

    // Codes created by an earlier version of this seed.
    static readonly string[] Replaced = ["AVISTA", "7D", "14D", "21D", "28D", "30D", "45D", "60D", "90D", "30-60", "30-60-90", "30-60-90-120"];

    public static async Task EnsureAsync(EbtDbContext db, CancellationToken ct = default)
    {
        var all = await db.PaymentTerms.ToListAsync(ct);
        foreach (var old in all.Where(p => Replaced.Contains(p.Code, StringComparer.OrdinalIgnoreCase)))
        {
            var used = await db.Quotes.AnyAsync(q => q.PaymentTermId == old.Id, ct) || await db.SalesOrders.AnyAsync(o => o.PaymentTermId == old.Id, ct);
            if (used) old.Active = false;
            else db.PaymentTerms.Remove(old);
        }
        var existing = all.Select(p => p.Code).ToHashSet(StringComparer.OrdinalIgnoreCase);
        db.PaymentTerms.AddRange(Terms.Where(t => !existing.Contains(t.Code)).Select(t => new PaymentTerm { Code = t.Code, Name = t.Name, Days = t.Days }));
        await db.SaveChangesAsync(ct);
    }
}
