using System.Net;
using System.Reflection;
using System.Text;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Ebt.Core.Maintenance;
using Ebt.Core.Sales;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Tests;

/// <summary>Price suggestion (weighted nearest neighbours over the price history and live order lines) and the CSV import that feeds it.</summary>
[Collection("api")]
public class PriceSuggestionTests(ApiFixture api)
{
    private static DateOnly Today => Clock.Today();
    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();
    private static string Day(int daysAgo) => Today.AddDays(-daysAgo).ToString("yyyy-MM-dd");
    private static string N(decimal v) => v.ToString(System.Globalization.CultureInfo.InvariantCulture);

    private static decimal Net(decimal d, decimal t, decimal l) => TubeWeight.NetWeightKg(TubeShape.Circular, d, null, null, t, l)!.Value;

    private async Task ClearHistoryAsync()
    {
        await using var db = api.NewDb();
        await db.PriceHistory.ExecuteDeleteAsync();
    }

    private static async Task<HttpResponseMessage> UploadAsync(HttpClient c, byte[] bytes, string name = "price-history.csv")
    {
        var form = new MultipartFormDataContent { { new ByteArrayContent(bytes), "file", name } };
        return await c.PostAsync("/api/sales/price-history/import", form);
    }

    private static Task<HttpResponseMessage> UploadAsync(HttpClient c, string csv) => UploadAsync(c, new UTF8Encoding(false).GetBytes(csv));

    private async Task<PriceHistoryImportResult> ImportAsync(string csv)
    {
        var admin = await api.AdminAsync();
        var res = await UploadAsync(admin, csv);
        res.EnsureSuccessStatusCode();
        return await res.Read<PriceHistoryImportResult>();
    }

    private async Task<CustomerOut> NewCustomerAsync(HttpClient admin, string name) =>
        await (await admin.Post("/api/customers", new CustomerIn(name, null, null, ConsumerType.Normal))).Read<CustomerOut>();

    private async Task<PriceSuggestionResult> SuggestAsync(HttpClient c, string query)
    {
        var res = await c.GetAsync("/api/sales/price-suggestion?" + query);
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        return await res.Read<PriceSuggestionResult>();
    }

    [Fact]
    public async Task Import_reads_pt_br_money_pc_unit_skips_invalid_rows_and_is_idempotent()
    {
        await ClearHistoryAsync();
        var csv = string.Join("\n",
            "data;cliente;diametro;espessura;comprimento;unid;valor unit;quantidade",
            "2026-01-10;Cli A;60,3;3;6000;PÇ;R$ 1.234,56;10",
            "10/01/2026;Cli B;60.3;3;6000;KG;23,5;5",
            "2026-01-10;Cli C;60,3;40;6000;PC;10;1",       // wall too thick
            "2026-01-10;Cli D;60,3;3;6000;MT;10;1",        // unknown unit
            "2026-01-10;Cli E;60,3;3;6000;PC;0;1",         // no price
            "2026-01-10;Cli A;60,3;3;6000;PÇ;R$ 1.234,56;10", // same row again
            "");
        var first = await ImportAsync(csv);
        Assert.Equal(6, first.Read);
        Assert.Equal(2, first.Imported);
        Assert.Equal(1, first.Duplicates);
        Assert.Equal(3, first.Skipped);
        Assert.Equal(new Dictionary<string, int> { ["unidade"] = 1, ["data"] = 0, ["medidas"] = 1, ["preço"] = 1 }, first.SkippedReasons);
        Assert.Equal(new DateOnly(2026, 1, 10), first.FirstDate);
        Assert.Equal(new DateOnly(2026, 1, 10), first.LastDate);

        await using (var db = api.NewDb())
        {
            var rows = await db.PriceHistory.AsNoTracking().OrderBy(h => h.CustomerName).ToListAsync();
            Assert.Equal(2, rows.Count);
            Assert.Equal("PC", rows[0].Unit);
            Assert.Equal(1234.56m, rows[0].UnitPrice);
            var net = Net(60.3m, 3m, 6000m);
            Assert.Equal(net, rows[0].WeightKg);
            Assert.InRange(rows[0].PricePerKg, 1234.56m / net - 0.001m, 1234.56m / net + 0.001m);
            Assert.Equal("KG", rows[1].Unit);
            Assert.Equal(23.5m, rows[1].PricePerKg);
        }

        var again = await ImportAsync(csv);
        Assert.Equal(0, again.Imported);
        Assert.Equal(3, again.Skipped);
        Assert.Equal(3, again.Duplicates);
        await using var check = api.NewDb();
        Assert.Equal(2, await check.PriceHistory.CountAsync());

        var admin = await api.AdminAsync();
        var summary = await (await admin.GetAsync("/api/sales/price-history/summary")).Read<PriceHistorySummary>();
        Assert.Equal(2, summary.Count);
        Assert.Equal(new DateOnly(2026, 1, 10), summary.FirstDate);
        var audit = await (await admin.GetAsync("/api/audit?entity=PriceHistory")).Read<Page<AuditOut>>();
        Assert.Contains(audit.Items, a => a.Action == "Import");
    }

    [Fact]
    public async Task Import_accepts_windows_1252_files_and_comma_delimiter_with_english_headers()
    {
        await ClearHistoryAsync();
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var csv = "date,customer,diameter,thickness,length,unit,price,quantity\n" + $"{Day(5)},\"Aço Forte, Ltda\",48.3,2.5,3000,PCS,\"1234.56\",3\n";
        var res = await UploadAsync(await api.AdminAsync(), Encoding.GetEncoding(1252).GetBytes(csv));
        res.EnsureSuccessStatusCode();
        Assert.Equal(1, (await res.Read<PriceHistoryImportResult>()).Imported);
        await using var db = api.NewDb();
        var row = await db.PriceHistory.AsNoTracking().SingleAsync();
        Assert.Equal("Aço Forte, Ltda", row.CustomerName);
        Assert.Equal("PC", row.Unit);
    }

    [Fact]
    public async Task Import_needs_the_price_edit_policy_and_a_valid_header()
    {
        var csv = $"date;customer;diameter;thickness;length;unit;price\n{Day(3)};Policy Co;50;2;1000;PC;40\n";
        Assert.Equal(HttpStatusCode.Forbidden, (await UploadAsync(await api.UserAsync(UserRole.Sales), csv)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await UploadAsync(await api.UserAsync(UserRole.Reader), csv)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await UploadAsync(await api.UserAsync(UserRole.SalesManager), csv)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await UploadAsync(await api.AdminAsync(), csv.Replace("40", "41"))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await UploadAsync(await api.AdminAsync(), "foo;bar\n1;2\n")).StatusCode);
    }

    [Fact]
    public async Task Same_customer_and_same_dimension_gets_its_last_price()
    {
        await ClearHistoryAsync();
        var admin = await api.AdminAsync();
        var token = Code("Zeta", 9);
        var customer = await NewCustomerAsync(admin, $"{token} Indústria de Aço S.A.");
        await ImportAsync(string.Join("\n",
            "date;customer;diameter;thickness;length;unit;price",
            // The customer's name is spelled differently in the history (no accents, LTDA): still the same customer.
            $"{Day(200)};{token} Industria de Aco Ltda;60.3;3;6000;PC;280",
            $"{Day(40)};{token} industria de aco;60.3;3;6000;PC;300",
            $"{Day(10)};{token} industria de aco;21.3;2;1000;PC;12",
            $"{Day(30)};Outro Cliente;60.3;3;6000;PC;100",
            $"{Day(31)};Outro Cliente;60.3;3.2;6000;PC;110",
            ""));
        var r = await SuggestAsync(admin, $"diameter=60.3&thickness=3&length=6000&customerId={customer.Id}&quantity=4");
        var net = Net(60.3m, 3m, 6000m);
        Assert.Equal("CustomerRepeat", r.Suggestion.Basis);
        Assert.Equal("High", r.Suggestion.Confidence);
        Assert.Equal(Math.Round(300m / net, 2), r.Suggestion.PricePerKg);
        Assert.Equal(Math.Round(280m / net, 2), r.Suggestion.Low);
        Assert.Equal(Math.Round(300m / net, 2), r.Suggestion.High);
        Assert.Equal(Math.Round(r.Suggestion.PricePerKg!.Value * net, 2), r.Suggestion.PricePerPiece);
        Assert.Equal(Math.Round(r.Suggestion.PricePerKg!.Value * net * 4, 2), r.Suggestion.TotalForQuantity);
        Assert.Equal(Math.Round(net, 3), r.Weight.NetKg);
        // The customer's most recent sale of any dimension.
        Assert.NotNull(r.CustomerLast);
        Assert.Equal(21.3m, r.CustomerLast!.Diameter);
        Assert.Equal(12m, r.CustomerLast.UnitPrice);
        Assert.Equal("Histórico", r.Similar[0].Source);

        // Without a customer the same query is a plain neighbours estimate and carries no quantity total.
        var anon = await SuggestAsync(admin, "diameter=60.3&thickness=3&length=6000");
        Assert.Equal("Neighbours", anon.Suggestion.Basis);
        Assert.Null(anon.Suggestion.TotalForQuantity);
        Assert.Null(anon.CustomerLast);
    }

    [Fact]
    public async Task Neighbours_are_a_distance_weighted_geometric_mean_of_the_seven_nearest()
    {
        await ClearHistoryAsync();
        var admin = await api.AdminAsync();
        (decimal D, decimal T, decimal L, decimal Price)[] sales =
        [
            (88.9m, 4m, 3000m, 520m), (88.9m, 4m, 3200m, 560m), (88.9m, 3.5m, 3000m, 470m), (76.1m, 4m, 3000m, 430m),
            (101.6m, 4m, 3000m, 600m), (88.9m, 5m, 3000m, 640m), (88.9m, 4m, 2500m, 430m), (114.3m, 6m, 3000m, 1100m), (60.3m, 2m, 3000m, 200m)
        ];
        var lines = sales.Select((s, i) => $"{Day(20 + i)};Cliente N{i};{N(s.D)};{N(s.T)};{N(s.L)};PC;{N(s.Price)}");
        await ImportAsync("date;customer;diameter;thickness;length;unit;price\n" + string.Join("\n", lines) + "\n");

        decimal qd = 88.9m, qt = 4m, ql = 3100m;
        // The newer a sale, the more it weighs (half the weight per 6 months): the rows are dated 20, 21, 22... days ago.
        var ranked = sales.Select((s, i) => (Dist: PriceSuggestionService.Distance(s.D, s.T, s.L, qd, qt, ql), Pkg: s.Price / Net(s.D, s.T, s.L), Age: PriceSuggestionService.RecencyFactor(Today.AddDays(-(20 + i)), Today)))
            .OrderBy(x => x.Dist).Take(7).ToList();
        double sw = ranked.Sum(x => 1 / (0.02 + x.Dist) * x.Age), swl = ranked.Sum(x => 1 / (0.02 + x.Dist) * x.Age * Math.Log((double)x.Pkg));
        var expected = (decimal)Math.Exp(swl / sw);

        var r = await SuggestAsync(admin, $"diameter={N(qd)}&thickness={N(qt)}&length={N(ql)}");
        Assert.Equal("Neighbours", r.Suggestion.Basis);
        Assert.InRange(r.Suggestion.PricePerKg!.Value, expected - 0.006m, expected + 0.006m);
        Assert.Equal(Math.Round(ranked.Min(x => x.Pkg), 2), r.Suggestion.Low);
        Assert.Equal(Math.Round(ranked.Max(x => x.Pkg), 2), r.Suggestion.High);
        Assert.InRange(r.Similar.Count, 9, 10); // live orders of other tests may fill the tenth slot
        Assert.True(r.Similar.Zip(r.Similar.Skip(1)).All(p => p.First.Distance <= p.Second.Distance));
        Assert.True(r.HistoryCount >= 9);
        Assert.Contains(r.Suggestion.Confidence, new[] { "High", "Medium" });

        // A tube far from everything sold before is still priced, but flagged as a guess.
        var far = await SuggestAsync(admin, "diameter=300&thickness=10&length=6000");
        Assert.Equal("Low", far.Suggestion.Confidence);
        // An exact dimension match is a confident one.
        var exact = await SuggestAsync(admin, "diameter=88.9&thickness=4&length=3000");
        Assert.Equal("High", exact.Suggestion.Confidence);
    }

    [Fact]
    public async Task History_older_than_24_months_is_ignored()
    {
        await ClearHistoryAsync();
        var admin = await api.AdminAsync();
        await ImportAsync($"date;customer;diameter;thickness;length;unit;price\n{Today.AddMonths(-30):yyyy-MM-dd};Antigo;70;3;2000;PC;500\n");
        var r = await SuggestAsync(admin, "diameter=70&thickness=3&length=2000");
        Assert.DoesNotContain(r.Similar, s => s.Customer == "Antigo");
    }

    [Fact]
    public async Task Without_any_data_the_basis_is_none()
    {
        await ClearHistoryAsync();
        await using var db = api.NewDb();
        await using var tx = await db.Database.BeginTransactionAsync();
        // Other tests leave live orders behind: hide them (rolled back below) so that nothing is left to learn from.
        await db.SalesOrders.ExecuteUpdateAsync(s => s.SetProperty(o => o.Source, DataSource.Test));
        var r = await new PriceSuggestionService(db).SuggestAsync(50m, 2m, 1000m, null, 5m, null);
        await tx.RollbackAsync();
        Assert.Equal("None", r.Suggestion.Basis);
        Assert.Null(r.Suggestion.PricePerKg);
        Assert.Empty(r.Similar);
        Assert.Equal(0, r.HistoryCount);
        Assert.True(r.Weight.NetKg > 0);
    }

    [Fact]
    public async Task Invalid_dimensions_are_rejected_with_400()
    {
        var admin = await api.AdminAsync();
        foreach (var q in new[] { "diameter=0&thickness=2&length=1000", "diameter=50&thickness=0&length=1000", "diameter=50&thickness=2", "diameter=50&thickness=25&length=1000", "diameter=50&thickness=30&length=1000", "diameter=50&thickness=2&length=-1" })
            Assert.Equal(HttpStatusCode.BadRequest, (await admin.GetAsync("/api/sales/price-suggestion?" + q)).StatusCode);
    }

    [Fact]
    public async Task Read_only_roles_cannot_see_prices()
    {
        foreach (var role in new[] { UserRole.Reader, UserRole.Stock, UserRole.Purchasing })
        {
            var c = await api.UserAsync(role);
            Assert.Equal(HttpStatusCode.Forbidden, (await c.GetAsync("/api/sales/price-suggestion?diameter=50&thickness=2&length=1000")).StatusCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await c.GetAsync("/api/sales/price-history/summary")).StatusCode);
        }
        foreach (var role in new[] { UserRole.Sales, UserRole.SalesManager })
            Assert.Equal(HttpStatusCode.OK, (await (await api.UserAsync(role)).GetAsync("/api/sales/price-suggestion?diameter=50&thickness=2&length=1000")).StatusCode);
    }

    [Fact]
    public async Task Gross_weight_adds_2_8_percent_unless_the_product_has_its_own_loss()
    {
        var admin = await api.AdminAsync();
        var net = Net(48.3m, 2.5m, 3000m);
        var r = await SuggestAsync(admin, "diameter=48.3&thickness=2.5&length=3000");
        Assert.Equal(Math.Round(net, 3), r.Weight.NetKg);
        Assert.Equal(2.8m, r.Weight.LossPercent);
        Assert.Equal(Math.Round(net * 1.028m, 3), r.Weight.GrossKg);

        var product = await (await admin.Post("/api/products", new ProductIn(Code("L"), "Tubo com perda", ProductKind.Part, TubeShape.Circular, 48.3m, null, null, 2.5m, 3000m, null, 5m, "73063010", "PC", 50, false, null, null))).Read<ProductOut>();
        var own = await SuggestAsync(admin, $"diameter=48.3&thickness=2.5&length=3000&productId={product.Id}");
        Assert.Equal(5m, own.Weight.LossPercent);
        Assert.Equal(Math.Round(net * 1.05m, 3), own.Weight.GrossKg);
    }

    [Fact]
    public async Task Live_order_lines_count_unless_the_order_is_test_data()
    {
        await ClearHistoryAsync();
        var admin = await api.AdminAsync();
        var customer = await NewCustomerAsync(admin, "Live " + Code("C"));
        var address = await (await admin.Post($"/api/customers/{customer.Id}/addresses", new CustomerAddressIn("26133636000103", "SP", null, "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", "3515004", "06800000", "5101", "Edilto", "compras@cliente.com", null))).Read<CustomerAddressOut>();
        var tube = await (await admin.Post("/api/products", new ProductIn(Code("T"), "Tubo vivo", ProductKind.Part, TubeShape.Circular, 133m, null, null, 7m, 5000m, null, null, "73063010", "PC", 50, false, null, null))).Read<ProductOut>();
        async Task<SalesOrderOut> OrderAsync(decimal price) =>
            await (await admin.Post("/api/sales/orders", new SalesOrderIn(customer.Id, address.Id, [new SalesLineInput(tube.Id, 2m, price)], "PO-" + Code("P", 6)))).Read<SalesOrderOut>();
        var real = await OrderAsync(777.77m);
        var test = await OrderAsync(999.99m);
        await using (var db = api.NewDb())
            await db.SalesOrders.Where(o => o.Id == test.Id).ExecuteUpdateAsync(s => s.SetProperty(o => o.Source, DataSource.Test));

        var r = await SuggestAsync(admin, $"diameter=133&thickness=7&length=5000&customerId={customer.Id}");
        var net = Net(133m, 7m, 5000m);
        Assert.Contains(r.Similar, s => s.Source == "MetaGest" && s.UnitPrice == 777.77m);
        Assert.DoesNotContain(r.Similar, s => s.UnitPrice == 999.99m);
        Assert.Equal("CustomerRepeat", r.Suggestion.Basis);
        Assert.Equal(Math.Round(777.77m / net, 2), r.Suggestion.PricePerKg);
        Assert.Single(real.Lines);
    }

    [Theory]
    [InlineData("NBK DIN 2393", "NBK")]
    [InlineData("BK DIN 2393", "BK")]
    [InlineData("DIN EN 10305-3 E420 + CR2", "EN10305")]
    [InlineData("EN 10305-3 E355", "EN10305")]
    [InlineData("NBK + EN 10305", "NBK")]
    [InlineData("EN 10305-2 – BK", "BK")]
    [InlineData("EN 10305-2 BK", "BK")]
    [InlineData("DIN EN 10305-1 +NBK", "NBK")]
    [InlineData("EN10305-4 NBK", "NBK")]
    [InlineData("BKS 10305", "EN10305")]
    [InlineData("ABK", "other")]
    [InlineData("aço carbono 1010 nbk", "NBK")]
    [InlineData("NBR 5599", "NBR")]
    [InlineData("SAE 1010", "SAE")]
    [InlineData("aço 1020", "SAE")]
    [InlineData("St 52", "other")]
    [InlineData("nbk", "NBK")]
    [InlineData("other", "other")]
    [InlineData("", null)]
    [InlineData("   ", null)]
    [InlineData(null, null)]
    public void Spec_text_is_classified_in_a_fixed_order(string? text, string? expected) => Assert.Equal(expected, PriceSpec.Classify(text));

    [Fact]
    public async Task A_different_specification_pushes_a_row_away_from_the_nearest_neighbours()
    {
        await ClearHistoryAsync();
        var admin = await api.AdminAsync();
        await ImportAsync("date;customer;diameter;thickness;length;unit;price;spec\n"
            + $"{Day(10)};Alfa Tubos;88.9;4;3000;PC;600;NBK DIN 2393\n{Day(11)};Beta Tubos;88.9;4;3000;PC;450;BK DIN 2393\n");
        var net = Net(88.9m, 4m, 3000m);

        var nbk = await SuggestAsync(admin, "diameter=88.9&thickness=4&length=3000&spec=NBK");
        Assert.Equal("NBK", nbk.Similar[0].Spec);
        Assert.Equal(0d, nbk.Similar[0].Distance);
        Assert.Equal(PriceSuggestionService.SpecPenalty, nbk.Similar[1].Distance, 3);

        var bk = await SuggestAsync(admin, "diameter=88.9&thickness=4&length=3000&spec=" + Uri.EscapeDataString("BK DIN 2393"));
        Assert.Equal("BK", bk.Similar[0].Spec);
        // Live orders of other tests may add faint neighbours, so only the direction and size of the effect are checked.
        Assert.True(nbk.Suggestion.PricePerKg > bk.Suggestion.PricePerKg,$"NBK {nbk.Suggestion.PricePerKg} vs BK {bk.Suggestion.PricePerKg} (rows are {600m / net:0.00} and {450m / net:0.00})");

        // Unknown spec on the query: no penalty at all.
        var none = await SuggestAsync(admin, "diameter=88.9&thickness=4&length=3000");
        Assert.All(none.Similar.Take(2), s => Assert.Equal(0d, s.Distance));
    }

    [Fact]
    public async Task Import_stores_the_specification_class_and_upserts_on_the_same_key()
    {
        await ClearHistoryAsync();
        var head = "data;cliente;diametro;espessura;comprimento;unid;valor unit;especificacao do material\n";
        var first = await ImportAsync(head + $"{Day(100)};Cliente Upsert Ltda;42,4;2;3000;PC;55,5;\n");
        Assert.Equal(1, first.Imported);

        // Same sale seen again from the other source: later date and a known specification refresh the stored row.
        var second = await ImportAsync(head + $"{Day(10)};Cliente Upsert S.A.;42,4;2;3000;PÇ;55.50;DIN EN 10305-3 E420 + CR2\n");
        Assert.Equal(0, second.Imported);
        Assert.Equal(1, second.Updated);
        await using (var db = api.NewDb())
        {
            var row = await db.PriceHistory.AsNoTracking().SingleAsync();
            Assert.Equal(Today.AddDays(-10), row.Date);
            Assert.Equal("EN10305", row.Spec);
        }

        // An older copy with another spec changes nothing.
        var third = await ImportAsync(head + $"{Day(300)};Cliente Upsert;42,4;2;3000;PC;55,5;BK\n");
        Assert.Equal(0, third.Imported + third.Updated);
        Assert.Equal(1, third.Duplicates);
        await using var check = api.NewDb();
        var kept = await check.PriceHistory.AsNoTracking().SingleAsync();
        Assert.Equal(Today.AddDays(-10), kept.Date);
        Assert.Equal("EN10305", kept.Spec);

        // The same sale twice in one file collapses to one row (latest date, any spec).
        await ClearHistoryAsync();
        var both = await ImportAsync(head + $"{Day(50)};Dup Cliente;30;2;1000;PC;20;\n{Day(5)};Dup Cliente Ltda;30;2;1000;PC;20;NBK\n");
        Assert.Equal(1, both.Imported);
        Assert.Equal(1, both.Duplicates);
        await using var db2 = api.NewDb();
        var one = await db2.PriceHistory.AsNoTracking().SingleAsync();
        Assert.Equal(Today.AddDays(-5), one.Date);
        Assert.Equal("NBK", one.Spec);
    }

    [Fact]
    public void Data_reset_never_touches_the_price_history()
    {
        var tables = (Dictionary<ResetScope, string[]>)typeof(DataResetService).GetField("Tables", BindingFlags.NonPublic | BindingFlags.Static)!.GetValue(null)!;
        Assert.DoesNotContain("price_history", tables.Values.SelectMany(t => t));
        Assert.DoesNotContain("price_simulations", tables.Values.SelectMany(t => t));
    }

    [Fact]
    public void Customer_names_are_compared_without_accents_punctuation_and_company_suffixes()
    {
        Assert.Equal("acme aco", PriceSuggestionService.NormalizeName("ACME Aço S.A."));
        Assert.Equal("acme aco", PriceSuggestionService.NormalizeName("Acme Aco Ltda."));
        Assert.Equal("acme aco", PriceSuggestionService.NormalizeName("acme  aço  EIRELI"));
        Assert.True(PriceSuggestionService.NamesMatch("acme aco", "acme aco industria"));
        Assert.False(PriceSuggestionService.NamesMatch("acme", "acmeron tubos"));
        Assert.False(PriceSuggestionService.NamesMatch("ab", "abc"));
    }

    [Fact]
    public void Oblong_weight_is_the_stadium_wall_and_the_equivalent_diameter_keeps_the_perimeter()
    {
        // 17 x 6,2 x 1,4 x 680 mm (Formigari's drawing): wall area 51,35 mm2 -> 0,274 kg
        var kg = TubeWeight.OblongNetWeightKg(17m, 6.2m, 1.4m, 680m)!.Value;
        Assert.InRange(kg, 0.2735m, 0.2745m);
        Assert.InRange(TubeWeight.OblongEquivalentDiameterMm(17m, 6.2m), 13.07m, 13.09m);
        // a "stadium" as wide as it is tall is a round tube
        Assert.Equal(TubeWeight.NetWeightKg(TubeShape.Circular, 10m, null, null, 1m, 1000m)!.Value, TubeWeight.OblongNetWeightKg(10m, 10m, 1m, 1000m)!.Value, 3);
        Assert.Null(TubeWeight.OblongNetWeightKg(5m, 10m, 1m, 1000m));   // width smaller than height
        Assert.Null(TubeWeight.OblongNetWeightKg(17m, 6.2m, 3.1m, 680m)); // wall eats the short side
    }

    [Fact]
    public async Task Oblong_price_is_looked_up_for_the_round_tube_of_the_same_perimeter_and_says_so()
    {
        await ClearHistoryAsync();
        // round 13,1 x 1,4 x 680 sold at R$ 20/kg: the oblong 17 x 6,2 x 1,4 x 680 has an equivalent diameter of 13,08
        var today = DateTime.UtcNow.ToString("yyyy-MM-dd");
        await ImportAsync($"date;customer;diameter;thickness;length;unit;price;quantity\n{today};Cli A;13,1;1,4;680;KG;20;100\n");
        await using var hidden = await LiveOrdersHidden.HideAsync(api); // live orders of other tests would add faint neighbours to the 20/kg row
        var admin = await api.AdminAsync();
        var r = await SuggestAsync(admin, "shape=oblong&width=17&height=6.2&thickness=1.4&length=680&quantity=1000");
        Assert.Equal("Oblong", r.Profile!.Shape);
        Assert.InRange(r.Profile.EquivalentDiameter, 13.07m, 13.09m);
        Assert.InRange(r.Weight.NetKg, 0.273m, 0.275m);
        Assert.Equal(20m, r.Suggestion.PricePerKg);
        Assert.Equal("Neighbours", r.Suggestion.Basis);
        Assert.InRange(r.Suggestion.PricePerPiece!.Value, 5.47m, 5.49m);
        Assert.InRange(r.Suggestion.TotalForQuantity!.Value, 5470m, 5490m);
        // a round request carries no profile
        Assert.Null((await SuggestAsync(admin, "diameter=13.1&thickness=1.4&length=680")).Profile);
    }

    [Fact]
    public async Task Oblong_dimensions_are_validated()
    {
        var admin = await api.AdminAsync();
        foreach (var q in new[] { "shape=oblong&height=6.2&thickness=1.4&length=680", "shape=oblong&width=17&thickness=1.4&length=680", "shape=oblong&width=5&height=6.2&thickness=1.4&length=680",
                     "shape=oblong&width=17&height=6.2&thickness=3.1&length=680", "shape=oblong&width=17&height=6.2&length=680", "shape=triangle&diameter=50&thickness=2&length=1000" })
            Assert.Equal(HttpStatusCode.BadRequest, (await admin.GetAsync("/api/sales/price-suggestion?" + q)).StatusCode);
    }
}
