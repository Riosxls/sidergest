using System.Globalization;
using System.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.DbfImport;

public sealed class PurchasingImport : IImportStep
{
    public static readonly (string Prefix, string Preferred, string Name)[] Sources =
    [
        ("E37", "SE370", "supplier materials"),
        ("G06", "SG060", "quotation items"),
        ("G07", "SG070", "quotation bids"),
        ("G19", "SG190", "purchase orders"),
        ("G12", "SG120", "order lines"),
        ("G09", "SG090", "delivery schedule"),
        ("G20", "SG200", "cancelled orders"),
        ("G02", "SG020", "requisitions")
    ];

    private EbtDbContext db = null!;
    private ImportReport report = null!;
    private Dictionary<string, int> suppliers = new();
    private Dictionary<string, Material> materials = new();
    private readonly Dictionary<(int Quotation, int Item), QuotationItem> items = new();
    private readonly Dictionary<int, PurchaseOrder> orders = new();
    private readonly HashSet<int> lockedOrders = new();

    public async Task RunAsync(EbtDbContext context, ImportOptions options, Encoding encoding, ImportReport importReport, CancellationToken ct)
    {
        db = context;
        report = importReport;
        var files = Discover(options.Directory);
        suppliers = await db.Suppliers.Where(s => s.LegacyCode != null).ToDictionaryAsync(s => s.LegacyCode!, s => s.Id, ct);
        materials = await db.Materials.AsNoTracking().ToDictionaryAsync(m => m.Code, ct);

        var counters = new Dictionary<string, int>();
        if (files.Control is { } control) counters = await ImportSettings(LegacyDbf.Read(control, encoding).FirstOrDefault(), Path.GetFileName(control), ct);
        else report.Warnings.Add("No SGCONTRO.DBF found; purchasing settings and counters left as they are.");

        List<LegacyRow> Rows(string prefix)
        {
            var name = Sources.First(s => s.Prefix == prefix).Name;
            if (!files.Tables.TryGetValue(prefix, out var path))
            {
                report.Warnings.Add($"No DBF found for {name} ({prefix}*); skipped.");
                return [];
            }
            report.For(name).File = Path.GetFileName(path);
            return LegacyDbf.Read(path, encoding).ToList();
        }

        var g06 = Rows("G06");
        await ImportSupplierMaterials(Rows("E37"), ct);
        await ImportQuotations(g06, Rows("G07"), ct);
        await ImportOrders(Rows("G19"), Rows("G12"), ct);
        ApplySchedule(Rows("G09"), g06);
        ApplyCancellations(Rows("G20"));
        foreach (var order in orders.Values.Where(o => !lockedOrders.Contains(o.Id))) order.Status = OrderStatus(order);
        await db.SaveChangesAsync(ct);
        await ImportRequisitions(Rows("G02"), ct);
        await db.SaveChangesAsync(ct);

        if (!options.DryRun)
        {
            await Advance(EbtDbContext.RequisitionNumbers, "purchase_requisitions", counters.GetValueOrDefault("GPKREQUIS"), ct);
            await Advance(EbtDbContext.QuotationNumbers, "quotations", counters.GetValueOrDefault("GNRCOTACAO"), ct);
            await Advance(EbtDbContext.PurchaseOrderNumbers, "purchase_orders", counters.GetValueOrDefault("GNRPEDIDO"), ct);
        }
    }

    private (Dictionary<string, string> Tables, string? Control) Discover(string dir)
    {
        var found = new Dictionary<string, List<string>>();
        string? control = null;
        foreach (var path in Directory.EnumerateFiles(dir, "*", SearchOption.TopDirectoryOnly).Where(p => p.EndsWith(".dbf", StringComparison.OrdinalIgnoreCase)))
        {
            LegacyTable? table;
            try { table = LegacyDbf.Describe(path); }
            catch (Exception) { continue; }
            if (table is null)
            {
                if (Path.GetFileNameWithoutExtension(path).Equals("SGCONTRO", StringComparison.OrdinalIgnoreCase)) control = path;
                continue;
            }
            if (!found.TryGetValue(table.Prefix, out var list)) found[table.Prefix] = list = new();
            list.Add(path);
        }
        var result = new Dictionary<string, string>();
        foreach (var (prefix, preferred, name) in Sources)
        {
            if (!found.TryGetValue(prefix, out var candidates)) continue;
            var pick = candidates.FirstOrDefault(p => Path.GetFileNameWithoutExtension(p).Equals(preferred, StringComparison.OrdinalIgnoreCase));
            if (pick is null && candidates.Count > 1)
            {
                report.Warnings.Add($"Several files look like {name} ({string.Join(", ", candidates.Select(Path.GetFileName))}); skipped. Remove the extra copies.");
                continue;
            }
            result[prefix] = pick ?? candidates[0];
        }
        return (result, control);
    }

    private async Task<Dictionary<string, int>> ImportSettings(LegacyRow? row, string file, CancellationToken ct)
    {
        var counters = new Dictionary<string, int>();
        if (row is null) return counters;
        report.For("purchasing settings").File = file;
        var settings = await db.PurchasingSettings.FirstOrDefaultAsync(ct);
        var inserted = settings is null;
        settings ??= db.PurchasingSettings.Add(new PurchasingSettings { Id = 1 }).Entity;
        if (row.Dec("TOLRECEBIM") is >= 0 and <= 100 and var tol) settings.ReceivingTolerancePercent = tol;
        if (row.Str("ANTECIPAMP") is not null) settings.AllowEarlyReceipt = row.Flag("ANTECIPAMP");
        await db.SaveChangesAsync(ct);
        Count("purchasing settings", inserted);
        foreach (var f in new[] { "GPKREQUIS", "GNRCOTACAO", "GNRPEDIDO" })
            if (row.Int(f) is > 0 and var v) counters[f] = v;
        return counters;
    }

    private async Task ImportSupplierMaterials(List<LegacyRow> rows, CancellationToken ct)
    {
        const string table = "supplier materials";
        var existing = await db.SupplierMaterials.ToDictionaryAsync(s => (s.SupplierId, s.MaterialId), ct);
        foreach (var r in rows)
        {
            if (Supplier(r.Str("E37CDFORNE"), table) is not { } sid || Material(r.Str("E37CDMATER"), table, required: true) is not { } m) continue;
            var inserted = !existing.TryGetValue((sid, m.Id), out var sm);
            if (inserted) db.SupplierMaterials.Add(existing[(sid, m.Id)] = sm = new SupplierMaterial { SupplierId = sid, MaterialId = m.Id });
            var date = r.Date("E37DATA");
            if (sm!.LastPurchaseDate is null || date is null || date >= sm.LastPurchaseDate)
            {
                sm.LastUnitPrice = r.Dec("E37VLUNIT") is > 0 and var p ? p : sm.LastUnitPrice;
                sm.LastPurchaseDate = date ?? sm.LastPurchaseDate;
            }
            sm.Qualification = r.Str("E37QUALIF")?.ToUpperInvariant() ?? sm.Qualification;
            sm.QualifiedAt = r.Date("E37DTQUALI") ?? sm.QualifiedAt;
            Count(table, inserted);
        }
        await db.SaveChangesAsync(ct);
    }

    private async Task ImportQuotations(List<LegacyRow> g06, List<LegacyRow> g07, CancellationToken ct)
    {
        var existing = await db.Quotations.Include(q => q.Items).ThenInclude(i => i.Bids).AsSplitQuery().ToDictionaryAsync(q => q.Number, ct);
        var quotations = new Dictionary<int, Quotation>();
        foreach (var r in g06)
        {
            const string table = "quotation items";
            if (Number(r.Str("G06NRCOTAC")) is not { } nr) { Skip(table, "item without quotation number"); continue; }
            if (Number(r.Str("G06ITEM")) is not { } itemNo) { Skip(table, $"quotation {nr}: item without number"); continue; }
            if (r.Dec("G06QTD") is not { } qty || qty <= 0) { Skip(table, $"quotation {nr} item {itemNo}: quantity is zero"); continue; }
            if (!quotations.TryGetValue(nr, out var q))
            {
                var isNew = !existing.TryGetValue(nr, out q);
                q ??= db.Quotations.Add(new Quotation { Number = nr }).Entity;
                q.CreatedAt = Timestamp(r.Date("G06DTCAD")) ?? (isNew ? DateTimeOffset.UtcNow : q.CreatedAt);
                q.CreatedBy = r.Str("G06USUARIO") ?? q.CreatedBy;
                quotations[nr] = q;
                Count("quotations", isNew);
            }
            var m = Material(r.Str("G06CDMATER"), table, required: false);
            var item = q.Items.FirstOrDefault(i => i.Item == itemNo);
            var inserted = item is null;
            if (inserted) q.Items.Add(item = new QuotationItem { Item = itemNo, Description = "", Unit = "" });
            item!.MaterialId = m?.Id;
            item.Description = Text(r.Str("G06DSMATER") ?? m?.Description ?? r.Str("G06CDMATER") ?? $"Item {itemNo}", 120);
            item.Unit = Unit(r.Str("G06UNIDADE") ?? m?.PurchaseUnit);
            item.Quantity = qty;
            items[(nr, itemNo)] = item;
            Count(table, inserted);
        }

        foreach (var r in g07)
        {
            const string table = "quotation bids";
            if (Number(r.Str("G07NRCOTAC")) is not { } nr || Number(r.Str("G07ITEM")) is not { } itemNo || !items.TryGetValue((nr, itemNo), out var item))
            {
                Skip(table, $"bid for unknown quotation item {r.Str("G07NRCOTAC")}/{r.Str("G07ITEM")}");
                continue;
            }
            if (Supplier(r.Str("G07CDFORN"), table) is not { } sid) continue;
            var bid = item.Bids.FirstOrDefault(b => b.SupplierId == sid);
            var inserted = bid is null;
            if (inserted) item.Bids.Add(bid = new QuotationBid { SupplierId = sid });
            bid!.UnitPrice = r.Dec("G07VLCOMPR") is > 0 and var p ? p : null;
            bid.DiscountPercent = Pct(r.Dec("G07DESCONT"));
            bid.IcmsPercent = Pct(r.Dec("G07ICMS"));
            bid.IpiPercent = Pct(r.Dec("G07IPI"));
            bid.LeadTimeDays = r.Int("G07PZENTR") is >= 0 and var lead ? lead : null;
            bid.PaymentTerms = r.Str("G07DDL") is { } ddl ? Text(ddl, 30) : null;
            bid.RespondedAt = bid.UnitPrice is null ? null : Timestamp(r.Date("G07DTCOTAC")) ?? bid.RespondedAt;
            bid.Status = r.Str("G07PENDENC")?.ToUpperInvariant() switch { "A" => BidStatus.Approved, "R" => BidStatus.Rejected, _ => BidStatus.Pending };
            if (bid.Status == BidStatus.Approved && bid.UnitPrice is null) bid.Status = BidStatus.Pending;
            Count(table, inserted);
        }

        foreach (var q in quotations.Values)
            q.Status = q.Items.Count > 0 && q.Items.All(i => i.Bids.Count > 0 && i.Bids.All(b => b.Status != BidStatus.Pending)) ? QuotationStatus.Closed : QuotationStatus.Open;
        await db.SaveChangesAsync(ct);
    }

    private async Task ImportOrders(List<LegacyRow> g19, List<LegacyRow> g12, CancellationToken ct)
    {
        var existing = await db.PurchaseOrders.Include(o => o.Lines).ToDictionaryAsync(o => o.Number, ct);
        var received = (await db.GoodsReceiptLines.Select(l => l.PurchaseOrderLine!.PurchaseOrderId).Distinct().ToListAsync(ct)).ToHashSet();
        var usedBids = (await db.PurchaseOrderLines.Where(l => l.QuotationBidId != null).Select(l => new { l.Id, Bid = l.QuotationBidId!.Value }).ToListAsync(ct))
            .ToDictionary(x => x.Bid, x => x.Id);

        PurchaseOrder? Header(int nr, string? supplierCode, LegacyRow r, bool fromHeader)
        {
            if (orders.TryGetValue(nr, out var o)) return o;
            if (Supplier(supplierCode, "purchase orders") is not { } sid) return null;
            var inserted = !existing.TryGetValue(nr, out o);
            if (!inserted && received.Contains(o!.Id))
            {
                lockedOrders.Add(o.Id);
                report.Warnings.Add($"purchase orders: order {nr} already has receipts in the new system; left unchanged.");
                orders[nr] = o;
                return o;
            }
            o ??= db.PurchaseOrders.Add(new PurchaseOrder { Number = nr }).Entity;
            o.SupplierId = sid;
            o.IssuedAt = Timestamp(r.Date(fromHeader ? "G19DTCADAS" : "G12DTPEDID")) ?? (inserted ? DateTimeOffset.UtcNow : o.IssuedAt);
            if (fromHeader)
            {
                o.PaymentTerms = r.Str("G19DDL") is { } ddl ? Text(ddl, 30) : null;
                o.Notes = r.Str("G19TEXTO");
            }
            o.IssuedBy ??= r.Str("G12EMISSOR");
            orders[nr] = o;
            Count("purchase orders", inserted);
            return o;
        }

        foreach (var r in g19)
        {
            if (Number(r.Str("G19NRPEDID")) is not { } nr) { Skip("purchase orders", "order without number"); continue; }
            Header(nr, r.Str("G19IDFORNE"), r, fromHeader: true);
        }

        var lineNumbers = new Dictionary<int, int>();
        var claimed = new HashSet<int>();
        foreach (var r in g12)
        {
            const string table = "order lines";
            if (Number(r.Str("G12NRPEDID")) is not { } nr) { Skip(table, "line without order number"); continue; }
            if (Header(nr, r.Str("G12CDFORN"), r, fromHeader: false) is not { } order) continue;
            var lineNo = lineNumbers[nr] = lineNumbers.GetValueOrDefault(nr) + 1;
            if (lockedOrders.Contains(order.Id)) continue;
            if (r.Dec("G12QTD") is not { } qty || qty <= 0) { Skip(table, $"order {nr} line {lineNo}: quantity is zero"); continue; }
            var code = r.Str("G12CDMATER");
            var m = Material(code, table, required: false);
            var quotationNr = Number(r.Str("G12NRCOTAC"));
            var qItem = quotationNr is { } qn ? items.Where(x => x.Key.Quotation == qn && Same(x.Value, m, code)).Select(x => x.Value).FirstOrDefault() : null;
            var line = order.Lines.FirstOrDefault(l => l.LineNumber == lineNo);
            var inserted = line is null;
            if (inserted) order.Lines.Add(line = new PurchaseOrderLine { LineNumber = lineNo, Description = "", Unit = "" });
            line!.MaterialId = m?.Id;
            line.Description = Text(m?.Description ?? qItem?.Description ?? code ?? $"Linha {lineNo}", 120);
            line.Unit = Unit(r.Str("G12UNIDADE") ?? qItem?.Unit ?? m?.PurchaseUnit);
            line.Quantity = qty;
            line.UnitPrice = r.Dec("G12PRUNIT") is >= 0 and var p ? p : 0m;
            line.DiscountPercent = Pct(r.Dec("G12DESC"));
            line.IcmsPercent = Pct(r.Dec("G12ICMS"));
            line.IpiPercent = Pct(r.Dec("G12IPI"));
            line.DueDate = r.Date("G12DTPEDID") ?? DateOnly.FromDateTime(order.IssuedAt.UtcDateTime);
            line.Closed = r.Flag("G12ENCERRA");
            var bid = qItem?.Bids.FirstOrDefault(b => b.SupplierId == order.SupplierId && b.Status == BidStatus.Approved);
            if (bid is not null && (!usedBids.TryGetValue(bid.Id, out var owner) || owner == line.Id && line.Id != 0) && claimed.Add(bid.Id))
                line.QuotationBidId = bid.Id;
            Count(table, inserted);
        }
        await db.SaveChangesAsync(ct);
    }

    private void ApplySchedule(List<LegacyRow> g09, List<LegacyRow> g06)
    {
        const string table = "delivery schedule";
        var codes = g06.Where(r => Number(r.Str("G06NRCOTAC")) is not null && Number(r.Str("G06ITEM")) is not null)
            .GroupBy(r => (Number(r.Str("G06NRCOTAC"))!.Value, Number(r.Str("G06ITEM"))!.Value))
            .ToDictionary(g => g.Key, g => g.First().Str("G06CDMATER") ?? g.First().Str("G06DSMATER"));
        var touched = new HashSet<PurchaseOrderLine>();
        foreach (var r in g09)
        {
            if (Number(r.Str("G09NRPEDID")) is not { } nr || !orders.TryGetValue(nr, out var order)) { Skip(table, $"schedule for unknown order {r.Str("G09NRPEDID")}"); continue; }
            if (lockedOrders.Contains(order.Id)) continue;
            var key = (Number(r.Str("G09NRCOTAC")) ?? -1, Number(r.Str("G09ITEM")) ?? -1);
            var code = codes.GetValueOrDefault(key);
            var line = order.Lines.FirstOrDefault(l => code is not null && (materials.TryGetValue(code, out var m) ? l.MaterialId == m.Id : l.Description.Equals(code, StringComparison.OrdinalIgnoreCase)))
                       ?? (order.Lines.Count == 1 ? order.Lines[0] : null);
            if (line is null) { Skip(table, $"order {nr}: schedule {key.Item1}/{key.Item2} does not match a line"); continue; }
            if (touched.Add(line))
            {
                line.ReceivedQuantity = 0;
                if (r.Date("G09DTENTR") is { } first) line.DueDate = first;
            }
            if (r.Date("G09DTENTR") is { } due && due < line.DueDate) line.DueDate = due;
            line.ReceivedQuantity += r.Dec("G09QTDIGIT") is > 0 and var q ? q : 0m;
            Count(table, false);
        }
    }

    private void ApplyCancellations(List<LegacyRow> g20)
    {
        foreach (var r in g20)
        {
            if (Number(r.Str("G20NRPEDID")) is not { } nr || !orders.TryGetValue(nr, out var order)) { Skip("cancelled orders", $"cancellation for unknown order {r.Str("G20NRPEDID")}"); continue; }
            if (lockedOrders.Contains(order.Id)) continue;
            order.Status = PurchaseOrderStatus.Cancelled;
            order.CloseReason = r.Str("G20MOTIVO") ?? "Cancelado no sistema antigo";
            order.ClosedBy = r.Str("G20USUARIO");
            order.ClosedAt = Timestamp(r.Date("G20DATACAN"));
            foreach (var l in order.Lines)
            {
                l.Closed = true;
                l.QuotationBidId = null;
            }
            lockedOrders.Add(order.Id);
            Count("cancelled orders", false);
        }
    }

    private static PurchaseOrderStatus OrderStatus(PurchaseOrder o)
    {
        if (o.Lines.Count > 0 && o.Lines.All(l => l.ReceivedQuantity >= l.Quantity)) return PurchaseOrderStatus.Received;
        if (o.Lines.Count > 0 && o.Lines.All(l => l.Closed || l.ReceivedQuantity >= l.Quantity))
            return o.Lines.Any(l => l.ReceivedQuantity > 0) ? PurchaseOrderStatus.Closed : PurchaseOrderStatus.Cancelled;
        return o.Lines.Any(l => l.ReceivedQuantity > 0) ? PurchaseOrderStatus.PartiallyReceived : PurchaseOrderStatus.Open;
    }

    private async Task ImportRequisitions(List<LegacyRow> rows, CancellationToken ct)
    {
        const string table = "requisitions";
        var existing = await db.PurchaseRequisitions.ToDictionaryAsync(r => r.Number, ct);
        var quotationIds = await db.Quotations.ToDictionaryAsync(q => q.Number, q => q.Id, ct);
        var itemIds = await db.QuotationItems.Select(i => new { i.Id, i.QuotationId, i.Item }).ToDictionaryAsync(i => (i.QuotationId, i.Item), i => i.Id, ct);
        var lines = await db.PurchaseOrderLines.Select(l => new { l.Id, l.PurchaseOrder!.Number, l.MaterialId, l.Description }).ToListAsync(ct);
        foreach (var r in rows)
        {
            if (Number(r.Str("G02PK")) is not { } nr) { Skip(table, "requisition without number (G02PK)"); continue; }
            if (r.Dec("G02QTNECES") is not { } qty || qty <= 0) { Skip(table, $"requisition {nr}: quantity is zero"); continue; }
            var code = r.Str("G02CDMATER");
            var m = Material(code, table, required: false);
            var inserted = !existing.TryGetValue(nr, out var req);
            if (inserted) db.PurchaseRequisitions.Add(existing[nr] = req = new PurchaseRequisition { Number = nr, Description = "", Unit = "" });
            req!.MaterialId = m?.Id;
            req.Description = Text(r.Str("G02DSMATER") ?? m?.Description ?? code ?? $"Requisição {nr}", 120);
            req.Unit = Unit(r.Str("G02UNIDADE") ?? m?.PurchaseUnit);
            req.Quantity = qty;
            req.ApprovedQuantity = r.Dec("G02QTAPROV") is > 0 and var aq ? aq : null;
            req.Department = r.Str("G02CDDEPTO") is { } d ? Text(d, 10) : null;
            req.RequestedAt = Timestamp(r.Date("G02DTMOVIM")) ?? (inserted ? DateTimeOffset.UtcNow : req.RequestedAt);
            req.NeededBy = r.Date("G02DTENTR");
            req.RequestedBy = r.Str("G02USUARIO");
            req.DecidedBy = r.Str("G02RESPONS");
            req.Notes = r.Str("G02DSCOMPR");
            var status = r.Int("G02STATUS");
            if (status is >= 0 and <= 8) req.Status = (RequisitionStatus)status;
            else
            {
                req.Status = RequisitionStatus.PendingApproval;
                report.Warnings.Add($"{table}: requisition {nr} has unknown status '{r.Str("G02STATUS")}'; set to pending approval.");
            }
            req.QuotationItemId = Number(r.Str("G02NRCOTAC")) is { } qn && quotationIds.TryGetValue(qn, out var qid) && Number(r.Str("G02ITEM")) is { } it && itemIds.TryGetValue((qid, it), out var iid) ? iid : null;
            req.PurchaseOrderLineId = Number(r.Str("G02NRPEDID")) is { } pn
                ? lines.FirstOrDefault(l => l.Number == pn && (m is not null ? l.MaterialId == m.Id : l.Description.Equals(req.Description, StringComparison.OrdinalIgnoreCase)))?.Id
                : null;
            if (req.Status >= RequisitionStatus.OrderIssued && req.PurchaseOrderLineId is null && r.Str("G02NRPEDID") is { } missing)
                report.Warnings.Add($"{table}: requisition {nr} refers to order {missing}, which has no matching line.");
            Count(table, inserted);
        }
    }

    private async Task Advance(string sequence, string table, int counter, CancellationToken ct)
    {
        var max = await db.Database.SqlQueryRaw<int>($"SELECT COALESCE(MAX(number), 0) AS \"Value\" FROM {table}").SingleAsync(ct);
        var last = Math.Max(max, counter);
        if (last > 0) await db.Database.ExecuteSqlRawAsync($"SELECT setval('{sequence}', GREATEST({last}, (SELECT last_value FROM {sequence})))", ct);
    }

    private static bool Same(QuotationItem item, Material? m, string? code) =>
        m is not null ? item.MaterialId == m.Id : code is not null && item.Description.Equals(code, StringComparison.OrdinalIgnoreCase);

    private int? Supplier(string? code, string table)
    {
        if (code is null) { Skip(table, "row without supplier"); return null; }
        if (suppliers.TryGetValue(code, out var id)) return id;
        Skip(table, $"unknown supplier {code}");
        return null;
    }

    private Material? Material(string? code, string table, bool required)
    {
        if (code is null)
        {
            if (required) Skip(table, "row without material");
            return null;
        }
        if (materials.TryGetValue(code, out var m)) return m;
        if (required) Skip(table, $"unknown material {code}");
        else report.Warnings.Add($"{table}: material {code} not found; kept as description only.");
        return null;
    }

    private static int? Number(string? s) => s is not null && int.TryParse(new string(s.Where(char.IsDigit).ToArray()), NumberStyles.None, CultureInfo.InvariantCulture, out var n) ? n : null;
    private static decimal Pct(decimal? v) => v is > 0 and < 100 ? v.Value : 0m;
    private static string Unit(string? u) => Text((u ?? "UN").ToUpperInvariant(), 3);
    private static string Text(string s, int max) => s.Length <= max ? s : s[..max];
    private static DateTimeOffset? Timestamp(DateOnly? d) => d is { } x ? new DateTimeOffset(x.ToDateTime(new TimeOnly(12, 0)), TimeSpan.Zero) : null;

    private void Skip(string table, string reason)
    {
        report.For(table).Skipped++;
        report.Warnings.Add($"{table}: {reason}");
    }

    private void Count(string table, bool inserted)
    {
        if (inserted) report.For(table).Inserted++;
        else report.For(table).Updated++;
    }
}

public static class LegacyRowDates
{
    private static readonly string[] Formats = ["yyyyMMdd", "dd/MM/yyyy", "dd/MM/yy", "MM/dd/yyyy HH:mm:ss", "yyyy-MM-dd"];

    public static DateOnly? Date(this LegacyRow row, string field)
    {
        var s = row.Str(field);
        if (s is null) return null;
        if (DateTime.TryParseExact(s, Formats, CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) && d.Year > 1900) return DateOnly.FromDateTime(d);
        return DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, out d) && d.Year > 1900 ? DateOnly.FromDateTime(d) : null;
    }
}
