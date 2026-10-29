using Ebt.Api.Infrastructure;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Sales;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;
using static Ebt.Api.Infrastructure.Crud;

namespace Ebt.Api.Endpoints;

public record MaterialConsumptionRow(string MaterialCode, string MaterialDescription, string Unit, int? GroupId, string? GroupName, DateOnly Date, string DocType, string DocNumber,
    decimal QuantityKg, string? InvoiceNumber, string Note);
public record MaterialConsumptionOut(DateOnly From, DateOnly To, IReadOnlyList<MaterialConsumptionRow> Rows, decimal TotalKg);

public record BillingRow(int CustomerId, string Customer, decimal Billed, decimal Icms, decimal Ipi, decimal TotalNoIpi, decimal Kg, decimal? AvgSalePrice, decimal? AvgMaterialCost);
public record BillingSection(string Key, IReadOnlyList<BillingRow> Rows, BillingRow Total);
public record BillingSummaryOut(DateOnly From, DateOnly To, IReadOnlyList<BillingSection> Companies, BillingRow GrandTotal, BillingSection Returns, BillingRow Net, IReadOnlyList<string> Notes);

public static class ReportsEndpoints
{
    private sealed record Sale(int CustomerId, string Customer, string Company, DateOnly Date, decimal Quantity, decimal Value, decimal Ipi, decimal Icms, decimal Kg, decimal? MaterialCost, decimal? MaterialKg);

    public static void MapReports(this WebApplication app)
    {
        var g = app.MapGroup("/api/reports").WithTags("Reports").RequireAuthorization(Policies.Read);

        g.MapGet("/material-consumption", async (EbtDbContext db, BomService bom, DateOnly? from, DateOnly? to, int? groupId, string? materialCode, string? q, CancellationToken ct) =>
        {
            var (f, t) = Range(from, to);
            var ship = await ShippedLines(db, f, t, ct);
            var productIds = ship.Select(s => s.ProductId).Distinct().ToList();

            // Materials per unit of product: from the production order when the line was produced, otherwise from the product BOM.
            var poIds = ship.Where(s => s.ProductionOrderId != null).Select(s => s.ProductionOrderId!.Value).Distinct().ToList();
            var poMaterials = await db.ProductionOrderMaterials.AsNoTracking().Where(m => poIds.Contains(m.OrderId) && m.MaterialId != null)
                .Select(m => new { m.OrderId, MaterialId = m.MaterialId!.Value, m.QuantityPerUnit }).ToListAsync(ct);
            var byOrder = poMaterials.GroupBy(m => m.OrderId).ToDictionary(x => x.Key, x => x.GroupBy(m => m.MaterialId).Select(m => (Id: m.Key, PerUnit: m.Sum(y => y.QuantityPerUnit))).ToList());
            var bomCache = new Dictionary<int, List<(int Id, decimal PerUnit)>>();
            foreach (var pid in productIds)
            {
                var ex = await bom.ExplodeAsync(pid, 1m, ct);
                bomCache[pid] = ex?.Materials.Select(m => (m.MaterialId, m.TotalQuantity)).ToList() ?? new();
            }

            var materialIds = byOrder.Values.SelectMany(x => x.Select(y => y.Id)).Concat(bomCache.Values.SelectMany(x => x.Select(y => y.Id))).Distinct().ToList();
            var materials = await db.Materials.AsNoTracking().Where(m => materialIds.Contains(m.Id))
                .Select(m => new { m.Id, m.Code, m.Description, m.StockUnit, m.GroupId, Group = m.Group != null ? m.Group.Name : null }).ToDictionaryAsync(m => m.Id, ct);

            var rows = new List<MaterialConsumptionRow>();
            foreach (var s in ship)
            {
                var perUnit = s.ProductionOrderId is { } po && byOrder.TryGetValue(po, out var l) ? l : bomCache.GetValueOrDefault(s.ProductId) ?? new();
                foreach (var (mid, per) in perUnit)
                {
                    if (!materials.TryGetValue(mid, out var m)) continue;
                    var docType = s.ProductionOrderId != null ? "OP" : "Entrega";
                    rows.Add(new MaterialConsumptionRow(m.Code, m.Description, m.StockUnit, m.GroupId, m.Group, s.Date, docType, s.ProductionOrderId != null ? s.ProductionReference! : s.DeliveryReference,
                        Math.Round(per * s.Quantity, 3), s.InvoiceNumber, $"{s.ProductCode}-{s.Customer}"));
                }
            }

            IEnumerable<MaterialConsumptionRow> x = rows;
            if (groupId is { } gid) x = x.Where(r => r.GroupId == gid);
            if (Has(materialCode)) x = x.Where(r => r.MaterialCode.Contains(materialCode!.Trim(), StringComparison.OrdinalIgnoreCase));
            if (Has(q))
            {
                var term = q!.Trim();
                x = x.Where(r => new[] { r.MaterialCode, r.MaterialDescription, r.DocNumber, r.InvoiceNumber, r.Note }.Any(v => v?.Contains(term, StringComparison.OrdinalIgnoreCase) == true));
            }
            var list = x.OrderBy(r => r.MaterialCode).ThenBy(r => r.Date).ThenBy(r => r.DocNumber).ToList();
            return Results.Ok(new MaterialConsumptionOut(f, t, list, list.Sum(r => r.QuantityKg)));
        });

        g.MapGet("/billing-summary", async (EbtDbContext db, DateOnly? from, DateOnly? to, string? company, CancellationToken ct) =>
        {
            var (f, t) = Range(from, to);
            var co = Has(company) ? SalesService.CompanyOf(company) : null;
            var ship = await ShippedLines(db, f, t, ct);

            var sales = ship.Select(s => new Sale(s.CustomerId, s.Customer, s.Company, s.Date, s.Quantity,
                Money(s.Quantity * s.UnitPrice), Money(s.Quantity * s.UnitPrice * s.IpiPercent / 100m), Money(s.Quantity * s.UnitPrice * s.IcmsPercent / 100m),
                s.Quantity * (s.NetWeightKg ?? 0m), s.PoQuantity > 0 && s.PoMaterialCost != null ? s.Quantity * s.PoMaterialCost / s.PoQuantity : null,
                s.PoQuantity > 0 && s.PoMaterialCost != null ? s.Quantity * (s.NetWeightKg ?? 0m) : null)).ToList();

            // Returns: customer returns posted in stock, valued at the latest sale price of that product to that customer.
            var returns = await db.StockMovements.AsNoTracking()
                .Where(m => m.Type == MovementType.CustomerReturn && m.ProductId != null && m.Document!.CustomerId != null && !m.Document.Reversed && m.Date >= f && m.Date <= t)
                .Select(m => new { CustomerId = m.Document!.CustomerId!.Value, Customer = m.Document.Customer!.Name, m.ProductId, m.Quantity, m.Date, NetWeight = m.Product!.NetWeightKg }).ToListAsync(ct);
            var retCustomers = returns.Select(r => r.CustomerId).Distinct().ToList();
            var prices = await db.SalesOrderLines.AsNoTracking().Where(l => retCustomers.Contains(l.Order!.CustomerId))
                .Select(l => new { l.Order!.CustomerId, l.ProductId, l.UnitPrice, l.IpiPercent, l.IcmsPercent, l.Order.Company, l.Order.CreatedAt }).ToListAsync(ct);
            var returnSales = new List<Sale>();
            foreach (var r in returns)
            {
                var p = prices.Where(x => x.CustomerId == r.CustomerId && x.ProductId == r.ProductId).OrderByDescending(x => x.CreatedAt).FirstOrDefault();
                if (p is null) continue;
                var qty = Math.Abs(r.Quantity);
                returnSales.Add(new Sale(r.CustomerId, r.Customer, p.Company, r.Date, qty, Money(qty * p.UnitPrice), Money(qty * p.UnitPrice * p.IpiPercent / 100m),
                    Money(qty * p.UnitPrice * p.IcmsPercent / 100m), qty * (r.NetWeight ?? 0m), null, null));
            }

            if (co is not null)
            {
                sales = sales.Where(s => s.Company == co).ToList();
                returnSales = returnSales.Where(s => s.Company == co).ToList();
            }

            var companies = new List<BillingSection>();
            foreach (var key in new[] { "EBT", "BST" })
            {
                if (co is not null && co != key) continue;
                companies.Add(Section(key, sales.Where(s => s.Company == key).ToList()));
            }
            var grand = Total(sales);
            var ret = Section("Devoluções", returnSales);
            var net = Subtract(grand, ret.Total);
            var notes = new List<string>
            {
                "Faturamento = itens de entregas expedidas (NF) no período, a preço do pedido.",
                "Valor Fat. = produtos + IPI. ICMS considerado incluso no preço. Total S/IPI = valor dos produtos.",
                "PM.M considera somente itens com custo de material fechado na OP.",
                "Devoluções = devoluções de cliente lançadas no estoque, valoradas ao último preço do cliente."
            };
            return Results.Ok(new BillingSummaryOut(f, t, companies, grand, ret, net, notes));
        });
    }

    private sealed record Shipped(int CustomerId, string Customer, string Company, DateOnly Date, decimal Quantity, decimal UnitPrice, decimal IpiPercent, decimal IcmsPercent,
        int ProductId, decimal? NetWeightKg, int? ProductionOrderId, string? ProductionReference, decimal PoQuantity, decimal? PoMaterialCost, string DeliveryReference, string? InvoiceNumber, string ProductCode);

    private static async Task<List<Shipped>> ShippedLines(EbtDbContext db, DateOnly from, DateOnly to, CancellationToken ct)
    {
        var lo = new DateTimeOffset(from.AddDays(-1).ToDateTime(TimeOnly.MinValue), TimeSpan.Zero);
        var hi = new DateTimeOffset(to.AddDays(2).ToDateTime(TimeOnly.MinValue), TimeSpan.Zero);
        var rows = await db.DeliveryLines.AsNoTracking()
            .Where(l => (l.Delivery!.Status == DeliveryStatus.Shipped || l.Delivery.Status == DeliveryStatus.Delivered) && l.Delivery.ShippedAt >= lo && l.Delivery.ShippedAt < hi)
            .Select(l => new
            {
                l.Quantity, ShippedAt = l.Delivery!.ShippedAt!.Value, DeliveryReference = l.Delivery.Reference, l.Delivery.InvoiceNumber,
                CustomerId = l.Delivery.Order!.CustomerId, Customer = l.Delivery.Order.Customer!.Name, l.Delivery.Order.Company,
                Line = l.OrderLine!, ProductId = l.OrderLine!.ProductId, ProductCode = l.OrderLine.Product!.Code, NetWeightKg = l.OrderLine.Product!.NetWeightKg,
                PoRef = l.OrderLine.ProductionOrder != null ? l.OrderLine.ProductionOrder.Reference : null,
                PoQty = l.OrderLine.ProductionOrder != null ? l.OrderLine.ProductionOrder.Quantity : 0m,
                PoCost = l.OrderLine.ProductionOrder != null ? l.OrderLine.ProductionOrder.MaterialCost : null
            }).ToListAsync(ct);
        return rows.Select(r => new Shipped(r.CustomerId, r.Customer, r.Company, DateOnly.FromDateTime(r.ShippedAt.ToLocalTime().DateTime), r.Quantity, r.Line.UnitPrice, r.Line.IpiPercent, r.Line.IcmsPercent,
                r.ProductId, r.NetWeightKg, r.Line.ProductionOrderId, r.PoRef, r.PoQty, r.PoCost, r.DeliveryReference, r.InvoiceNumber, r.ProductCode))
            .Where(r => r.Date >= from && r.Date <= to).ToList();
    }

    private static (DateOnly From, DateOnly To) Range(DateOnly? from, DateOnly? to)
    {
        var today = SalesService.Today();
        var f = from ?? new DateOnly(today.Year, today.Month, 1);
        var t = to ?? f.AddMonths(1).AddDays(-1);
        return (f, t < f ? f : t);
    }

    private static decimal Money(decimal d) => Math.Round(d, 2, MidpointRounding.AwayFromZero);

    private static BillingSection Section(string key, List<Sale> sales) =>
        new(key, sales.GroupBy(s => (s.CustomerId, s.Customer)).Select(g => Row(g.Key.CustomerId, g.Key.Customer, g.ToList())).OrderByDescending(r => r.Billed).ThenBy(r => r.Customer).ToList(), Total(sales));

    private static BillingRow Total(List<Sale> sales) => Row(0, "Total", sales);

    private static BillingRow Row(int id, string name, List<Sale> sales)
    {
        var noIpi = sales.Sum(s => s.Value);
        var ipi = sales.Sum(s => s.Ipi);
        var kg = sales.Sum(s => s.Kg);
        var costed = sales.Where(s => s.MaterialCost != null).ToList();
        var costedKg = costed.Sum(s => s.MaterialKg ?? 0m);
        return new BillingRow(id, name, noIpi + ipi, sales.Sum(s => s.Icms), ipi, noIpi, kg, kg > 0 ? Math.Round(noIpi / kg, 4) : null,
            costedKg > 0 ? Math.Round(costed.Sum(s => s.MaterialCost!.Value) / costedKg, 4) : null);
    }

    private static BillingRow Subtract(BillingRow a, BillingRow b) =>
        new(0, "Líquido", a.Billed - b.Billed, a.Icms - b.Icms, a.Ipi - b.Ipi, a.TotalNoIpi - b.TotalNoIpi, a.Kg - b.Kg, a.Kg - b.Kg > 0 ? Math.Round((a.TotalNoIpi - b.TotalNoIpi) / (a.Kg - b.Kg), 4) : null, a.AvgMaterialCost);
}
