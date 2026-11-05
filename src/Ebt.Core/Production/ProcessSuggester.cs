using System.Globalization;
using System.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Sales;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Production;

public enum ProcessSource { PreviousOrder, TemplateCustomer, TemplateDims, Rules }

/// <summary>Kind of shop-floor operation, read from the words of its description (or of the resource written on the legacy paper).</summary>
public enum OperationKind { Other, Profile, Draw, StraightenCut, Inspection, Brush, Polish }

public sealed record SuggestedOperation(int Sequence, string Description, string? Tolerance, string? MeasureStart, string? MeasureEnd, int? MachineId, string? MachineCode, string? MachineName);

public sealed record ProcessSuggestion(ProcessSource Source, string? SourceRef, IReadOnlyList<SuggestedOperation> Operations);

/// <summary>The machines of the plant, looked up by name keywords (never by id or code).</summary>
public sealed class MachineIndex
{
    private readonly List<Machine> machines;
    private MachineIndex(List<Machine> machines) => this.machines = machines;

    public static async Task<MachineIndex> LoadAsync(EbtDbContext db, CancellationToken ct) =>
        new(await db.Machines.AsNoTracking().OrderBy(m => m.Id).ToListAsync(ct));

    public static MachineIndex Of(IEnumerable<Machine> machines) => new(machines.OrderBy(m => m.Id).ToList());

    public Machine? For(OperationKind kind)
    {
        Machine? Find(params string[] words) => machines.FirstOrDefault(m => { var n = ProcessSuggester.Fold(m.Name); return words.All(w => n.Contains(w)); });
        return kind switch
        {
            OperationKind.Profile => Find("PERFILAD"),
            OperationKind.Draw => Find("TREFIL"),
            OperationKind.StraightenCut => Find("ENDIREIT", "CORTE") ?? Find("ENDIREIT"),
            OperationKind.Inspection => Find("INSPE"),
            OperationKind.Brush => Find("ESCOV"),
            OperationKind.Polish => Find("POLI"),
            _ => null
        };
    }
}

/// <summary>
/// Suggests the secondary process of a new OF. Tried in order: the last OF of the same customer and product, the legacy process of the same customer and tube,
/// the most common legacy process of the same tube for any customer, and finally the generic rules. The tolerance is decided per customer and product in the legacy data,
/// so a tolerance is never invented outside these sources.
/// </summary>
public sealed class ProcessSuggester(EbtDbContext db)
{
    public const string Dash = "-";
    public const string LegacyInspectionResource = "Visual/Dimensional";

    public static string Fold(string? s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        var sb = new StringBuilder();
        foreach (var c in s.Normalize(NormalizationForm.FormD))
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        return sb.ToString().Normalize(NormalizationForm.FormC).ToUpperInvariant();
    }

    public static OperationKind KindOf(string? text)
    {
        var t = Fold(text);
        if (t.Contains("PERFIL")) return OperationKind.Profile;
        if (t.Contains("TREFIL")) return OperationKind.Draw;
        if (t.Contains("ENDIREIT") || t.Contains("CORT")) return OperationKind.StraightenCut;
        if (t.Contains("INSPE")) return OperationKind.Inspection;
        if (t.Contains("ESCOV")) return OperationKind.Brush;
        if (t.Contains("POLI")) return OperationKind.Polish;
        return OperationKind.Other;
    }

    /// <summary>Legacy swap: the text "Visual/Dimensional" is the resource of the inspection, not its requirement.</summary>
    public static bool IsLegacySwap(string? tolerance) => string.Equals(tolerance?.Trim(), LegacyInspectionResource, StringComparison.OrdinalIgnoreCase);

    /// <summary>Default requirement by operation type; the straightening and cutting one depends on the piece length. Null for types without a rule.</summary>
    public static string? RuleTolerance(OperationKind kind, decimal? lengthMm) => kind switch
    {
        OperationKind.Profile or OperationKind.Draw => "± 0,10",
        OperationKind.StraightenCut => lengthMm is not > 0 ? "± 0,10" : lengthMm >= 2500 ? "+30" : lengthMm >= 500 ? "± 0,05" : "± 0,50",
        OperationKind.Inspection => Dash,
        _ => null
    };

    /// <summary>Operation texts of the generic process: profile from the primary tube, draw to the diameter, straighten and cut to the length, final inspection.</summary>
    public static List<string> RuleDescriptions(Product product, string? primaryTube)
    {
        string Mm(decimal v, string format = "0.00") => v.ToString(format, CultureInfo.GetCultureInfo("pt-BR"));
        var ops = new List<string>();
        decimal? profile = null;
        var m = System.Text.RegularExpressions.Regex.Match(primaryTube ?? "", @"\d+(?:[.,]\d+)?");
        if (m.Success && decimal.TryParse(m.Value.Replace(',', '.'), NumberStyles.Number, CultureInfo.InvariantCulture, out var d)) profile = d;
        ops.Add(profile is { } p ? $"Perfilar {Mm(p)}mm" : "Perfilar");
        if (product.DiameterMm is { } dia and > 0 && (profile is null || dia < profile)) ops.Add($"Trefilar para {Mm(dia)}mm");
        ops.Add(product.LengthMm is { } len and > 0 ? $"Endireitar e Cortar {Mm(len, "0.##")}" : "Endireitar e Cortar");
        ops.Add("Inspeção Final");
        return ops;
    }

    private static SuggestedOperation Make(int index, string description, string? tolerance, string? start, string? end, Machine? machine) =>
        new((index + 1) * 10, description, tolerance, start, end, machine?.Id, machine?.Code, machine?.Name);

    /// <summary>Machine for an operation: the resource text first (template operations), then the words of the description. Types without a machine keyword (outside treatment...) get none.</summary>
    public static Machine? MachineFor(MachineIndex machines, string? description, string? resource = null)
    {
        var kind = KindOf(resource);
        if (kind == OperationKind.Other) kind = KindOf(description);
        return machines.For(kind);
    }

    public static IReadOnlyList<SuggestedOperation> RuleOperations(Product product, string? primaryTube, MachineIndex machines) =>
        RuleDescriptions(product, primaryTube).Select((text, i) =>
        {
            var kind = KindOf(text);
            return Make(i, text, RuleTolerance(kind, product.LengthMm), null, null, machines.For(kind));
        }).ToList();

    /// <param name="excludeOrderId">The order the process is for (when it already exists): its own operations are never the source.</param>
    /// <param name="customerAlias">Second name of the customer (trade name): legacy sheets use either.</param>
    public async Task<ProcessSuggestion> SuggestAsync(Product product, string? primaryTube, string? customerName, CancellationToken ct = default, int? excludeOrderId = null, string? customerAlias = null, MachineIndex? machines = null)
    {
        machines ??= await MachineIndex.LoadAsync(db, ct);
        var keys = new[] { customerName, customerAlias }.Where(n => !string.IsNullOrWhiteSpace(n)).Select(n => PriceHistoryImporter.CustomerKey(n!).ToUpperInvariant()).Where(k => k.Length > 0).Distinct().ToList();

        if (keys.Count > 0 && await FromPreviousOrderAsync(product, keys, excludeOrderId, machines, ct) is { } previous) return previous;
        if (product.DiameterMm is > 0)
        {
            var templates = await TemplatesAsync(product, ct);
            if (keys.Count > 0 && templates.Where(t => t.CustomerKey is not null && keys.Contains(t.CustomerKey)).OrderByDescending(t => t.SourceDate).ThenByDescending(t => t.Id).FirstOrDefault() is { } own)
                return FromTemplate(ProcessSource.TemplateCustomer, own, machines);
            if (templates.Count > 0)
            {
                var winner = templates.GroupBy(Signature).OrderByDescending(g => g.Count()).ThenByDescending(g => g.Max(t => t.SourceDate)).First()
                    .OrderByDescending(t => t.SourceDate).ThenByDescending(t => t.Id).First();
                return FromTemplate(ProcessSource.TemplateDims, winner, machines);
            }
        }
        return new ProcessSuggestion(ProcessSource.Rules, null, RuleOperations(product, primaryTube, machines));
    }

    private static string Signature(ProcessTemplate t) =>
        string.Join('|', t.Operations.OrderBy(o => o.Sequence).Select(o => $"{Fold(o.Description)}~{o.Tolerance?.Trim()}"));

    private async Task<List<ProcessTemplate>> TemplatesAsync(Product product, CancellationToken ct)
    {
        var d = product.DiameterMm!.Value;
        var candidates = await db.ProcessTemplates.AsNoTracking().Include(t => t.Operations)
            .Where(t => t.DiameterMm >= d - 0.01m && t.DiameterMm <= d + 0.01m).ToListAsync(ct);
        // A dimension the product does not have constrains nothing; one it has must be on the template and match.
        return candidates.Where(t =>
            (product.ThicknessMm is not { } th || (t.ThicknessMm is { } tt && Math.Abs(tt - th) <= 0.001m)) &&
            (product.LengthMm is not { } len || (t.LengthMm is { } tl && Math.Abs(tl - len) <= 1m)) &&
            t.Operations.Count > 0).ToList();
    }

    private static ProcessSuggestion FromTemplate(ProcessSource source, ProcessTemplate t, MachineIndex machines) =>
        new(source, t.SourceRef, t.Operations.OrderBy(o => o.Sequence).Select((o, i) => Make(i, o.Description, o.Tolerance, o.MeasureStart, o.MeasureEnd, MachineFor(machines, o.Description, o.Resource))).ToList());

    private async Task<ProcessSuggestion?> FromPreviousOrderAsync(Product product, List<string> keys, int? excludeOrderId, MachineIndex machines, CancellationToken ct)
    {
        var candidates = await db.ProductionOrders.AsNoTracking()
            .Where(o => o.ProductId == product.Id && o.Status != ProductionOrderStatus.Cancelled && o.Id != excludeOrderId
                && o.Operations.Any(op => op.Tolerance != null && op.Tolerance.Trim() != ""))
            .OrderByDescending(o => o.Id).Take(100)
            .Select(o => new
            {
                o.Id, o.Reference,
                Name = o.Customer != null ? o.Customer.Name : null, Trade = o.Customer != null ? o.Customer.TradeName : null,
                SalesName = db.SalesOrderLines.Where(l => l.ProductionOrderId == o.Id).Select(l => l.Order!.Customer!.Name).FirstOrDefault(),
                SalesTrade = db.SalesOrderLines.Where(l => l.ProductionOrderId == o.Id).Select(l => l.Order!.Customer!.TradeName).FirstOrDefault()
            }).ToListAsync(ct);
        var match = candidates.FirstOrDefault(c => new[] { c.Name, c.Trade, c.SalesName, c.SalesTrade }
            .Any(n => !string.IsNullOrWhiteSpace(n) && keys.Contains(PriceHistoryImporter.CustomerKey(n).ToUpperInvariant())));
        if (match is null) return null;
        var ops = await db.ProductionOrderOperations.AsNoTracking().Include(o => o.Machine).Where(o => o.OrderId == match.Id).OrderBy(o => o.Sequence).ToListAsync(ct);
        return new ProcessSuggestion(ProcessSource.PreviousOrder, match.Reference, ops.Select((o, i) =>
        {
            var swap = IsLegacySwap(o.Tolerance);
            var machine = o.Machine ?? MachineFor(machines, o.Description, swap ? LegacyInspectionResource : null);
            return Make(i, o.Description ?? "", swap ? Dash : o.Tolerance, o.MeasureStart, o.MeasureEnd, machine);
        }).ToList());
    }
}
