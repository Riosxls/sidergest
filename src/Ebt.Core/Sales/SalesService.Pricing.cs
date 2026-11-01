using static Ebt.Core.Services.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Inventory;
using Ebt.Core.Services;
using Ebt.Core.Production;
using Ebt.Core.Viability;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Sales;

/// <summary>Sales settings, price list lookup, company validation and quote totals/approval rules.</summary>
public sealed partial class SalesService
{
    public async Task<SalesSettings> SettingsAsync(CancellationToken ct = default) =>
        await db.SalesSettings.FirstOrDefaultAsync(ct) ?? throw new InvalidOperationException("sales_settings row missing");

    public async Task<PriceListEntry?> PriceAsync(int productId, int? customerId, DateOnly date, CancellationToken ct = default) =>
        await db.PriceList.AsNoTracking()
            .Where(p => p.ProductId == productId && (p.CustomerId == customerId || p.CustomerId == null) && p.ValidFrom <= date && (p.ValidTo == null || p.ValidTo >= date))
            .OrderBy(p => p.CustomerId == null).ThenByDescending(p => p.ValidFrom)
            .FirstOrDefaultAsync(ct);

    public static string CompanyOf(string? company) => Clean(company)?.ToUpperInvariant() switch
    {
        null or "EBT" => "EBT",
        "BST" => "BST",
        _ => throw SalesException.Invalid("company", "EBT or BST")
    };

    public static QuoteTotals Totals(IEnumerable<(decimal Qty, decimal Price, decimal Ipi, decimal? List)> lines) =>
        Totals(lines.Select(l => (l.Qty, l.Price, l.Ipi, l.List, 0m)));

    public static QuoteTotals Totals(IEnumerable<(decimal Qty, decimal Price, decimal Ipi, decimal? List, decimal Icms)> lines)
    {
        var list = lines.ToList();
        var products = list.Sum(l => Money(l.Qty * l.Price));
        var ipi = list.Sum(l => Money(l.Qty * l.Price * l.Ipi / 100m));
        var icms = list.Sum(l => Money(l.Qty * l.Price * l.Icms / 100m));
        var discount = list.Where(l => l.List is > 0).Select(l => Math.Round((1 - l.Price / l.List!.Value) * 100m, 2)).DefaultIfEmpty(0).Max();
        return new QuoteTotals(products, ipi, products + ipi, discount, list.Count(l => l.List is not > 0), icms);
    }

    public static QuoteTotals Totals(Quote q) => Totals(q.Lines.Select(l => (l.Quantity, l.UnitPrice, l.IpiPercent, l.ListPrice, l.IcmsPercent)));

    /// <summary>A quote needs the manager when a discount passes the limit, or (if the setting is on) when a price was typed by hand with no list price to compare.</summary>
    public static bool NeedsApprovalFor(QuoteTotals t, SalesSettings s) => t.MaxDiscountPercent > s.MaxDiscountPercent || s.OffListNeedsApproval && t.OffListLines > 0;
}
