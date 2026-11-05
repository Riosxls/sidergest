using System.Net;
using System.Reflection;
using System.Text;
using Ebt.Api.Endpoints;
using Ebt.Core.Entities;
using Ebt.Core.Maintenance;
using Ebt.Core.Production;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Tests;

/// <summary>Process of the OF ("PROCESSOS SECUNDÁRIOS"): legacy templates, the suggester (previous OF, template of the customer, template of the tube, rules), machines by name, and the admin completion tool.</summary>
[Collection("api")]
public class ProcessSuggestionTests(ApiFixture api)
{
    private static readonly DateOnly Today = Ebt.Core.Services.Clock.Today();
    private static int dimCounter = 1000;
    private static readonly Random Rng = new();

    private static string Letters(int n) => new(Enumerable.Range(0, n).Select(_ => (char)('A' + Rng.Next(26))).ToArray());
    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();
    /// <summary>A diameter no other test uses, so templates imported here never match a foreign product.</summary>
    private static decimal NewDiameter() => 40m + Interlocked.Increment(ref dimCounter) * 0.05m;
    private static string N(decimal v) => v.ToString(System.Globalization.CultureInfo.InvariantCulture);

    private const string Header = "of;date;customer;diameter;thickness;length;spec;seq;description;tolerance;start;end;resource";

    private static string Row(string of, DateOnly date, string customer, decimal d, decimal t, decimal l, int seq, string description, string? tolerance, string? resource = null, string? start = null, string? end = null) =>
        string.Join(';', of, date.ToString("yyyy-MM-dd"), customer, N(d), N(t), N(l), "", seq, description, tolerance, start, end, resource);

    private static async Task<HttpResponseMessage> UploadAsync(HttpClient c, byte[] bytes, string name = "process-templates.csv") =>
        await c.PostAsync("/api/production/process-templates/import", new MultipartFormDataContent { { new ByteArrayContent(bytes), "file", name } });

    private static Task<HttpResponseMessage> UploadAsync(HttpClient c, string csv) => UploadAsync(c, new UTF8Encoding(false).GetBytes(csv));

    private async Task<ProcessTemplateImportResult> ImportAsync(params string[] rows)
    {
        var admin = await api.AdminAsync();
        var res = await UploadAsync(admin, Header + "\n" + string.Join('\n', rows));
        res.EnsureSuccessStatusCode();
        return await res.Read<ProcessTemplateImportResult>();
    }

    private static ProductIn Tube(string code, decimal d, decimal t = 1.5m, decimal? l = 1000m) =>
        new(code, "Tubo " + code, ProductKind.Part, TubeShape.Circular, d, null, null, t, l, null, null, "73063010", "PC", null, false, null, null);

    private static async Task<CustomerOut> NewCustomerAsync(HttpClient admin, string name, string? trade = null) =>
        await (await admin.Post("/api/customers", new CustomerIn(name, trade, null, ConsumerType.Normal))).Read<CustomerOut>();

    private static async Task<ProductionOrderOut> NewOrderAsync(HttpClient c, int productId, int? customerId, string? primaryTube = null) =>
        await (await c.Post("/api/production/orders", new ProductionOrderIn(productId, 10m, Today.AddDays(30), CustomerId: customerId, PrimaryTube: primaryTube))).Read<ProductionOrderOut>();

    private static async Task<ProductionOrderOut> GetAsync(HttpClient c, int id) => await (await c.GetAsync($"/api/production/orders/{id}")).Read<ProductionOrderOut>();

    private static async Task<ProcessSuggestionOut> SuggestAsync(HttpClient c, int orderId)
    {
        var res = await c.PostAsync($"/api/production/orders/{orderId}/process/suggest", null);
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        return await res.Read<ProcessSuggestionOut>();
    }

    /// <summary>Makes sure the plant has a machine for each kind (names as in the live database) and returns the ones the suggester picks.</summary>
    private async Task<MachineIndex> EnsureMachinesAsync(HttpClient admin)
    {
        await using var db = api.NewDb();
        foreach (var (word, name) in new[] { ("PERFILAD", "PERFILADEIRA 001"), ("TREFIL", "TREFILA"), ("ENDIREIT", "ENDIREITADEIRA/CORTE"), ("INSPE", "INSPECAO FINAL") })
        {
            var names = await db.Machines.AsNoTracking().Select(m => m.Name).ToListAsync();
            if (!names.Any(n => ProcessSuggester.Fold(n).Contains(word)))
                (await admin.Post("/api/machines", new MachineIn(Code("PX", 10), name, null, null))).EnsureSuccessStatusCode();
        }
        return await MachineIndex.LoadAsync(db, CancellationToken.None);
    }

    // ---- pure rules -----------------------------------------------------------------------------------------------

    [Theory]
    [InlineData(3000, "+30")]
    [InlineData(2500, "+30")]
    [InlineData(2499, "± 0,05")]
    [InlineData(500, "± 0,05")]
    [InlineData(499.9, "± 0,50")]
    [InlineData(120, "± 0,50")]
    public void Straighten_and_cut_tolerance_follows_the_length(double length, string expected) =>
        Assert.Equal(expected, ProcessSuggester.RuleTolerance(OperationKind.StraightenCut, (decimal)length));

    [Fact]
    public void Rules_give_profile_and_draw_a_tenth_and_inspection_a_dash_and_nothing_to_other_types()
    {
        Assert.Equal("± 0,10", ProcessSuggester.RuleTolerance(OperationKind.StraightenCut, null));
        Assert.Equal("± 0,10", ProcessSuggester.RuleTolerance(OperationKind.Profile, 3000));
        Assert.Equal("± 0,10", ProcessSuggester.RuleTolerance(OperationKind.Draw, 100));
        Assert.Equal("-", ProcessSuggester.RuleTolerance(OperationKind.Inspection, 3000));
        Assert.Null(ProcessSuggester.RuleTolerance(OperationKind.Other, 3000));
        Assert.Null(ProcessSuggester.RuleTolerance(OperationKind.Brush, 3000));
    }

    [Fact]
    public void Machines_are_found_by_name_keywords_without_case_or_accents_and_types_without_keyword_get_none()
    {
        var index = MachineIndex.Of([
            new Machine { Id = 1, Code = "ED001", Name = "ENDIREITADEIRA" },
            new Machine { Id = 2, Code = "EC001", Name = "Endireitadeira / Corte" },
            new Machine { Id = 3, Code = "CO001", Name = "CORTE" },
            new Machine { Id = 4, Code = "IF001", Name = "Inspeção Final" },
            new Machine { Id = 5, Code = "PF001", Name = "perfiladeira 001" },
            new Machine { Id = 6, Code = "TF001", Name = "TREFILA" },
            new Machine { Id = 7, Code = "ES001", Name = "ESCOVADEIRA" },
            new Machine { Id = 8, Code = "PL001", Name = "POLITRIZ" },
            new Machine { Id = 9, Code = "SV001", Name = "SERVICO DE CORTE MP" },
        ]);
        Assert.Equal(2, index.For(OperationKind.StraightenCut)!.Id);
        Assert.Equal(4, index.For(OperationKind.Inspection)!.Id);
        Assert.Equal(5, index.For(OperationKind.Profile)!.Id);
        Assert.Equal(6, index.For(OperationKind.Draw)!.Id);
        Assert.Equal(7, index.For(OperationKind.Brush)!.Id);
        Assert.Equal(8, index.For(OperationKind.Polish)!.Id);
        Assert.Null(index.For(OperationKind.Other));

        // Without a machine named after both words the one that straightens is taken.
        Assert.Equal(1, MachineIndex.Of([new Machine { Id = 1, Code = "ED001", Name = "ENDIREITADEIRA" }, new Machine { Id = 3, Code = "CO001", Name = "CORTE" }]).For(OperationKind.StraightenCut)!.Id);

        Assert.Equal(OperationKind.Profile, ProcessSuggester.KindOf("Perfilar 14,00mm"));
        Assert.Equal(OperationKind.Draw, ProcessSuggester.KindOf("Trefilar para  12,00mm"));
        Assert.Equal(OperationKind.StraightenCut, ProcessSuggester.KindOf("Endireitar e Cortar 869"));
        Assert.Equal(OperationKind.Inspection, ProcessSuggester.KindOf("Inspeção Final"));
        Assert.Equal(OperationKind.Other, ProcessSuggester.KindOf("Beneficiamento"));
        Assert.Equal(OperationKind.Other, ProcessSuggester.KindOf("Tratamento térmico"));
        // The resource written on the legacy paper decides before the description.
        Assert.Equal(5, ProcessSuggester.MachineFor(index, "Operação 10", "Perfiladeira")!.Id);
        Assert.Equal(4, ProcessSuggester.MachineFor(index, "Inspeção Final", "Visual/Dimensional")!.Id);
        Assert.Null(ProcessSuggester.MachineFor(index, "Beneficiamento", null));
    }

    [Fact]
    public void Data_reset_never_touches_the_process_templates()
    {
        var tables = (Dictionary<ResetScope, string[]>)typeof(DataResetService).GetField("Tables", BindingFlags.NonPublic | BindingFlags.Static)!.GetValue(null)!;
        Assert.DoesNotContain("process_templates", tables.Values.SelectMany(t => t));
        Assert.DoesNotContain("process_template_operations", tables.Values.SelectMany(t => t));
    }

    // ---- import -----------------------------------------------------------------------------------------------------

    [Fact]
    public async Task Import_groups_rows_by_OF_keeps_the_latest_process_and_is_idempotent()
    {
        var customer = Letters(8) + " Industria";
        var d = NewDiameter();
        var older = Today.AddDays(-200);
        var newer = Today.AddDays(-20);

        // The newer OF comes first in the file: the date decides, not the order.
        var first = await ImportAsync(
            Row("0200-26", newer, customer, d, 1.5m, 1000, 10, "Perfilar 14,00mm", "± 0,10", "Perfiladeira"),
            Row("0200-26", newer, customer, d, 1.5m, 1000, 20, "Inspeção Final", "-", "Visual/Dimensional"),
            Row("0100-25", older, customer, d, 1.5m, 1000, 10, "Perfilar 14,00mm", "± 0,20", "Perfiladeira"),
            Row("0100-25", older, customer, d, 1.5m, 1000, 20, "Trefilar para 9,52mm", "± 0,05", "Trefiladeira"),
            Row("0100-25", older, customer, d, 1.5m, 1000, 30, "Inspeção Final", "-", "Visual/Dimensional"));
        Assert.Equal(5, first.Read);
        Assert.Equal(1, first.Templates);
        Assert.Equal(0, first.Updated);
        Assert.Equal(2, first.Operations);
        Assert.Equal(0, first.Skipped);
        Assert.Equal(older, first.FirstDate);
        Assert.Equal(newer, first.LastDate);

        await using (var db = api.NewDb())
        {
            var t = await db.ProcessTemplates.Include(x => x.Operations).SingleAsync(x => x.CustomerName == customer);
            Assert.Equal("0200-26", t.SourceRef);
            Assert.Equal(newer, t.SourceDate);
            Assert.Equal(Ebt.Core.Sales.PriceHistoryImporter.CustomerKey(customer).ToUpperInvariant(), t.CustomerKey);
            Assert.Equal(["Perfilar 14,00mm", "Inspeção Final"], t.Operations.OrderBy(o => o.Sequence).Select(o => o.Description));
            Assert.Equal("Visual/Dimensional", t.Operations.Single(o => o.Description == "Inspeção Final").Resource);
        }

        // Same file again: nothing changes.
        var again = await ImportAsync(
            Row("0200-26", newer, customer, d, 1.5m, 1000, 10, "Perfilar 14,00mm", "± 0,10", "Perfiladeira"),
            Row("0200-26", newer, customer, d, 1.5m, 1000, 20, "Inspeção Final", "-", "Visual/Dimensional"));
        Assert.Equal(0, again.Templates);
        Assert.Equal(0, again.Updated);
        Assert.Equal(0, again.Operations);

        // An older OF never replaces a newer one.
        var old = await ImportAsync(Row("0050-24", Today.AddDays(-900), customer, d, 1.5m, 1000, 10, "Perfilar 99", "± 9"));
        Assert.Equal(0, old.Updated);

        // A newer OF replaces the process.
        var update = await ImportAsync(
            Row("0300-26", Today.AddDays(-2), customer, d, 1.5m, 1000, 10, "Trefilar para 8,00mm", "± 0,08"),
            Row("0300-26", Today.AddDays(-2), customer, d, 1.5m, 1000, 20, "Endireitar e Cortar 1000", "± 0,05"),
            Row("0300-26", Today.AddDays(-2), customer, d, 1.5m, 1000, 30, "Inspeção Final", "-"));
        Assert.Equal(0, update.Templates);
        Assert.Equal(1, update.Updated);
        Assert.Equal(3, update.Operations);
        await using var db2 = api.NewDb();
        var after = await db2.ProcessTemplates.Include(x => x.Operations).SingleAsync(x => x.CustomerName == customer);
        Assert.Equal("0300-26", after.SourceRef);
        Assert.Equal(3, after.Operations.Count);
        Assert.Equal(3, await db2.ProcessTemplateOperations.CountAsync(o => o.TemplateId == after.Id));
    }

    [Fact]
    public async Task Import_counts_skipped_rows_by_reason_and_rejects_future_dates()
    {
        var customer = Letters(8) + " Industria";
        var d = NewDiameter();
        var result = await ImportAsync(
            Row("1-26", Today.AddDays(-10), customer, d, 1.5m, 1000, 10, "Perfilar 14,00mm", "± 0,10"),
            Row("1-26", Today.AddDays(-10), customer, d, 1.5m, 1000, 20, "", "± 0,10"),                       // no description
            Row("2-26", Today.AddDays(90), customer, d, 1.5m, 1000, 10, "Perfilar 14,00mm", "± 0,10"),        // future
            "3-26;nao-e-data;" + customer + ";" + N(d) + ";1.5;1000;;10;Perfilar;;;;",                         // unreadable date
            "4-26;" + Today.AddDays(-5).ToString("yyyy-MM-dd") + ";" + customer + ";;1.5;1000;;10;Perfilar;;;;", // no diameter
            "5-26;" + Today.AddDays(-5).ToString("yyyy-MM-dd") + ";;" + N(d) + ";1.5;1000;;10;Perfilar;;;;",   // no customer
            Row("6-26", Today.AddDays(-5), customer, d, 80m, 1000, 10, "Perfilar", null));                    // wall thicker than the radius
        Assert.Equal(7, result.Read);
        Assert.Equal(1, result.Templates);
        Assert.Equal(1, result.Operations);
        Assert.Equal(6, result.Skipped);
        Assert.Equal(1, result.SkippedReasons["operação"]);
        Assert.Equal(2, result.SkippedReasons["data"]);
        Assert.Equal(3, result.SkippedReasons["medidas"]);
        Assert.Equal(3, result.SkippedReasons.Count);
    }

    [Fact]
    public async Task Import_reads_windows_1252_with_tab_delimiter_and_accented_headers()
    {
        var customer = Letters(6) + " Ação";
        var d = NewDiameter();
        var csv = string.Join("\r\n",
            "OF\tData\tCliente\tDiâmetro\tEspessura\tComprimento\tEspecificação\tSeq\tDescrição\tTolerância\tInício\tFim\tRecurso",
            $"7-26\t{Today.AddDays(-3):dd/MM/yyyy}\t{customer}\t{N(d)}\t1.5\t1000\t\t10\tTrefilar para 9,52mm\t± 0,05\t11,00\t9,52\tTrefiladeira");
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var admin = await api.AdminAsync();
        var res = await UploadAsync(admin, Encoding.GetEncoding(1252).GetBytes(csv));
        res.EnsureSuccessStatusCode();
        var result = await res.Read<ProcessTemplateImportResult>();
        Assert.Equal(1, result.Templates);
        await using var db = api.NewDb();
        var op = await db.ProcessTemplateOperations.AsNoTracking().SingleAsync(o => o.Template!.CustomerName == customer);
        Assert.Equal("± 0,05", op.Tolerance);
        Assert.Equal("11,00", op.MeasureStart);
        Assert.Equal("9,52", op.MeasureEnd);
        Assert.Equal("Trefiladeira", op.Resource);
    }

    [Fact]
    public async Task Import_needs_admin_and_a_valid_file_and_summary_is_readable()
    {
        var customer = Letters(8) + " Industria";
        var d = NewDiameter();
        await ImportAsync(Row("8-26", Today.AddDays(-3), customer, d, 1.5m, 1000, 10, "Perfilar 14,00mm", "± 0,10"));
        foreach (var role in new[] { UserRole.Production, UserRole.Reader })
        {
            var user = await api.UserAsync(role);
            Assert.Equal(HttpStatusCode.Forbidden, (await UploadAsync(user, Header + "\n")).StatusCode);
        }
        Assert.Equal(HttpStatusCode.Unauthorized, (await UploadAsync(api.Anonymous(), Header + "\n")).StatusCode);

        var admin = await api.AdminAsync();
        Assert.Equal(HttpStatusCode.BadRequest, (await UploadAsync(admin, new byte[0])).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await UploadAsync(admin, "a;b;c\n1;2;3")).StatusCode);

        var reader = await api.UserAsync(UserRole.Reader);
        var summary = await (await reader.GetAsync("/api/production/process-templates/summary")).Read<ProcessTemplateSummary>();
        Assert.True(summary.Templates >= 1);
        Assert.True(summary.Operations >= 1);
        Assert.True(summary.Customers >= 1);
        Assert.NotNull(summary.LastDate);
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().GetAsync("/api/production/process-templates/summary")).StatusCode);
    }

    // ---- suggester --------------------------------------------------------------------------------------------------

    [Fact]
    public async Task Rules_process_has_tolerance_and_machine_by_operation_type_and_length()
    {
        var admin = await api.AdminAsync();
        var machines = await EnsureMachinesAsync(admin);
        var mine = await NewCustomerAsync(admin, Letters(8) + " Industria");
        var other = Letters(8) + " Outros";
        var d = NewDiameter();
        var product = await (await admin.Post("/api/products", Tube(Code("S"), d, 1.5m, 3000m))).Read<ProductOut>();

        // 4. Rules: no template, no previous OF.
        var first = await NewOrderAsync(admin, product.Id, mine.Id, "Rolo 140,00 x 1,20 mm");
        Assert.Equal(["Perfilar 140,00mm", $"Trefilar para {d.ToString("0.00", System.Globalization.CultureInfo.GetCultureInfo("pt-BR"))}mm", "Endireitar e Cortar 3000", "Inspeção Final"], first.Operations.Select(o => o.Description));
        Assert.Equal(["± 0,10", "± 0,10", "+30", "-"], first.Operations.Select(o => o.Tolerance));
        Assert.Equal([machines.For(OperationKind.Profile)!.Id, machines.For(OperationKind.Draw)!.Id, machines.For(OperationKind.StraightenCut)!.Id, machines.For(OperationKind.Inspection)!.Id], first.Operations.Select(o => o.MachineId!.Value));
        Assert.All(first.Operations, o => Assert.False(string.IsNullOrEmpty(o.MachineName)));
        var viaRules = await SuggestAsync(admin, first.Id); // the OF itself is never its own source
        Assert.Equal("Rules", viaRules.Source);
        Assert.Null(viaRules.SourceRef);
        Assert.Equal(first.Operations.Select(o => o.Description), viaRules.Operations.Select(o => o.Description));

        // Shorter tube: the length bucket changes the straightening tolerance.
        var short500 = await (await admin.Post("/api/products", Tube(Code("S"), NewDiameter(), 1.5m, 800m))).Read<ProductOut>();
        var shortOrder = await NewOrderAsync(admin, short500.Id, null);
        Assert.Equal("± 0,05", shortOrder.Operations.Single(o => o.Description!.StartsWith("Endireitar")).Tolerance);
        var tiny = await (await admin.Post("/api/products", Tube(Code("S"), NewDiameter(), 1.5m, 300m))).Read<ProductOut>();
        Assert.Equal("± 0,50", (await NewOrderAsync(admin, tiny.Id, null)).Operations.Single(o => o.Description!.StartsWith("Endireitar")).Tolerance);
    }

    [Fact]
    public async Task Suggestion_source_by_source()
    {
        var admin = await api.AdminAsync();
        var machines = await EnsureMachinesAsync(admin);
        var mine = await NewCustomerAsync(admin, Letters(8) + " Industria");
        var other = Letters(8) + " Outros";
        var d = NewDiameter();
        var product = await (await admin.Post("/api/products", Tube(Code("S"), d, 1.5m, 3000m))).Read<ProductOut>();

        // Rules: a probe order of another customer (the process it carries never counts for this customer).
        var rules = await NewOrderAsync(admin, product.Id, null);
        var viaRules = await SuggestAsync(admin, rules.Id);
        Assert.Equal("Rules", viaRules.Source);
        Assert.Null(viaRules.SourceRef);
        Assert.Equal(["± 0,10", "± 0,10", "+30", "-"], viaRules.Operations.Select(o => o.Tolerance));

        // TemplateDims: only a template of another customer for the same tube.
        await ImportAsync(
            Row("0010-26", Today.AddDays(-30), other, d, 1.5m, 3000, 10, "Perfilar 14,00mm", "± 0,12", "Perfiladeira"),
            Row("0010-26", Today.AddDays(-30), other, d, 1.5m, 3000, 20, "Endireitar e Cortar 3000", "+30", "Endireitadeira"),
            Row("0010-26", Today.AddDays(-30), other, d, 1.5m, 3000, 30, "Inspeção Final", "-", "Visual/Dimensional"));
        var viaDims = await NewOrderAsync(admin, product.Id, mine.Id);
        Assert.Equal(["Perfilar 14,00mm", "Endireitar e Cortar 3000", "Inspeção Final"], viaDims.Operations.Select(o => o.Description));
        Assert.Equal(["± 0,12", "+30", "-"], viaDims.Operations.Select(o => o.Tolerance));
        Assert.Equal(machines.For(OperationKind.Inspection)!.Id, viaDims.Operations[2].MachineId);
        Assert.Equal(machines.For(OperationKind.Profile)!.Id, viaDims.Operations[0].MachineId);
        var s1 = await SuggestAsync(admin, rules.Id);
        Assert.Equal("TemplateDims", s1.Source);
        Assert.Equal("0010-26", s1.SourceRef);
        // The previous OF of this customer for this tube beats it, but this one was just created from the template... so a customer template (next) is tested on a new tube.

        // TemplateCustomer: a template of this very customer wins over the other customer's.
        var d2 = NewDiameter();
        var product2 = await (await admin.Post("/api/products", Tube(Code("S"), d2, 1.5m, 3000m))).Read<ProductOut>();
        await ImportAsync(
            Row("0020-26", Today.AddDays(-60), other, d2, 1.5m, 3000, 10, "Perfilar 14,00mm", "± 0,12"),
            Row("0030-26", Today.AddDays(-90), mine.Name, d2, 1.5m, 3000, 10, "Trefilar para 9,00mm", "± 0,07", "Trefiladeira"),
            Row("0030-26", Today.AddDays(-90), mine.Name, d2, 1.5m, 3000, 20, "Inspeção Final", "-", "Visual/Dimensional"));
        var probe = await NewOrderAsync(admin, product2.Id, null);
        var viaCustomer = await SuggestAsync(admin, probe.Id);
        Assert.Equal("TemplateDims", viaCustomer.Source); // probe has no customer
        var mineOrder = await NewOrderAsync(admin, product2.Id, mine.Id);
        Assert.Equal(["Trefilar para 9,00mm", "Inspeção Final"], mineOrder.Operations.Select(o => o.Description));
        Assert.Equal("± 0,07", mineOrder.Operations[0].Tolerance);
        Assert.Equal(machines.For(OperationKind.Draw)!.Id, mineOrder.Operations[0].MachineId);

        // PreviousOrder: after the planner edits the process of that OF, the next OF of the same customer and tube copies the OF, not the template.
        var ops = mineOrder.Operations;
        (await admin.Put($"/api/production/orders/{mineOrder.Id}/process", new ProcessIn([
            new ProcessLine(ops[0].Sequence, "Trefilar para 9,00mm", "± 0,03", "11,00", "9,00"),
            new ProcessLine(ops[1].Sequence, "Inspeção Final", "-", null, null)]))).EnsureSuccessStatusCode();
        var next = await NewOrderAsync(admin, product2.Id, mine.Id);
        Assert.Equal("± 0,03", next.Operations[0].Tolerance);
        Assert.Equal("11,00", next.Operations[0].MeasureStart);
        Assert.Equal(machines.For(OperationKind.Draw)!.Id, next.Operations[0].MachineId);
        var viaPrevious = await SuggestAsync(admin, next.Id);
        Assert.Equal("PreviousOrder", viaPrevious.Source);
        Assert.Equal(mineOrder.Reference, viaPrevious.SourceRef);
        Assert.Equal("± 0,03", viaPrevious.Operations[0].Tolerance);
        Assert.Equal(next.Operations[0].MachineId, viaPrevious.Operations[0].MachineId);
        Assert.NotNull(viaPrevious.Operations[0].MachineName);
        Assert.NotNull(viaPrevious.Operations[0].MachineCode);

        // A cancelled OF is not a source: the template of the customer is back.
        (await admin.Post($"/api/production/orders/{mineOrder.Id}/cancel", new ProductionReasonIn("teste", true))).EnsureSuccessStatusCode();
        (await admin.Post($"/api/production/orders/{next.Id}/cancel", new ProductionReasonIn("teste", true))).EnsureSuccessStatusCode();
        var probe2 = await NewOrderAsync(admin, product2.Id, mine.Id);
        Assert.Equal("± 0,07", probe2.Operations[0].Tolerance);
        var viaTemplate = await SuggestAsync(admin, probe2.Id);
        Assert.Equal("TemplateCustomer", viaTemplate.Source);
        Assert.Equal("0030-26", viaTemplate.SourceRef);
    }

    [Fact]
    public async Task Tube_template_with_the_most_common_process_wins_over_a_newer_odd_one()
    {
        var admin = await api.AdminAsync();
        await EnsureMachinesAsync(admin);
        var d = NewDiameter();
        var product = await (await admin.Post("/api/products", Tube(Code("S"), d, 1.5m, 1000m))).Read<ProductOut>();
        await ImportAsync(
            Row("A-26", Today.AddDays(-50), "Alfa " + Letters(8), d, 1.5m, 1000, 10, "Trefilar para 9,00mm", "± 0,10"),
            Row("B-26", Today.AddDays(-40), "Beta " + Letters(8), d, 1.5m, 1000, 10, "Trefilar para 9,00mm", "± 0,10"),
            Row("C-26", Today.AddDays(-30), "Gama " + Letters(8), d, 1.5m, 1000, 10, "Trefilar para 9,00mm", "± 0,05"));
        var order = await NewOrderAsync(admin, product.Id, null);
        Assert.Equal("± 0,10", order.Operations.Single().Tolerance);
        var s = await SuggestAsync(admin, order.Id);
        Assert.Equal("TemplateDims", s.Source);
        Assert.Equal("B-26", s.SourceRef); // the latest of the two that agree
    }

    [Fact]
    public async Task Template_dimensions_match_within_tolerance_and_trade_name_counts_for_the_customer()
    {
        var admin = await api.AdminAsync();
        await EnsureMachinesAsync(admin);
        var trade = Letters(9);
        var customer = await NewCustomerAsync(admin, Letters(8) + " Razao", trade);
        var d = NewDiameter();
        // Thickness 1.5 vs 1.5004 and length 1000 vs 1000.8 are the same tube; 1.52 is not.
        var product = await (await admin.Post("/api/products", Tube(Code("S"), d, 1.5004m, 1000.8m))).Read<ProductOut>();
        await ImportAsync(
            Row("D-26", Today.AddDays(-30), trade + " Ltda", d + 0.004m, 1.5m, 1000, 10, "Trefilar para 9,00mm", "± 0,01"),
            Row("E-26", Today.AddDays(-20), trade + " Ltda", d, 1.52m, 1000, 10, "Trefilar para 7,00mm", "± 0,02"));
        var order = await NewOrderAsync(admin, product.Id, customer.Id);
        Assert.Equal("Trefilar para 9,00mm", order.Operations.Single().Description);
        var suggestion = await SuggestAsync(admin, order.Id);
        Assert.Equal("TemplateCustomer", suggestion.Source);
        Assert.Equal("D-26", suggestion.SourceRef);
    }

    // ---- suggest endpoint -------------------------------------------------------------------------------------------

    [Fact]
    public async Task Suggest_endpoint_saves_nothing_and_answers_409_after_release_404_unknown_and_403_for_readers()
    {
        var admin = await api.AdminAsync();
        await EnsureMachinesAsync(admin);
        var product = await (await admin.Post("/api/products", Tube(Code("S"), NewDiameter()))).Read<ProductOut>();
        var order = await NewOrderAsync(admin, product.Id, null);
        var before = await GetAsync(admin, order.Id);
        var s = await SuggestAsync(admin, order.Id);
        Assert.NotEmpty(s.Operations);
        Assert.Equal([10, 20, 30, 40], s.Operations.Select(o => o.Sequence));
        var after = await GetAsync(admin, order.Id);
        Assert.Equal(before.Operations.Select(o => (o.Id, o.Description, o.Tolerance, o.MachineId)), after.Operations.Select(o => (o.Id, o.Description, o.Tolerance, o.MachineId)));

        var reader = await api.UserAsync(UserRole.Reader);
        Assert.Equal(HttpStatusCode.Forbidden, (await reader.PostAsync($"/api/production/orders/{order.Id}/process/suggest", null)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await admin.PostAsync("/api/production/orders/999999/process/suggest", null)).StatusCode);

        (await admin.Post($"/api/production/orders/{order.Id}/cancel", new ProductionReasonIn("teste", true))).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Conflict, (await admin.PostAsync($"/api/production/orders/{order.Id}/process/suggest", null)).StatusCode);
    }

    // ---- replace process with machine -------------------------------------------------------------------------------

    [Fact]
    public async Task Replace_process_sets_the_machine_keeps_it_when_omitted_and_rejects_unknown_ones()
    {
        var admin = await api.AdminAsync();
        var machines = await EnsureMachinesAsync(admin);
        var product = await (await admin.Post("/api/products", Tube(Code("S"), NewDiameter(), 1.5m, 3000m))).Read<ProductOut>();
        var order = await NewOrderAsync(admin, product.Id, null);
        var ops = order.Operations;
        var inspection = machines.For(OperationKind.Inspection)!;
        var profile = machines.For(OperationKind.Profile)!;

        var res = await admin.Put($"/api/production/orders/{order.Id}/process", new ProcessIn([
            new ProcessLine(ops[0].Sequence, ops[0].Description, "± 0,10", null, null),                       // keeps its machine
            new ProcessLine(ops[1].Sequence, ops[1].Description, "± 0,10", null, null, inspection.Id),         // changes it
            new ProcessLine(null, "Beneficiamento", null, null, null),                                          // new row: none
            new ProcessLine(null, "Escovar", null, null, null, profile.Id)]));                                  // new row with a machine
        var after = (await res.Read<ProductionOrderOut>()).Operations.OrderBy(o => o.Sequence).ToList();
        Assert.Equal(ops[0].MachineId, after[0].MachineId);
        Assert.Equal(inspection.Id, after[1].MachineId);
        Assert.Equal(inspection.Name, after[1].MachineName);
        Assert.Null(after[2].MachineId);
        Assert.Null(after[2].MachineName);
        Assert.Equal(profile.Id, after[3].MachineId);

        Assert.Equal(HttpStatusCode.BadRequest, (await admin.Put($"/api/production/orders/{order.Id}/process", new ProcessIn([new ProcessLine(null, "Perfilar", null, null, null, 999999)]))).StatusCode);
        Assert.Equal(4, (await GetAsync(admin, order.Id)).Operations.Count);
    }

    // ---- routing gaps -----------------------------------------------------------------------------------------------

    [Fact]
    public async Task Routing_copied_onto_the_OF_gets_only_its_empty_requirement_and_machine_filled()
    {
        var admin = await api.AdminAsync();
        var machines = await EnsureMachinesAsync(admin);
        var product = await (await admin.Post("/api/products", Tube(Code("S"), NewDiameter(), 1.5m, 3000m))).Read<ProductOut>();
        var own = await (await admin.Post("/api/machines", new MachineIn(Code("MQ", 10), "Serra propria", null, null))).Read<MachineOut>();
        (await admin.Post($"/api/products/{product.Id}/routing", new RoutingOperationIn(10, null, null, null, null, 1m, 50m, 1m, "Perfilar 14,00mm", null, null))).EnsureSuccessStatusCode();
        (await admin.Post($"/api/products/{product.Id}/routing", new RoutingOperationIn(20, null, own.Id, null, null, 1m, 50m, 1m, "Endireitar e Cortar 3000", "+45", null))).EnsureSuccessStatusCode();
        (await admin.Post($"/api/products/{product.Id}/routing", new RoutingOperationIn(30, null, null, null, null, 1m, 50m, 1m, "Montagem", null, null))).EnsureSuccessStatusCode();

        var order = await NewOrderAsync(admin, product.Id, null);
        var ops = order.Operations.OrderBy(o => o.Sequence).ToList();
        Assert.Equal("± 0,10", ops[0].Tolerance);
        Assert.Equal(machines.For(OperationKind.Profile)!.Id, ops[0].MachineId);
        Assert.Equal("+45", ops[1].Tolerance);          // the routing's own value stays
        Assert.Equal(own.Id, ops[1].MachineId);          // and its machine
        Assert.Null(ops[2].Tolerance);                   // no rule for this type
        Assert.Null(ops[2].MachineId);
    }

    // ---- bulk completion --------------------------------------------------------------------------------------------

    [Fact]
    public async Task Complete_requirements_fills_only_empty_fields_fixes_the_inspection_swap_and_previews_without_writing()
    {
        var admin = await api.AdminAsync();
        var machines = await EnsureMachinesAsync(admin);
        var product = await (await admin.Post("/api/products", Tube(Code("S"), NewDiameter(), 1.5m, 3000m))).Read<ProductOut>();
        var own = await (await admin.Post("/api/machines", new MachineIn(Code("MQ", 10), "Serra propria", null, null))).Read<MachineOut>();
        var order = await NewOrderAsync(admin, product.Id, null);
        var ops = order.Operations;
        // Legacy-looking process: first op has everything, second lacks both, third has the swap, fourth has an outside-type name.
        (await admin.Put($"/api/production/orders/{order.Id}/process", new ProcessIn([
            new ProcessLine(ops[0].Sequence, "Perfilar 14,00mm", "± 0,02", null, null, own.Id),
            new ProcessLine(ops[1].Sequence, "Trefilar para 9,52mm", null, null, null),
            new ProcessLine(ops[2].Sequence, "Endireitar e Cortar 3000", null, null, null),
            new ProcessLine(ops[3].Sequence, "Inspeção Final", "Visual/Dimensional", null, null),
            new ProcessLine(null, "Beneficiamento", null, null, null)]))).EnsureSuccessStatusCode();
        // The machines of the new rows come from the plant (no machine on the legacy ones): clear them through the database.
        await using (var db = api.NewDb())
        {
            await db.ProductionOrderOperations.Where(o => o.OrderId == order.Id && o.Sequence > 10).ExecuteUpdateAsync(s => s.SetProperty(o => o.MachineId, (int?)null));
        }
        var before = (await GetAsync(admin, order.Id)).Operations.OrderBy(o => o.Sequence).ToList();

        var preview = await (await admin.Post("/api/production/orders/bulk/complete-requirements", new BulkApplyIn(false))).Read<BulkRequirementsResult>();
        Assert.True(preview.Matched >= 1);
        Assert.Equal(0, preview.Done);
        Assert.True(preview.OperationsFilled >= 3);
        var untouched = (await GetAsync(admin, order.Id)).Operations.OrderBy(o => o.Sequence).ToList();
        Assert.Equal(before.Select(o => (o.Tolerance, o.MachineId)), untouched.Select(o => (o.Tolerance, o.MachineId)));

        var applied = await (await admin.Post("/api/production/orders/bulk/complete-requirements", new BulkApplyIn(true))).Read<BulkRequirementsResult>();
        Assert.True(applied.Done >= 1);
        Assert.True(applied.OperationsFilled >= 3);
        var after = (await GetAsync(admin, order.Id)).Operations.OrderBy(o => o.Sequence).ToList();
        Assert.Equal(["Perfilar 14,00mm", "Trefilar para 9,52mm", "Endireitar e Cortar 3000", "Inspeção Final", "Beneficiamento"], after.Select(o => o.Description));
        Assert.Equal([10, 20, 30, 40, 50], after.Select(o => o.Sequence));
        Assert.Equal("± 0,02", after[0].Tolerance);                  // never overwritten
        Assert.Equal(own.Id, after[0].MachineId);
        Assert.Equal("± 0,10", after[1].Tolerance);
        Assert.Equal(machines.For(OperationKind.Draw)!.Id, after[1].MachineId);
        Assert.Equal("+30", after[2].Tolerance);
        Assert.Equal(machines.For(OperationKind.StraightenCut)!.Id, after[2].MachineId);
        Assert.Equal("-", after[3].Tolerance);                       // swap fixed
        Assert.Equal(machines.For(OperationKind.Inspection)!.Id, after[3].MachineId);
        Assert.Null(after[4].Tolerance);                             // no source for this type: nothing invented
        Assert.Null(after[4].MachineId);

        // Applied once: a second run finds nothing to do on this order.
        (await admin.Post("/api/production/orders/bulk/complete-requirements", new BulkApplyIn(true))).EnsureSuccessStatusCode();
        var again = (await GetAsync(admin, order.Id)).Operations.OrderBy(o => o.Sequence).ToList();
        Assert.Equal(after.Select(o => (o.Tolerance, o.MachineId)), again.Select(o => (o.Tolerance, o.MachineId)));

        await using var db2 = api.NewDb();
        Assert.True(await db2.AuditLog.AnyAsync(a => a.Entity == nameof(ProductionOrder) && a.Action == "Requirements"));
    }

    [Fact]
    public async Task Complete_requirements_leaves_cancelled_orders_alone_and_is_admin_only()
    {
        var admin = await api.AdminAsync();
        await EnsureMachinesAsync(admin);
        var product = await (await admin.Post("/api/products", Tube(Code("S"), NewDiameter()))).Read<ProductOut>();
        var order = await NewOrderAsync(admin, product.Id, null);
        (await admin.Put($"/api/production/orders/{order.Id}/process", new ProcessIn([new ProcessLine(order.Operations[0].Sequence, "Perfilar", null, null, null)]))).EnsureSuccessStatusCode();
        await using (var db = api.NewDb())
            await db.ProductionOrderOperations.Where(o => o.OrderId == order.Id).ExecuteUpdateAsync(s => s.SetProperty(o => o.MachineId, (int?)null));
        (await admin.Post($"/api/production/orders/{order.Id}/cancel", new ProductionReasonIn("teste", true))).EnsureSuccessStatusCode();

        (await admin.Post("/api/production/orders/bulk/complete-requirements", new BulkApplyIn(true))).EnsureSuccessStatusCode();
        var cancelled = await GetAsync(admin, order.Id);
        Assert.Null(cancelled.Operations.Single().Tolerance);
        Assert.Null(cancelled.Operations.Single().MachineId);

        foreach (var role in new[] { UserRole.Production, UserRole.Reader })
            Assert.Equal(HttpStatusCode.Forbidden, (await (await api.UserAsync(role)).Post("/api/production/orders/bulk/complete-requirements", new BulkApplyIn(true))).StatusCode);
    }

    [Fact]
    public async Task Order_operations_expose_the_machine_name_next_to_code_and_id()
    {
        var admin = await api.AdminAsync();
        var machines = await EnsureMachinesAsync(admin);
        var product = await (await admin.Post("/api/products", Tube(Code("S"), NewDiameter(), 1.5m, 3000m))).Read<ProductOut>();
        var order = await NewOrderAsync(admin, product.Id, null);
        var profile = machines.For(OperationKind.Profile)!;
        var op = order.Operations.Single(o => o.MachineId == profile.Id);
        Assert.Equal(profile.Code, op.MachineCode);
        Assert.Equal(profile.Name, op.MachineName);
        var json = await (await admin.GetAsync($"/api/production/orders/{order.Id}")).Content.ReadAsStringAsync();
        Assert.Contains("\"machineName\"", json);
    }
}
