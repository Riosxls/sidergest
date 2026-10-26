using System.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.DbfImport;

public sealed class ImportOptions
{
    public required string Directory { get; init; }
    public int CodePage { get; init; } = 850;
    public string DefaultNcm { get; init; } = "73063010";
    public bool DryRun { get; init; }
    public IReadOnlyList<IImportStep> Steps { get; init; } = [];
}

public sealed class TableReport
{
    public string? File { get; set; }
    public int Inserted { get; set; }
    public int Updated { get; set; }
    public int Skipped { get; set; }
}

public sealed class ImportReport
{
    public Dictionary<string, TableReport> Tables { get; } = new();
    public List<string> Warnings { get; } = new();
    public TableReport For(string name) => Tables.TryGetValue(name, out var r) ? r : Tables[name] = new TableReport();
}

public sealed class Importer(EbtDbContext db, ImportOptions options)
{
    public static readonly (string Prefix, string Preferred, string Name)[] Sources =
    [
        ("E09", "SE090", "material classes"),
        ("E03", "SE030", "material groups"),
        ("E04", "SE040", "material subgroups"),
        ("E10", "SE100", "materials"),
        ("E07", "SE070", "work centers"),
        ("P07", "", "machines"),
        ("G32", "", "tools"),
        ("X03", "XY030", "standard operations"),
        ("F01", "NF010", "customers"),
        ("F02", "NF020", "customer addresses"),
        ("E06", "SE060", "suppliers"),
        ("E08", "SE080", "supplier addresses"),
        ("F06", "NF060", "products"),
        ("F33", "NF330", "product customers"),
        ("X05", "XY050", "routing"),
        ("X04", "XY040", "bill of materials")
    ];

    private readonly ImportReport report = new();
    private Encoding encoding = Encoding.Latin1;

    public async Task<ImportReport> RunAsync(CancellationToken ct = default)
    {
        encoding = LegacyDbf.GetEncoding(options.CodePage);
        var files = Discover();
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        foreach (var (prefix, _, name) in Sources)
        {
            if (!files.TryGetValue(prefix, out var path))
            {
                report.Warnings.Add($"No DBF found for {name} ({prefix}*); skipped.");
                continue;
            }
            report.For(name).File = Path.GetFileName(path);
            var rows = LegacyDbf.Read(path, encoding).ToList();
            await (prefix switch
            {
                "E09" => ImportCodeName(rows, name, "E09CDTPMAT", "E09DSTPMAT", db.MaterialClasses, (c, n) => new MaterialClass { Code = c, Name = n }, (e, n) => e.Name = n, e => e.Code, ct),
                "E03" => ImportCodeName(rows, name, "E03CDGPMAT", "E03DSGPMAT", db.MaterialGroups, (c, n) => new MaterialGroup { Code = c, Name = n }, (e, n) => e.Name = n, e => e.Code, ct),
                "E04" => ImportCodeName(rows, name, "E04CDSGMAT", "E04DSSGMAT", db.MaterialSubgroups, (c, n) => new MaterialSubgroup { Code = c, Name = n }, (e, n) => e.Name = n, e => e.Code, ct),
                "E10" => ImportMaterials(rows, name, ct),
                "E07" => ImportCodeName(rows, name, "E07CDCCUST", "E07DSCCUST", db.WorkCenters, (c, n) => new WorkCenter { Code = c, Name = n, CostCenter = c }, (e, n) => e.Name = n, e => e.Code, ct),
                "P07" => ImportMachines(rows, name, ct),
                "G32" => ImportTools(rows, name, ct),
                "X03" => ImportCodeName(rows, name, "X03CDOPER", "X03DSOPER", db.StandardOperations, (c, n) => new StandardOperation { Code = c, Name = n }, (e, n) => e.Name = n, e => e.Code, ct),
                "F01" => ImportCustomers(rows, name, ct),
                "F02" => ImportCustomerAddresses(rows, name, ct),
                "E06" => ImportSuppliers(rows, name, ct),
                "E08" => ImportSupplierAddresses(rows, name, ct),
                "F06" => ImportProducts(rows, name, ct),
                "F33" => ImportProductCustomers(rows, name, ct),
                "X05" => ImportRouting(rows, name, ct),
                "X04" => ImportBom(rows, name, ct),
                _ => Task.CompletedTask
            });
            await db.SaveChangesAsync(ct);
            db.ChangeTracker.Clear();
        }

        foreach (var step in options.Steps)
        {
            await step.RunAsync(db, options, encoding, report, ct);
            db.ChangeTracker.Clear();
        }

        if (options.DryRun) await tx.RollbackAsync(ct);
        else await tx.CommitAsync(ct);
        return report;
    }

    private Dictionary<string, string> Discover()
    {
        var found = new Dictionary<string, List<string>>();
        foreach (var path in System.IO.Directory.EnumerateFiles(options.Directory, "*", SearchOption.TopDirectoryOnly)
                     .Where(p => p.EndsWith(".dbf", StringComparison.OrdinalIgnoreCase)))
        {
            LegacyTable? table;
            try { table = LegacyDbf.Describe(path); }
            catch (Exception ex) { report.Warnings.Add($"Could not read {Path.GetFileName(path)}: {ex.Message}"); continue; }
            if (table is null) continue;
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
        return result;
    }

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

    private async Task ImportCodeName<T>(List<LegacyRow> rows, string table, string codeField, string nameField, DbSet<T> set,
        Func<string, string, T> create, Action<T, string> update, Func<T, string> key, CancellationToken ct) where T : class
    {
        var existing = (await set.ToListAsync(ct)).ToDictionary(key);
        foreach (var row in rows)
        {
            var code = row.Str(codeField);
            if (code is null) { Skip(table, "row without code"); continue; }
            var name = row.Str(nameField) ?? code;
            if (existing.TryGetValue(code, out var e)) { update(e, name); Count(table, false); }
            else { existing[code] = e = create(code, name); set.Add(e); Count(table, true); }
        }
    }

    private async Task ImportMaterials(List<LegacyRow> rows, string table, CancellationToken ct)
    {
        var classes = await db.MaterialClasses.ToDictionaryAsync(x => x.Code, x => x.Id, ct);
        var groups = await db.MaterialGroups.ToDictionaryAsync(x => x.Code, x => x.Id, ct);
        var subgroups = await db.MaterialSubgroups.ToDictionaryAsync(x => x.Code, x => x.Id, ct);
        var existing = await db.Materials.ToDictionaryAsync(x => x.Code, ct);
        foreach (var r in rows)
        {
            var code = r.Str("E10CDMATER");
            if (code is null) { Skip(table, "material without code"); continue; }
            var inserted = !existing.TryGetValue(code, out var m);
            m ??= new Material { Code = code, Description = "", StockUnit = "", PurchaseUnit = "" };
            m.Description = r.Str("E10DSMATER") ?? code;
            m.ClassId = r.Str("E10CDTPMAT") is { } c && classes.TryGetValue(c, out var cid) ? cid : null;
            m.GroupId = r.Str("E10CDGPMAT") is { } g && groups.TryGetValue(g, out var gid) ? gid : null;
            m.SubgroupId = r.Str("E10CDSGMAT") is { } s && subgroups.TryGetValue(s, out var sid) ? sid : null;
            m.StockUnit = (r.Str("E10UNIDADE") ?? "UN").ToUpperInvariant();
            m.PurchaseUnit = (r.Str("E10UNCOMPR") ?? m.StockUnit).ToUpperInvariant();
            m.PurchaseFactor = r.Dec("E10FATOR") is > 0 and var f ? f : 1m;
            m.ThicknessMm = r.Dec("E10ESPEC") is > 0 and var t ? t : null;
            m.WidthMm = r.Dec("E10LARG") is > 0 and var w ? w : null;
            m.Ncm = r.Digits("E10NCM") is { Length: 8 } ncm ? ncm : null;
            m.LeadTimeDays = r.Int("E10LEADTIM");
            m.PurchaseLot = r.Dec("E10LOTECOM");
            m.MinStock = r.Dec("E10QTMINIM");
            m.MaxStock = r.Dec("E10QTMAXIM");
            m.RequiresInspection = r.Flag("E10INSPEC");
            m.GeneratesPurchaseOrder = r.Flag("E10GERACOM", true);
            m.ExternalProcessing = r.Flag("E10BENEF");
            if (inserted) { db.Materials.Add(m); existing[code] = m; }
            Count(table, inserted);
        }
    }

    private async Task ImportMachines(List<LegacyRow> rows, string table, CancellationToken ct)
    {
        var centers = await db.WorkCenters.ToDictionaryAsync(x => x.Code, x => x.Id, ct);
        var existing = await db.Machines.ToDictionaryAsync(x => x.Code, ct);
        foreach (var r in rows)
        {
            var code = r.Str("P07CDMAQ");
            if (code is null) { Skip(table, "machine without code"); continue; }
            var inserted = !existing.TryGetValue(code, out var m);
            m ??= new Machine { Code = code, Name = "" };
            m.Name = r.Str("P07DSMAQ") ?? code;
            m.Family = r.Str("P07CDGPMAQ");
            m.WorkCenterId = r.Str("P07CDCCUST") is { } cc && centers.TryGetValue(cc, out var id) ? id : null;
            if (inserted) { db.Machines.Add(m); existing[code] = m; }
            Count(table, inserted);
        }
    }

    private async Task ImportTools(List<LegacyRow> rows, string table, CancellationToken ct)
    {
        var existing = await db.Tools.ToDictionaryAsync(x => x.Code, ct);
        foreach (var r in rows)
        {
            var code = r.Str("G32CDFER");
            if (code is null) { Skip(table, "tool without code"); continue; }
            var inserted = !existing.TryGetValue(code, out var t);
            t ??= new Tool { Code = code, Name = "" };
            t.Name = r.Str("G32DSFER") ?? code;
            t.WarningLimit = r.Int("G32LIM_AVI");
            t.InspectionLimit = r.Int("G32LIM_INS");
            if (inserted) { db.Tools.Add(t); existing[code] = t; }
            Count(table, inserted);
        }
    }

    private async Task ImportCustomers(List<LegacyRow> rows, string table, CancellationToken ct)
    {
        var existing = await db.Customers.Where(c => c.LegacyCode != null).ToDictionaryAsync(x => x.LegacyCode!, ct);
        foreach (var r in rows)
        {
            var code = r.Str("F01CDCLIE");
            if (code is null) { Skip(table, "customer without code"); continue; }
            var inserted = !existing.TryGetValue(code, out var c);
            c ??= new Customer { LegacyCode = code, Name = "" };
            c.Name = r.Str("F01NMCLIE") ?? r.Str("F01NMFANT") ?? code;
            c.TradeName = r.Str("F01NMFANT");
            c.ConsumerType = r.Str("F01TPCONSU") == "F" ? ConsumerType.FinalConsumer : ConsumerType.Normal;
            c.Active = r.Str("F01STATUS") != "I";
            if (inserted) { db.Customers.Add(c); existing[code] = c; }
            Count(table, inserted);
        }
    }

    private async Task ImportCustomerAddresses(List<LegacyRow> rows, string table, CancellationToken ct)
    {
        var customers = await db.Customers.Where(c => c.LegacyCode != null).ToDictionaryAsync(x => x.LegacyCode!, x => x.Id, ct);
        var existing = await db.CustomerAddresses.Where(a => a.LegacyCode != null).ToDictionaryAsync(a => (a.CustomerId, a.LegacyCode!), ct);
        foreach (var r in rows)
        {
            var customerCode = r.Str("F02CDCLIE");
            var code = r.Str("F02CDENDER") ?? "1";
            if (customerCode is null || !customers.TryGetValue(customerCode, out var customerId)) { Skip(table, $"address {code} for unknown customer {customerCode}"); continue; }
            var uf = r.Str("F02CDESTAD");
            if (uf is not { Length: 2 }) { Skip(table, $"customer {customerCode} address {code} without valid UF"); continue; }
            var inserted = !existing.TryGetValue((customerId, code), out var a);
            a ??= new CustomerAddress { CustomerId = customerId, LegacyCode = code, Document = "", Uf = "" };
            a.Document = r.Digits("F02CGC") ?? "";
            a.Uf = uf.ToUpperInvariant();
            a.StateRegistration = r.Str("F02IE");
            a.IcmsContributor = r.Str("F02ICMSCON") is { } ic ? ic is "1" or "S" : !string.IsNullOrEmpty(a.StateRegistration);
            a.Street = r.Str("F02ENDER");
            a.Number = r.Str("F02NUMERO");
            a.Complement = r.Str("F02COMPL");
            a.District = r.Str("F02BAIRRO");
            a.City = r.Str("F02CIDADE");
            a.CityIbgeCode = r.Digits("F02IDMUNIC") is { Length: 7 } ibge ? ibge : null;
            a.ZipCode = r.Digits("F02CEP") is { Length: 8 } cep ? cep : null;
            a.DefaultCfop = r.Str("F02CDOPRC");
            a.Buyer = r.Str("F02COMPRAD");
            a.Email = r.Str("F02EMAILCP");
            a.Phone = r.Str("F02TELEF");
            if (a.Document.Length is not (11 or 14)) report.Warnings.Add($"{table}: customer {customerCode} address {code} has no valid CNPJ/CPF");
            if (inserted) { db.CustomerAddresses.Add(a); existing[(customerId, code)] = a; }
            Count(table, inserted);
        }
    }

    private async Task ImportSuppliers(List<LegacyRow> rows, string table, CancellationToken ct)
    {
        var existing = await db.Suppliers.Where(s => s.LegacyCode != null).ToDictionaryAsync(x => x.LegacyCode!, ct);
        foreach (var r in rows)
        {
            var code = r.Str("E06CDFORNE");
            if (code is null) { Skip(table, "supplier without code"); continue; }
            var inserted = !existing.TryGetValue(code, out var s);
            s ??= new Supplier { LegacyCode = code, Name = "" };
            s.Name = r.Str("E06RSFORNE") ?? r.Str("E06NMFANTA") ?? code;
            s.TradeName = r.Str("E06NMFANTA");
            s.GroupCode = r.Str("E06CDGPFOR");
            s.Active = r.Str("E06STATUS") != "I";
            if (inserted) { db.Suppliers.Add(s); existing[code] = s; }
            Count(table, inserted);
        }
    }

    private async Task ImportSupplierAddresses(List<LegacyRow> rows, string table, CancellationToken ct)
    {
        var suppliers = await db.Suppliers.Where(s => s.LegacyCode != null).ToDictionaryAsync(x => x.LegacyCode!, x => x.Id, ct);
        var existing = await db.SupplierAddresses.Where(a => a.LegacyCode != null).ToDictionaryAsync(a => (a.SupplierId, a.LegacyCode!), ct);
        foreach (var r in rows)
        {
            var supplierCode = r.Str("E08CDFORNE");
            var code = r.Str("E08CDENDER") ?? "1";
            if (supplierCode is null || !suppliers.TryGetValue(supplierCode, out var supplierId)) { Skip(table, $"address {code} for unknown supplier {supplierCode}"); continue; }
            var uf = r.Str("E08CDESTAD");
            if (uf is not { Length: 2 }) { Skip(table, $"supplier {supplierCode} address {code} without valid UF"); continue; }
            var inserted = !existing.TryGetValue((supplierId, code), out var a);
            a ??= new SupplierAddress { SupplierId = supplierId, LegacyCode = code, Uf = "" };
            a.Uf = uf.ToUpperInvariant();
            a.Document = r.Digits("E08CGC") is { Length: 11 or 14 } doc ? doc : null;
            a.StateRegistration = r.Str("E08IE");
            a.Street = r.Str("E08ENDER");
            a.Number = r.Str("E08NUMERO");
            a.District = r.Str("E08BAIRRO");
            a.City = r.Str("E08CIDADE");
            a.CityIbgeCode = r.Digits("E08IDMUNIC") is { Length: 7 } ibge ? ibge : null;
            a.ZipCode = r.Digits("E08CEP") is { Length: 8 } cep ? cep : null;
            a.Email = r.Str("E08EMAIL");
            a.Phone = r.Str("E08TELEF");
            if (inserted) { db.SupplierAddresses.Add(a); existing[(supplierId, code)] = a; }
            Count(table, inserted);
        }
    }

    private async Task ImportProducts(List<LegacyRow> rows, string table, CancellationToken ct)
    {
        var existing = await db.Products.ToDictionaryAsync(x => x.Code, ct);
        foreach (var r in rows)
        {
            var code = r.Str("F06CDPECA");
            if (code is null) { Skip(table, "product without code"); continue; }
            var inserted = !existing.TryGetValue(code, out var p);
            p ??= new Product { Code = code, Name = "", Ncm = "", StockUnit = "" };
            p.Name = r.Str("F06NMPECA") ?? code;
            p.Kind = r.Str("F06TPPECA") == "C" ? ProductKind.Component : ProductKind.Part;
            p.Shape = r.Str("F06TPTUBO") switch { "C" => TubeShape.Circular, "R" => TubeShape.Rectangular, _ => null };
            p.DiameterMm = Positive(r.Dec("F06DIAMETR"));
            p.WidthMm = Positive(r.Dec("F06LARGURA"));
            p.HeightMm = Positive(r.Dec("F06ALTURA"));
            p.ThicknessMm = Positive(r.Dec("F06ESPESSU"));
            p.LengthMm = Positive(r.Dec("F06COMPRIM"));
            p.NetWeightKg = Positive(r.Dec("F06PESOLIQ"));
            p.LossPercent = r.Dec("F06PERDA");
            var ncm = r.Digits("F06NCM");
            if (ncm is not { Length: 8 })
            {
                report.Warnings.Add($"{table}: product {code} has no valid NCM; used default {options.DefaultNcm}");
                ncm = options.DefaultNcm;
            }
            p.Ncm = ncm;
            p.StockUnit = (r.Str("F06UNESTOC") ?? "PC").ToUpperInvariant();
            p.PiecesPerPackage = r.Int("F06QTPCEMB") is > 0 and var q ? q : null;
            p.Blocked = r.Flag("F06BLOQUEI");
            p.DrawingRevision = r.Str("F06REVDES");
            p.ProcessRevision = r.Str("F06REVPROC");
            if (inserted) { db.Products.Add(p); existing[code] = p; }
            Count(table, inserted);
        }
    }

    private async Task ImportProductCustomers(List<LegacyRow> rows, string table, CancellationToken ct)
    {
        var products = await db.Products.ToDictionaryAsync(x => x.Code, x => x.Id, ct);
        var customers = await db.Customers.Where(c => c.LegacyCode != null).ToDictionaryAsync(x => x.LegacyCode!, x => x.Id, ct);
        var existing = await db.ProductCustomers.ToDictionaryAsync(x => (x.ProductId, x.CustomerId), ct);
        foreach (var r in rows)
        {
            var productCode = r.Str("F33CDPECA");
            var customerCode = r.Str("F33CDCLIE");
            if (productCode is null || !products.TryGetValue(productCode, out var pid)) { Skip(table, $"link to unknown product {productCode}"); continue; }
            if (customerCode is null || !customers.TryGetValue(customerCode, out var cid)) { Skip(table, $"product {productCode} linked to unknown customer {customerCode}"); continue; }
            var inserted = !existing.TryGetValue((pid, cid), out var link);
            link ??= new ProductCustomer { ProductId = pid, CustomerId = cid };
            link.CustomerDescription = r.Str("F33DSPCCLI");
            link.CustomerPartNumber = r.Str("F33DSPCCLI");
            link.Active = r.Str("F33IDSTATU") is not ("I" or "B");
            if (inserted) { db.ProductCustomers.Add(link); existing[(pid, cid)] = link; }
            Count(table, inserted);
        }
    }

    private async Task ImportRouting(List<LegacyRow> rows, string table, CancellationToken ct)
    {
        var products = await db.Products.ToDictionaryAsync(x => x.Code, x => x.Id, ct);
        var machines = await db.Machines.ToDictionaryAsync(x => x.Code, x => x.Id, ct);
        var centers = await db.WorkCenters.ToDictionaryAsync(x => x.Code, x => x.Id, ct);
        var tools = await db.Tools.ToDictionaryAsync(x => x.Code, x => x.Id, ct);
        var standard = await db.StandardOperations.ToDictionaryAsync(x => x.Code, x => x.Id, ct);
        var existing = await db.RoutingOperations.ToDictionaryAsync(x => (x.ProductId, x.Sequence), ct);
        foreach (var r in rows)
        {
            var productCode = r.Str("X05CDPECA");
            var seq = r.Int("X05NROPER");
            if (productCode is null || !products.TryGetValue(productCode, out var pid)) { Skip(table, $"operation for unknown product {productCode}"); continue; }
            if (seq is not > 0 || seq % 10 != 0) { Skip(table, $"product {productCode} operation {seq} is not a multiple of 10"); continue; }
            var inserted = !existing.TryGetValue((pid, seq.Value), out var op);
            op ??= new RoutingOperation { ProductId = pid, Sequence = seq.Value };
            op.MachineId = Lookup(machines, r.Str("X05CDMAQ"), table, $"product {productCode} op {seq} machine");
            op.WorkCenterId = Lookup(centers, r.Str("X05CDSETOR"), table, $"product {productCode} op {seq} work center");
            op.ToolId = Lookup(tools, r.Str("X05CDFER"), table, $"product {productCode} op {seq} tool");
            op.StandardOperationId = Lookup(standard, r.Str("X05CDOPER"), table, $"product {productCode} op {seq} standard operation");
            op.SetupHours = r.Dec("X05HRPRE");
            op.PiecesPerHour = Positive(r.Dec("X05HRMAQ"));
            op.Operators = r.Dec("X05HRHOM");
            op.Description = r.Str("X05DESC1");
            op.Standard = r.Str("X05DESC2");
            op.Notes = r.Str("X05DESC3");
            if (inserted) { db.RoutingOperations.Add(op); existing[(pid, seq.Value)] = op; }
            Count(table, inserted);
        }
    }

    private async Task ImportBom(List<LegacyRow> rows, string table, CancellationToken ct)
    {
        var products = await db.Products.ToDictionaryAsync(x => x.Code, x => x.Id, ct);
        var materials = await db.Materials.ToDictionaryAsync(x => x.Code, x => x.Id, ct);
        var operations = await db.RoutingOperations.ToDictionaryAsync(x => (x.ProductId, x.Sequence), x => x.Id, ct);
        var touched = new HashSet<int>();
        var pending = new List<BomItem>();
        foreach (var r in rows)
        {
            var productCode = r.Str("X04CDPECA");
            var seq = r.Int("X04NROPER");
            var itemCode = r.Str("X04CDMAT");
            if (productCode is null || !products.TryGetValue(productCode, out var pid)) { Skip(table, $"BOM line for unknown product {productCode}"); continue; }
            if (seq is null || !operations.TryGetValue((pid, seq.Value), out var opId)) { Skip(table, $"product {productCode} BOM line for missing operation {seq}"); continue; }
            var qty = r.Dec("X04QTMAT");
            if (qty is not > 0) { Skip(table, $"product {productCode} op {seq} item {itemCode} without quantity"); continue; }
            int? materialId = null, componentId = null;
            if (itemCode is not null && products.TryGetValue(itemCode, out var compId) && (r.Str("X04TPMATER") is "C" or null || !materials.ContainsKey(itemCode))) componentId = compId;
            else if (itemCode is not null && materials.TryGetValue(itemCode, out var matId)) materialId = matId;
            else { Skip(table, $"product {productCode} op {seq} references unknown item {itemCode}"); continue; }
            if (componentId == pid) { Skip(table, $"product {productCode} lists itself as component"); continue; }
            touched.Add(opId);
            pending.Add(new BomItem
            {
                RoutingOperationId = opId,
                MaterialId = materialId,
                ComponentProductId = componentId,
                Quantity = qty.Value,
                Unit = (r.Str("X04UNID") ?? "UN").ToUpperInvariant(),
                Factor = r.Dec("X04FATOR") is > 0 and var f ? f : 1m
            });
        }
        var replaced = await db.BomItems.Where(b => touched.Contains(b.RoutingOperationId)).ExecuteDeleteAsync(ct);
        db.BomItems.AddRange(pending);
        report.For(table).Inserted += pending.Count;
        if (replaced > 0) report.Warnings.Add($"{table}: replaced {replaced} existing BOM lines on {touched.Count} operations");
    }

    private int? Lookup(Dictionary<string, int> map, string? code, string table, string what)
    {
        if (code is null) return null;
        if (map.TryGetValue(code, out var id)) return id;
        report.Warnings.Add($"{table}: {what} '{code}' not found; left empty");
        return null;
    }

    private static decimal? Positive(decimal? value) => value is > 0 ? value : null;
}
