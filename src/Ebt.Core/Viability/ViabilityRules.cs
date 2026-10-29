using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Sales;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Viability;

public static class ViabilityRules
{
    private static readonly SalesOrderStatus[] Counted = [SalesOrderStatus.Created, SalesOrderStatus.Released, SalesOrderStatus.PartiallyShipped, SalesOrderStatus.Shipped, SalesOrderStatus.Delivered];

    public static async Task<Dictionary<int, int>> UsedOrdersAsync(EbtDbContext db, IReadOnlyCollection<int> studyIds, int? excludeOrderId, CancellationToken ct)
    {
        var rows = await db.SalesOrderLines.AsNoTracking()
            .Where(l => l.FeasibilityStudyId != null && studyIds.Contains(l.FeasibilityStudyId.Value) && Counted.Contains(l.Order!.Status) && l.OrderId != excludeOrderId)
            .Select(l => new { Study = l.FeasibilityStudyId!.Value, l.OrderId }).Distinct().ToListAsync(ct);
        return rows.GroupBy(r => r.Study).ToDictionary(g => g.Key, g => g.Count());
    }

    public static async Task ValidateAsync(EbtDbContext db, int customerId, IEnumerable<(int ProductId, int? StudyId)> lines, int? excludeOrderId, CancellationToken ct)
    {
        var list = lines.ToList();
        var ids = list.Where(l => l.StudyId != null).Select(l => l.StudyId!.Value).Distinct().ToList();
        if (ids.Count == 0) return;
        var studies = await db.FeasibilityStudies.AsNoTracking().Where(f => ids.Contains(f.Id)).ToDictionaryAsync(f => f.Id, ct);
        var used = await UsedOrdersAsync(db, ids, excludeOrderId, ct);
        foreach (var (n, l) in list.Select((l, n) => (n, l)))
        {
            if (l.StudyId is not { } id) continue;
            var f = $"lines[{n}].feasibilityId";
            if (!studies.TryGetValue(id, out var s)) throw SalesException.Invalid(f, "Feasibility study not found");
            if (s.Status != FeasibilityStatus.Approved) throw SalesException.Invalid(f, $"{s.Reference} is not approved yet");
            if (s.CustomerId != customerId) throw SalesException.Invalid(f, $"{s.Reference} belongs to another customer");
            if (s.ProductId is { } p && p != l.ProductId) throw SalesException.Invalid(f, $"{s.Reference} covers another product");
            if (used.GetValueOrDefault(id) >= s.OrdersAllowed) throw SalesException.Conflict($"{s.Reference} already covered its {s.OrdersAllowed} orders; request a new study");
        }
    }

    public static async Task<Dictionary<int, int>> UsableForQuoteAsync(EbtDbContext db, int quoteId, CancellationToken ct)
    {
        var studies = await db.FeasibilityStudies.AsNoTracking().Where(f => f.QuoteId == quoteId && f.Status == FeasibilityStatus.Approved && f.ProductId != null).OrderBy(f => f.Number).ToListAsync(ct);
        var used = await UsedOrdersAsync(db, studies.Select(s => s.Id).ToList(), null, ct);
        var map = new Dictionary<int, int>();
        foreach (var s in studies.Where(s => used.GetValueOrDefault(s.Id) < s.OrdersAllowed))
            map.TryAdd(s.ProductId!.Value, s.Id);
        return map;
    }

    public static string RoutingNote(FeasibilityStudy s) =>
        string.Join(" · ", new[] { s.Reference, Part("transformações", s.Transformations), Part("acabamento", s.Finishing), Part("embalagem", s.Packaging) }.Where(x => x is not null));

    private static string? Part(string label, string? value) => string.IsNullOrWhiteSpace(value) ? null : $"{label}: {value.Trim()}";
}
