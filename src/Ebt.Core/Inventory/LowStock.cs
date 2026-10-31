using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Inventory;

/// <summary>A material whose on-hand stock fell below its minimum. Quantities are in the stock unit, the suggestion also in the purchase unit.</summary>
public sealed record LowStockRow(int MaterialId, string Code, string Description, string StockUnit, string PurchaseUnit, decimal OnHand, decimal MinStock, decimal? MaxStock,
    decimal Incoming, decimal Missing, decimal SuggestedStock, decimal SuggestedPurchase, bool HasOpenRequisition, bool Purchasable);

public static class LowStock
{
    private static readonly RequisitionStatus[] OpenRequisition = [RequisitionStatus.PendingApproval, RequisitionStatus.Approved, RequisitionStatus.Quoting, RequisitionStatus.QuoteApproved];

    /// <summary>Active materials with a minimum, where on-hand (all locations, any lot) is below it. The target is the maximum, or the minimum when none is set.</summary>
    public static async Task<List<LowStockRow>> ListAsync(EbtDbContext db, IReadOnlyCollection<int>? materialIds, CancellationToken ct)
    {
        var materials = db.Materials.AsNoTracking().Where(m => m.Active && m.MinStock > 0);
        if (materialIds is { Count: > 0 }) materials = materials.Where(m => materialIds.Contains(m.Id));
        var list = await materials.ToListAsync(ct);
        var ids = list.Select(m => m.Id).ToList();
        var onHand = await db.StockBalances.AsNoTracking().Where(b => b.MaterialId != null && ids.Contains(b.MaterialId.Value))
            .GroupBy(b => b.MaterialId!.Value).Select(g => new { Id = g.Key, Qty = g.Sum(x => x.Quantity) }).ToDictionaryAsync(x => x.Id, x => x.Qty, ct);
        var lines = await db.PurchaseOrderLines.AsNoTracking()
            .Where(l => l.MaterialId != null && ids.Contains(l.MaterialId.Value) && !l.Closed && l.ReceivedQuantity < l.Quantity
                && (l.PurchaseOrder!.Status == PurchaseOrderStatus.Open || l.PurchaseOrder.Status == PurchaseOrderStatus.PartiallyReceived))
            .Select(l => new { Id = l.MaterialId!.Value, l.Unit, Open = l.Quantity - l.ReceivedQuantity }).ToListAsync(ct);
        var requested = (await db.PurchaseRequisitions.AsNoTracking().Where(r => r.MaterialId != null && ids.Contains(r.MaterialId.Value) && OpenRequisition.Contains(r.Status) && r.PurchaseOrderLineId == null)
            .Select(r => r.MaterialId!.Value).Distinct().ToListAsync(ct)).ToHashSet();

        var rows = new List<LowStockRow>();
        foreach (var m in list)
        {
            var have = onHand.GetValueOrDefault(m.Id);
            if (have >= m.MinStock) continue;
            var incoming = lines.Where(l => l.Id == m.Id).Sum(l => string.Equals(l.Unit, m.StockUnit, StringComparison.OrdinalIgnoreCase) ? l.Open : l.Open * m.PurchaseFactor);
            var target = m.MaxStock ?? m.MinStock!.Value;
            var suggestedStock = Math.Max(0m, target - have - incoming);
            var factor = m.PurchaseFactor > 0 ? m.PurchaseFactor : 1m;
            var purchase = string.Equals(m.PurchaseUnit, m.StockUnit, StringComparison.OrdinalIgnoreCase) ? suggestedStock : suggestedStock / factor;
            if (m.PurchaseLot is > 0) purchase = Math.Ceiling(purchase / m.PurchaseLot.Value) * m.PurchaseLot.Value;
            rows.Add(new LowStockRow(m.Id, m.Code, m.Description, m.StockUnit, m.PurchaseUnit, have, m.MinStock!.Value, m.MaxStock, incoming, Math.Max(0m, m.MinStock.Value - have),
                suggestedStock, Math.Round(purchase, 3, MidpointRounding.AwayFromZero), requested.Contains(m.Id), m.GeneratesPurchaseOrder));
        }
        return rows.OrderBy(r => r.OnHand / r.MinStock).ThenBy(r => r.Code).ToList();
    }
}
