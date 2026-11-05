using System.Net;
using System.Text;
using Ebt.Api.Endpoints;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;
using Ebt.Core.Sales;
using Ebt.Core.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace Ebt.Tests;

/// <summary>Flags every live order as test data while a test checks exact prices, then puts the original source back. The api collection runs one test at a time.</summary>
internal sealed class LiveOrdersHidden : IAsyncDisposable
{
    private readonly ApiFixture api;
    private readonly List<(int Id, DataSource Source)> flipped;

    private LiveOrdersHidden(ApiFixture api, List<(int Id, DataSource Source)> flipped) { this.api = api; this.flipped = flipped; }

    public static async Task<LiveOrdersHidden> HideAsync(ApiFixture api)
    {
        await using var db = api.NewDb();
        var rows = await db.SalesOrders.AsNoTracking().Where(o => o.Source != DataSource.Test).Select(o => new { o.Id, o.Source }).ToListAsync();
        await db.SalesOrders.Where(o => o.Source != DataSource.Test).ExecuteUpdateAsync(s => s.SetProperty(o => o.Source, DataSource.Test));
        return new(api, rows.Select(r => (r.Id, r.Source)).ToList());
    }

    public async ValueTask DisposeAsync()
    {
        await using var db = api.NewDb();
        foreach (var group in flipped.GroupBy(f => f.Source))
        {
            var ids = group.Select(f => f.Id).ToList();
            var source = group.Key;
            await db.SalesOrders.Where(o => ids.Contains(o.Id)).ExecuteUpdateAsync(s => s.SetProperty(o => o.Source, source));
        }
    }
}

/// <summary>Price simulator extras: repeat row, usage counts, confidence, recency, customer history, specification comparison, trend, customer factor, rectangular tubes,
/// de-duplication against live orders, import robustness, cache and the saved simulations.</summary>
[Collection("api")]
public class PriceSimulatorExtrasTests(ApiFixture api) : IAsyncLifetime
{
    private LiveOrdersHidden? hidden;

    public Task InitializeAsync() => Task.CompletedTask;

    public async Task DisposeAsync()
    {
        if (hidden is not null) await hidden.DisposeAsync();
    }

    private static DateOnly Today => Clock.Today();
    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();
    private static string Day(int daysAgo) => Today.AddDays(-daysAgo).ToString("yyyy-MM-dd");
    private const string Head = "date;customer;diameter;thickness;length;unit;price;spec\n";
    private static decimal Net(decimal d, decimal t, decimal l) => TubeWeight.NetWeightKg(TubeShape.Circular, d, null, null, t, l)!.Value;
    private sealed record IdOnly(int Id);

    /// <summary>Empties the history and sets the live orders that exist now aside (see <see cref="LiveOrdersHidden"/>); orders a test creates afterwards count.</summary>
    private async Task ClearHistoryAsync()
    {
        hidden ??= await LiveOrdersHidden.HideAsync(api);
        await using var db = api.NewDb();
        await db.PriceHistory.ExecuteDeleteAsync();
    }

    private async Task<PriceHistoryImportResult> ImportAsync(string csv)
    {
        var form = new MultipartFormDataContent { { new ByteArrayContent(new UTF8Encoding(false).GetBytes(csv)), "file", "h.csv" } };
        var res = await (await api.AdminAsync()).PostAsync("/api/sales/price-history/import", form);
        return await res.Read<PriceHistoryImportResult>();
    }

    private async Task<PriceSuggestionResult> SuggestAsync(string query, HttpClient? c = null)
    {
        var res = await (c ?? await api.AdminAsync()).GetAsync("/api/sales/price-suggestion?" + query);
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        return await res.Read<PriceSuggestionResult>();
    }

    private async Task<CustomerOut> NewCustomerAsync(string name) =>
        await (await (await api.AdminAsync()).Post("/api/customers", new CustomerIn(name, null, null, ConsumerType.Normal))).Read<CustomerOut>();

    private async Task<SalesOrderOut> LiveOrderAsync(CustomerOut customer, decimal d, decimal t, decimal l, decimal price)
    {
        var admin = await api.AdminAsync();
        var address = await (await admin.Post($"/api/customers/{customer.Id}/addresses", new CustomerAddressIn("26133636000103", "SP", null, "148061942112", true, "Av. Brasil", "100", null, "Centro", "Embu", "3515004", "06800000", "5101", "Edilto", "compras@cliente.com", null))).Read<CustomerAddressOut>();
        var tube = await (await admin.Post("/api/products", new ProductIn(Code("T"), "Tubo vivo", ProductKind.Part, TubeShape.Circular, d, null, null, t, l, null, null, "73063010", "PC", 50, false, null, null))).Read<ProductOut>();
        return await (await admin.Post("/api/sales/orders", new SalesOrderIn(customer.Id, address.Id, [new SalesLineInput(tube.Id, 2m, price)], "PO-" + Code("P", 6)))).Read<SalesOrderOut>();
    }

    // ---- A4: specification classes

    [Fact]
    public void Spec_other_counts_like_an_unknown_specification_in_the_distance()
    {
        Assert.Equal(0d, PriceSuggestionService.Distance(50m, 2m, 1000m, 50m, 2m, 1000m, "other", "NBK"));
        Assert.Equal(0d, PriceSuggestionService.Distance(50m, 2m, 1000m, 50m, 2m, 1000m, "NBK", "other"));
        Assert.Equal(0d, PriceSuggestionService.Distance(50m, 2m, 1000m, 50m, 2m, 1000m, null, "NBK"));
        Assert.Equal(PriceSuggestionService.SpecPenalty, PriceSuggestionService.Distance(50m, 2m, 1000m, 50m, 2m, 1000m, "BK", "NBK"), 6);
    }

    [Fact]
    public async Task Import_stores_the_STKM13A_and_GBK_classes_and_a_GBK_query_still_gets_an_answer_from_BK_rows()
    {
        await ClearHistoryAsync();
        await ImportAsync(Head
            + $"{Day(5)};Alfa Oblongos;17;1.4;680;KG;40;JIS G3445 STKM13A\n"
            + $"{Day(6)};Beta Recozidos;17;1.4;680;KG;35;EN 10305-2 - GBK\n"
            + $"{Day(7)};Gama Brilhantes;17;1.4;680;KG;30;BK DIN 2393\n");
        await using (var db = api.NewDb())
            Assert.Equal(["BK", "GBK", "STKM13A"], await db.PriceHistory.AsNoTracking().Select(h => h.Spec!).OrderBy(s => s).ToArrayAsync());

        await ClearHistoryAsync();
        await ImportAsync(Head + $"{Day(5)};Delta Brilhantes;17;1.4;680;KG;30;BK\n{Day(6)};Eps Brilhantes;17;1.4;680;KG;31;BK\n");
        var r = await SuggestAsync("diameter=17&thickness=1.4&length=680&spec=GBK");
        Assert.Equal("Neighbours", r.Suggestion.Basis);
        Assert.NotNull(r.Suggestion.PricePerKg);
        Assert.All(r.Similar.Take(2), s => Assert.Equal("BK", s.Spec));
        Assert.Equal(PriceSuggestionService.SpecPenalty, r.Similar[0].Distance, 3); // known and different: penalised
        var stkm = await SuggestAsync("diameter=17&thickness=1.4&length=680&spec=" + Uri.EscapeDataString("JIS G3445 STKM13A"));
        Assert.NotNull(stkm.Suggestion.PricePerKg);
    }

    // ---- A2 / A3 / confidence

    [Fact]
    public async Task Repeat_returns_the_latest_near_sale_of_the_whole_history_and_counts_what_it_used()
    {
        await ClearHistoryAsync();
        var token = Code("Rep", 8);
        var customer = await NewCustomerAsync($"{token} Tubos Ltda");
        await ImportAsync(Head
            + $"{Day(1200)};{token} Tubos;70;3;2000;PC;300;\n"          // three and a half years old, exact tube
            + $"{Day(1000)};{token} Tubos;70.5;3;2000;KG;31.5;\n"       // newer, a bit farther
            + $"{Day(1300)};{token} Tubos;70;3;2000;KG;20;\n"           // oldest
            + $"{Day(30)};{token} Tubos;120;5;2000;PC;900;\n");         // recent but another tube: not near
        var r = await SuggestAsync($"diameter=70&thickness=3&length=2000&customerId={customer.Id}");
        Assert.Equal("CustomerRepeat", r.Suggestion.Basis);
        Assert.NotNull(r.Repeat);
        Assert.Equal(Today.AddDays(-1000), r.Repeat!.Date);
        Assert.Equal(70.5m, r.Repeat.Diameter);
        Assert.Equal("KG", r.Repeat.Unit);
        Assert.Equal(31.5m, r.Repeat.UnitPrice);
        Assert.Equal(31.5m, r.Repeat.PricePerKg);
        Assert.Equal(31.5m, r.Suggestion.PricePerKg);
        var perKgOld = Math.Round(300m / Net(70m, 3m, 2000m), 2);
        Assert.Equal(Math.Min(20m, perKgOld), r.Suggestion.Low);
        Assert.Equal(Math.Max(31.5m, perKgOld), r.Suggestion.High);
        Assert.Equal(3, r.Suggestion.UsedCount);
        Assert.Equal(Today.AddDays(-1000), r.Suggestion.NewestDate);
        Assert.Equal(Today.AddDays(-1300), r.Suggestion.OldestDate);
        // The newest sale is older than 24 months: no longer a High confidence repeat.
        Assert.Equal("Medium", r.Suggestion.Confidence);
    }

    [Fact]
    public async Task Repeat_of_the_same_day_picks_the_nearest_tube_and_a_recent_repeat_is_high_confidence()
    {
        await ClearHistoryAsync();
        var token = Code("Tie", 8);
        var customer = await NewCustomerAsync($"{token} Aco");
        await ImportAsync(Head + $"{Day(20)};{token} Aco;70.8;3;2000;KG;25;\n{Day(20)};{token} Aco;70;3;2000;KG;26;\n");
        var r = await SuggestAsync($"diameter=70&thickness=3&length=2000&customerId={customer.Id}");
        Assert.Equal(26m, r.Repeat!.PricePerKg);
        Assert.Equal("High", r.Suggestion.Confidence);
        Assert.Equal(2, r.Suggestion.UsedCount);
        // Without a customer there is no repeat.
        Assert.Null((await SuggestAsync("diameter=70&thickness=3&length=2000")).Repeat);
    }

    [Fact]
    public async Task Neighbours_report_used_rows_dates_and_confidence_follows_distance_count_and_age()
    {
        await ClearHistoryAsync();
        // nine sales of the same tube, 1 to 9 days old: exact match, many rows, fresh
        await ImportAsync(Head + string.Join("", Enumerable.Range(1, 9).Select(i => $"{Day(i)};Cli{i};77.3;3.7;3100;KG;{20 + i};\n")));
        var r = await SuggestAsync("diameter=77.3&thickness=3.7&length=3100");
        Assert.Equal("Neighbours", r.Suggestion.Basis);
        Assert.Equal(7, r.Suggestion.UsedCount);
        Assert.Equal(Today.AddDays(-1), r.Suggestion.NewestDate);
        Assert.Equal(Today.AddDays(-7), r.Suggestion.OldestDate);
        Assert.Equal("High", r.Suggestion.Confidence);
        Assert.Null(r.Repeat);

        // two rows only: not enough for High
        await ClearHistoryAsync();
        await ImportAsync(Head + $"{Day(5)};A Co;77.3;3.7;3100;KG;20;\n{Day(6)};B Co;77.3;3.7;3100;KG;22;\n");
        var two = await SuggestAsync("diameter=77.3&thickness=3.7&length=3100");
        Assert.Equal(2, two.Suggestion.UsedCount);
        Assert.Equal("Medium", two.Suggestion.Confidence);

        // a single row: Low
        await ClearHistoryAsync();
        await ImportAsync(Head + $"{Day(5)};A Co;77.3;3.7;3100;KG;20;\n");
        Assert.Equal("Low", (await SuggestAsync("diameter=77.3&thickness=3.7&length=3100")).Suggestion.Confidence);

        // three exact rows but 14 months old: Medium (too old for High)
        await ClearHistoryAsync();
        await ImportAsync(Head + string.Join("", Enumerable.Range(0, 3).Select(i => $"{Day(430 + i)};Cli{i};77.3;3.7;3100;KG;{20 + i};\n")));
        var old = await SuggestAsync("diameter=77.3&thickness=3.7&length=3100");
        Assert.Equal("Medium", old.Suggestion.Confidence);
        Assert.Equal(Today.AddDays(-430), old.Suggestion.NewestDate);

        // far from everything: Low whatever the count
        await ClearHistoryAsync();
        await ImportAsync(Head + string.Join("", Enumerable.Range(1, 5).Select(i => $"{Day(i)};Cli{i};30;2;3000;KG;{20 + i};\n")));
        Assert.Equal("Low", (await SuggestAsync("diameter=200&thickness=8&length=3100")).Suggestion.Confidence);
    }

    // ---- B: recency

    [Fact]
    public void Recency_halves_the_weight_every_six_months_and_ignores_future_dates()
    {
        var today = new DateOnly(2026, 6, 15);
        Assert.Equal(1d, PriceSuggestionService.RecencyFactor(today, today));
        Assert.Equal(1d, PriceSuggestionService.RecencyFactor(today.AddDays(10), today));
        Assert.InRange(PriceSuggestionService.RecencyFactor(today.AddDays(-183), today), 0.49, 0.51);
        Assert.InRange(PriceSuggestionService.RecencyFactor(today.AddDays(-365), today), 0.24, 0.26);
    }

    [Fact]
    public async Task An_old_cheap_row_weighs_less_than_a_recent_dear_one_at_the_same_distance()
    {
        await ClearHistoryAsync();
        await ImportAsync(Head + $"{Day(400)};Antigo Co;63.7;3.1;4100;KG;20;\n{Day(5)};Recente Co;63.7;3.1;4100;KG;30;\n");
        var r = await SuggestAsync("diameter=63.7&thickness=3.1&length=4100");
        var plain = Math.Sqrt(20 * 30); // what a recency-blind geometric mean gives: 24.49
        Assert.True(r.Suggestion.PricePerKg > (decimal)plain + 2m, $"price {r.Suggestion.PricePerKg} should lean to the recent 30");
        Assert.True(r.Suggestion.PricePerKg < 30m);
        Assert.Equal(20m, r.Suggestion.Low);
        Assert.Equal(30m, r.Suggestion.High);
    }

    // ---- C1: customer history

    [Fact]
    public async Task Customer_history_lists_the_latest_five_near_sales_of_the_whole_history()
    {
        await ClearHistoryAsync();
        var token = Code("His", 8);
        var customer = await NewCustomerAsync($"{token} Industria");
        var rows = string.Join("", Enumerable.Range(0, 7).Select(i => $"{Day(100 + i * 200)};{token} Industria;55;2.5;3000;KG;{30 - i};\n"));
        await ImportAsync(Head + rows + $"{Day(10)};{token} Industria;90;4;3000;KG;40;\n{Day(11)};Outro Cliente;55;2.5;3000;KG;99;\n");
        var r = await SuggestAsync($"diameter=55&thickness=2.5&length=3000&customerId={customer.Id}");
        Assert.NotNull(r.CustomerHistory);
        Assert.Equal(5, r.CustomerHistory!.Count);
        Assert.Equal(Today.AddDays(-100), r.CustomerHistory[0].Date);
        Assert.Equal(30m, r.CustomerHistory[0].UnitPrice);
        Assert.Equal(30m, r.CustomerHistory[0].PricePerKg);
        Assert.Equal("KG", r.CustomerHistory[0].Unit);
        Assert.Null(r.CustomerHistory[0].Quantity);
        Assert.True(r.CustomerHistory.Zip(r.CustomerHistory.Skip(1)).All(p => p.First.Date > p.Second.Date));
        Assert.DoesNotContain(r.CustomerHistory, h => h.UnitPrice is 99m or 40m);
        // No customer: empty list, never null.
        Assert.Empty((await SuggestAsync("diameter=55&thickness=2.5&length=3000")).CustomerHistory!);
    }

    // ---- C3: by specification

    [Fact]
    public async Task By_spec_compares_the_nearest_rows_of_each_class_by_dimensions_only()
    {
        await ClearHistoryAsync();
        await ImportAsync(Head
            + $"{Day(10)};A;88.9;4;3000;KG;30;NBK\n{Day(11)};B;88.9;4;3000;KG;32;NBK\n{Day(12)};C;88.9;4;3000;KG;31;NBK\n"
            + $"{Day(13)};D;88.9;4.2;3000;KG;22;BK\n{Day(14)};E;88.9;4.2;3000;KG;24;BK\n"
            + $"{Day(15)};F;20;1;500;KG;50;SAE\n"                 // dimensionally far: left out
            + $"{Day(16)};G;88.9;4;3000;KG;18;\n");               // no specification: ignored
        var r = await SuggestAsync("diameter=88.9&thickness=4&length=3000&spec=BK");
        Assert.NotNull(r.BySpec);
        var nbk = Assert.Single(r.BySpec!, s => s.Spec == "NBK");
        var bk = Assert.Single(r.BySpec!, s => s.Spec == "BK");
        Assert.DoesNotContain(r.BySpec!, s => s.Spec == "SAE");
        Assert.Equal(3, nbk.Count);
        Assert.Equal(31m, nbk.MedianPerKg);
        Assert.Equal(0d, nbk.NearestDistance);          // the asked spec (BK) does not push NBK away
        Assert.Equal(2, bk.Count);
        Assert.Equal(23m, bk.MedianPerKg);
        Assert.True(bk.NearestDistance > 0);
        Assert.True(r.BySpec!.Zip(r.BySpec!.Skip(1)).All(p => p.First.NearestDistance <= p.Second.NearestDistance));
        Assert.True(r.BySpec!.All(s => s.NearestDistance < 1.0));
    }

    // ---- C7: trend

    [Fact]
    public async Task Trend_is_the_monthly_median_of_near_rows_and_the_customer_trend_is_its_own_part()
    {
        await ClearHistoryAsync();
        var token = Code("Trd", 8);
        var customer = await NewCustomerAsync($"{token} Metais");
        await ImportAsync(Head
            + $"{Day(10)};{token} Metais;48;2;3000;KG;22;\n{Day(12)};Terceiro;48;2;3000;KG;24;\n{Day(14)};Quarto;48;2;3000;KG;26;\n"
            + $"{Day(400)};{token} Metais;48;2;3000;KG;18;\n"
            + $"{Day(100)};Longe;200;9;3000;KG;70;\n");     // far measure: not in the trend
        var r = await SuggestAsync($"diameter=48&thickness=2&length=3000&customerId={customer.Id}");
        Assert.NotNull(r.Trend);
        Assert.DoesNotContain(r.Trend!, p => p.PricePerKg == 70m);
        Assert.True(r.Trend!.Zip(r.Trend!.Skip(1)).All(p => string.CompareOrdinal(p.First.Month, p.Second.Month) < 0));
        Assert.All(r.Trend!, p => Assert.Matches(@"^\d{4}-\d{2}$", p.Month));
        Assert.Equal(4, r.Trend!.Sum(p => p.Count));
        var oldMonth = r.Trend!.Single(p => p.Month == Today.AddDays(-400).ToString("yyyy-MM"));
        Assert.Equal(18m, oldMonth.PricePerKg);
        Assert.Equal(1, oldMonth.Count);
        Assert.NotNull(r.CustomerTrend);
        Assert.Equal(2, r.CustomerTrend!.Sum(p => p.Count));
        Assert.Equal([18m, 22m], r.CustomerTrend!.OrderBy(p => p.Month).Select(p => p.PricePerKg).ToArray());
        // no customer: empty customer trend
        Assert.Empty((await SuggestAsync("diameter=48&thickness=2&length=3000")).CustomerTrend!);
        // rows older than 60 months are not part of the trend
        await ClearHistoryAsync();
        await ImportAsync(Head + $"{Today.AddMonths(-70):yyyy-MM-dd};Velho;48;2;3000;KG;10;\n");
        Assert.Empty((await SuggestAsync("diameter=48&thickness=2&length=3000")).Trend!);
    }

    // ---- C2: customer factor

    [Fact]
    public async Task Customer_factor_compares_the_customer_with_the_others_and_is_never_applied()
    {
        await ClearHistoryAsync();
        var token = Code("Fac", 8);
        var customer = await NewCustomerAsync($"{token} Compras");
        await ImportAsync(Head
            + string.Concat(new[] { 17.9m, 18m, 18.1m, 18.2m }.Select((p, i) => $"{Day(10 + i * 5)};{token} Compras;40;2;3000;KG;{p.ToString(System.Globalization.CultureInfo.InvariantCulture)};\n"))
            + string.Concat(new[] { "Alfa", "Beta", "Gama", "Delta", "Epsilon" }.Select((n, i) => $"{Day(100 + i)};{n} Tubos;40;2;3000;KG;20;\n")));
        var r = await SuggestAsync($"diameter=40&thickness=2&length=3000&customerId={customer.Id}");
        Assert.NotNull(r.CustomerFactor);
        Assert.Equal(4, r.CustomerFactor!.SampleSize);
        Assert.InRange(r.CustomerFactor.Ratio, 0.90m, 0.905m); // median of 17.9, 18, 18.1, 18.2 over the market's 20

        // A new dimension for this customer: the suggestion is the market-wide neighbours price, the factor changes nothing.
        var withCustomer = await SuggestAsync($"diameter=48&thickness=2&length=3000&customerId={customer.Id}");
        var without = await SuggestAsync("diameter=48&thickness=2&length=3000");
        Assert.Equal("Neighbours", withCustomer.Suggestion.Basis);
        Assert.Equal(without.Suggestion.PricePerKg, withCustomer.Suggestion.PricePerKg);

        // no customer, or fewer than three sales: no factor
        Assert.Null((await SuggestAsync("diameter=40&thickness=2&length=3000")).CustomerFactor);
        var small = await NewCustomerAsync($"{Code("Sma", 8)} Pequeno");
        Assert.Null((await SuggestAsync($"diameter=40&thickness=2&length=3000&customerId={small.Id}")).CustomerFactor);
    }

    // ---- C6: rectangular and square tubes

    [Fact]
    public void Square_tube_weight_is_the_wall_area_times_length()
    {
        // 20 x 20 x 2 x 1000: area 400 - 256 = 144 mm2 -> 144 * 1000 * 7.85e-6 = 1.1304 kg
        Assert.Equal(1.1304m, TubeWeight.NetWeightKg(TubeShape.Rectangular, null, 20m, 20m, 2m, 1000m));
        Assert.InRange(TubeWeight.RectEquivalentDiameterMm(20m, 20m), 25.464m, 25.466m);
        Assert.Equal(TubeWeight.RectEquivalentDiameterMm(30m, 20m), TubeWeight.RectEquivalentDiameterMm(20m, 30m));
    }

    [Fact]
    public async Task Rectangular_price_is_looked_up_for_the_round_tube_of_the_same_perimeter()
    {
        await ClearHistoryAsync();
        // 20 x 20 -> equivalent round diameter 25.46; round 25.5 x 2 x 1000 sold at R$ 21/kg
        await ImportAsync(Head + $"{Day(3)};Cli;25.5;2;1000;KG;21;\n");
        var r = await SuggestAsync("shape=rect&width=20&height=20&thickness=2&length=1000&quantity=10");
        Assert.Equal("Rectangular", r.Profile!.Shape);
        Assert.InRange(r.Profile.EquivalentDiameter, 25.464m, 25.466m);
        Assert.Equal(1.13m, r.Weight.NetKg, 2);
        Assert.Equal(21m, r.Suggestion.PricePerKg);
        Assert.Equal(Math.Round(21m * 1.1304m, 2), r.Suggestion.PricePerPiece);
        Assert.Equal(Math.Round(21m * 1.1304m * 10, 2), r.Suggestion.TotalForQuantity);
        // the sides can come in either order
        var swapped = await SuggestAsync("shape=rect&width=30&height=20&thickness=2&length=1000");
        var other = await SuggestAsync("shape=rect&width=20&height=30&thickness=2&length=1000");
        Assert.Equal(swapped.Weight.NetKg, other.Weight.NetKg);
        Assert.Equal(swapped.Profile!.EquivalentDiameter, other.Profile!.EquivalentDiameter);
    }

    [Fact]
    public async Task Rectangular_dimensions_are_validated_with_field_names()
    {
        var admin = await api.AdminAsync();
        async Task<string> Fail(string q)
        {
            var res = await admin.GetAsync("/api/sales/price-suggestion?" + q);
            Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
            return await res.Content.ReadAsStringAsync();
        }
        Assert.Contains("width", await Fail("shape=rect&height=20&thickness=2&length=1000"));
        Assert.Contains("height", await Fail("shape=rect&width=20&thickness=2&length=1000"));
        Assert.Contains("thickness", await Fail("shape=rect&width=20&height=20&thickness=10&length=1000"));
        Assert.Contains("thickness", await Fail("shape=rect&width=40&height=20&thickness=10&length=1000"));
        Assert.Contains("length", await Fail("shape=rect&width=20&height=20&thickness=2"));
        Assert.Contains("width", await Fail("shape=rect&width=-1&height=20&thickness=2&length=1000"));
    }

    // ---- A5 / A7: live orders against imported history

    [Fact]
    public async Task A_live_order_line_replaces_the_imported_row_of_the_same_sale()
    {
        await ClearHistoryAsync();
        var customer = await NewCustomerAsync("Dedupe Aco " + Code("C", 5));
        await LiveOrderAsync(customer, 141.3m, 6.55m, 5100m, 801.5m);
        // the same sale also found in the workbook (same customer, tube, price within 0.5%, a week apart), plus one that is not (price 10% off), plus one 100 days apart
        await ImportAsync(Head
            + $"{Day(7)};Dedupe Aco Ltda;141.3;6.55;5100;PC;803\n"
            + $"{Day(8)};Dedupe Aco Ltda;141.3;6.55;5100;PC;881\n"
            + $"{Day(150)};Dedupe Aco Ltda;141.3;6.55;5100;PC;801.5\n");
        var r = await SuggestAsync($"diameter=141.3&thickness=6.55&length=5100&customerId={customer.Id}");
        var near = r.Similar.Where(s => s.Diameter == 141.3m && s.Thickness == 6.55m).ToList();
        Assert.Contains(near, s => s.Source == "MetaGest" && s.UnitPrice == 801.5m);
        Assert.DoesNotContain(near, s => s.Source == "Histórico" && s.UnitPrice == 803m);
        Assert.Contains(near, s => s.Source == "Histórico" && s.UnitPrice == 881m);
        Assert.Contains(near, s => s.Source == "Histórico" && s.UnitPrice == 801.5m);
        Assert.Equal(3, near.Count);
    }

    [Fact]
    public async Task A_live_line_is_dated_by_the_quote_approval_or_else_the_order_creation_day()
    {
        await ClearHistoryAsync();
        var customer = await NewCustomerAsync("Datado " + Code("C", 5));
        var direct = await LiveOrderAsync(customer, 168.3m, 7.1m, 5200m, 901.11m);
        var viaQuote = await LiveOrderAsync(customer, 168.3m, 7.1m, 5200m, 902.22m);
        var decided = DateTimeOffset.UtcNow.AddDays(-100);
        await using (var db = api.NewDb())
        {
            var quote = new Quote { Number = Random.Shared.Next(900000, 999999), Reference = Code("Q", 10), CustomerId = customer.Id, DecidedAt = decided, Status = QuoteStatus.Approved };
            db.Quotes.Add(quote);
            await db.SaveChangesAsync();
            await db.SalesOrders.Where(o => o.Id == viaQuote.Id).ExecuteUpdateAsync(s => s.SetProperty(o => o.QuoteId, quote.Id));
        }
        await using var read = api.NewDb();
        var created = await read.SalesOrders.AsNoTracking().Where(o => o.Id == direct.Id).Select(o => o.CreatedAt).SingleAsync();
        var r = await SuggestAsync($"diameter=168.3&thickness=7.1&length=5200&customerId={customer.Id}");
        Assert.Equal(Clock.DateOf(created), r.Similar.Single(s => s.UnitPrice == 901.11m).Date);
        Assert.Equal(Clock.DateOf(decided), r.Similar.Single(s => s.UnitPrice == 902.22m).Date);
    }

    // ---- import robustness

    [Theory]
    [InlineData("UN", "PC")]
    [InlineData("und", "PC")]
    [InlineData("UNID.", "PC")]
    [InlineData("Pç", "PC")]
    [InlineData("pc", "PC")]
    [InlineData("PCS", "PC")]
    [InlineData("peça", "PC")]
    [InlineData("PEÇAS", "PC")]
    [InlineData("KG", "KG")]
    [InlineData("kgs", "KG")]
    [InlineData("Quilo", "KG")]
    [InlineData("QUILOS", "KG")]
    [InlineData("MT", null)]
    [InlineData("", null)]
    public void Units_are_read_in_the_ways_the_sheets_write_them(string raw, string? expected) => Assert.Equal(expected, PriceHistoryImporter.ParseUnit(raw));

    [Fact]
    public async Task Import_skips_far_future_dates_and_counts_skips_by_reason()
    {
        await ClearHistoryAsync();
        var res = await ImportAsync(Head
            + $"{Day(-10)};Futuro Perto;50;2;1000;PC;40;\n"       // ten days ahead: allowed
            + $"{Day(-31)};Futuro Longe;50;2;1000;PC;41;\n"       // 31 days ahead: typo
            + "01/01/2099;Ano Errado;50;2;1000;PC;42;\n"
            + ";Sem Data;50;2;1000;PC;43;\n"
            + $"{Day(3)};Unidade Ruim;50;2;1000;CX;44;\n"
            + $"{Day(3)};Medida Ruim;50;30;1000;PC;45;\n"
            + $"{Day(3)};Medida Ruim;0;2;1000;PC;45;\n"
            + $"{Day(3)};Sem Preco;50;2;1000;PC;0;\n"
            + $"{Day(3)};Preco Texto;50;2;1000;PC;abc;\n"
            + $"{Day(3)};;50;2;1000;PC;46;\n"                       // no customer: counted with the measures
            + $"{Day(3)};Boa Un;50;2;1000;UND;47;\n");
        Assert.Equal(11, res.Read);
        Assert.Equal(2, res.Imported);
        Assert.Equal(9, res.Skipped);
        Assert.Equal(3, res.SkippedReasons!["data"]);
        Assert.Equal(1, res.SkippedReasons["unidade"]);
        Assert.Equal(3, res.SkippedReasons["medidas"]);
        Assert.Equal(2, res.SkippedReasons["preço"]);
        Assert.Equal(res.Skipped, res.SkippedReasons.Values.Sum());
    }

    [Fact]
    public async Task Two_imports_of_the_same_new_rows_at_once_never_answer_500()
    {
        await ClearHistoryAsync();
        var csv = Head + string.Concat(Enumerable.Range(0, 300).Select(i => $"{Day(2)};Concorrente {i};50;2;{1000 + i};PC;{40 + i};\n"));
        var admin = await api.AdminAsync();
        HttpResponseMessage[] results = await Task.WhenAll(Enumerable.Range(0, 3).Select(async _ =>
        {
            var form = new MultipartFormDataContent { { new ByteArrayContent(new UTF8Encoding(false).GetBytes(csv)), "file", "h.csv" } };
            return await admin.PostAsync("/api/sales/price-history/import", form);
        }));
        Assert.All(results, r => Assert.Contains(r.StatusCode, new[] { HttpStatusCode.OK, HttpStatusCode.Conflict }));
        Assert.Contains(results, r => r.StatusCode == HttpStatusCode.OK);
        await using var db = api.NewDb();
        Assert.Equal(300, await db.PriceHistory.CountAsync());
    }

    // ---- cache

    [Fact]
    public async Task Cached_points_stay_for_the_ttl_until_an_import_invalidates_them()
    {
        await ClearHistoryAsync();
        var cache = new PriceDataCache(new MemoryCache(new MemoryCacheOptions()), 60);
        await using var db = api.NewDb();
        var svc = new PriceSuggestionService(db, cache);
        Task<PriceSuggestionResult> AskAsync() => svc.SuggestAsync(57.1m, 2.9m, 2700m, null, null, null);

        Assert.DoesNotContain((await AskAsync()).Similar, s => s.Customer == "Cache A");
        await using (var writer = api.NewDb())
        {
            writer.PriceHistory.Add(new PriceHistory { Date = Today, CustomerName = "Cache A", DiameterMm = 57.1m, ThicknessMm = 2.9m, LengthMm = 2700m, Unit = "KG", UnitPrice = 25m, WeightKg = 1m, PricePerKg = 25m, ImportKey = "cache-a-" + Guid.NewGuid() });
            await writer.SaveChangesAsync();
        }
        Assert.DoesNotContain((await AskAsync()).Similar, s => s.Customer == "Cache A");   // still the cached load

        await using var importDb = api.NewDb();
        await new PriceHistoryImporter(importDb, cache).ImportAsync(new UTF8Encoding(false).GetBytes(Head + $"{Day(1)};Cache B;57.1;2.9;2700;KG;26;\n"));
        var fresh = (await AskAsync()).Similar;
        Assert.Contains(fresh, s => s.Customer == "Cache A");
        Assert.Contains(fresh, s => s.Customer == "Cache B");

        // an explicit invalidation also works, and a cache of 0 seconds never keeps anything
        var off = new PriceDataCache(new MemoryCache(new MemoryCacheOptions()), 0);
        var offSvc = new PriceSuggestionService(db, off);
        await offSvc.SuggestAsync(57.1m, 2.9m, 2700m, null, null, null);
        await using (var writer = api.NewDb())
            await writer.PriceHistory.Where(h => h.CustomerName == "Cache B").ExecuteDeleteAsync();
        Assert.DoesNotContain((await offSvc.SuggestAsync(57.1m, 2.9m, 2700m, null, null, null)).Similar, s => s.Customer == "Cache B");
        cache.Invalidate();
        Assert.DoesNotContain((await AskAsync()).Similar, s => s.Customer == "Cache B");
    }

    // ---- saved simulations

    private static PriceSimulationIn Sim(string shape = "Round", string? customerName = "Cliente Sim", bool used = false) =>
        new(shape, shape == "Round" ? 50m : null, shape == "Round" ? null : 30m, shape == "Round" ? null : 20m, 2m, 3000m, "NBK", 100m, null, customerName, 15m, 18.5m, 24.9m, 111.2m, "Neighbours", "Medium", "7 vendas parecidas", "nota", used);

    [Fact]
    public async Task Simulations_are_saved_listed_newest_first_and_audited()
    {
        var admin = await api.AdminAsync();
        var sales = await api.UserAsync(UserRole.Sales);
        var res = await sales.Post("/api/sales/price-simulations", Sim("Rectangular", used: true));
        Assert.Equal(HttpStatusCode.Created, res.StatusCode);
        var id = (await res.Read<IdOnly>()).Id;
        var second = (await (await sales.Post("/api/sales/price-simulations", Sim())).Read<IdOnly>()).Id;

        var list = await (await sales.GetAsync("/api/sales/price-simulations?take=2")).Read<List<PriceSimulationOut>>();
        Assert.Equal([second, id], list.Select(s => s.Id).ToArray());
        var saved = list[1];
        Assert.Equal("Rectangular", saved.Shape);
        Assert.Equal(30m, saved.Width);
        Assert.Equal(20m, saved.Height);
        Assert.Null(saved.Diameter);
        Assert.Equal(2m, saved.Thickness);
        Assert.Equal(3000m, saved.Length);
        Assert.Equal("NBK", saved.Spec);
        Assert.Equal(100m, saved.Quantity);
        Assert.Equal(15m, saved.MarkupPercent);
        Assert.Equal(18.5m, saved.CostPerKg);
        Assert.Equal(24.9m, saved.PricePerKg);
        Assert.Equal(111.2m, saved.PricePerPiece);
        Assert.Equal("Neighbours", saved.Basis);
        Assert.Equal("Medium", saved.Confidence);
        Assert.Equal("7 vendas parecidas", saved.Reason);
        Assert.Equal("nota", saved.Note);
        Assert.True(saved.UsedInQuote);
        Assert.StartsWith("sales", saved.CreatedBy);
        Assert.True(saved.CreatedAt > DateTimeOffset.UtcNow.AddMinutes(-5));

        var audit = await (await admin.GetAsync("/api/audit?entity=PriceSimulation")).Read<Page<AuditOut>>();
        Assert.Contains(audit.Items, a => a.Action == "Create" && a.EntityId == id.ToString());

        // take is capped at 100 and floored at 1
        Assert.Single(await (await sales.GetAsync("/api/sales/price-simulations?take=0")).Read<List<PriceSimulationOut>>());
        Assert.True((await (await sales.GetAsync("/api/sales/price-simulations?take=100000")).Read<List<PriceSimulationOut>>()).Count <= 100);
    }

    [Fact]
    public async Task Simulations_are_validated()
    {
        var c = await api.UserAsync(UserRole.Sales);
        foreach (var bad in new[]
                 {
                     Sim() with { Thickness = 0m }, Sim() with { Length = null }, Sim() with { PricePerKg = -1m }, Sim() with { PricePerPiece = -1m }, Sim() with { CostPerKg = -1m },
                     Sim() with { PricePerKg = null }, Sim() with { Shape = "Triangle" }, Sim() with { Shape = null }, Sim() with { Diameter = null }, Sim("Oblong") with { Width = null },
                     Sim() with { Basis = " " }, Sim() with { Confidence = null }, Sim() with { Note = new string('x', 1001) }
                 })
            Assert.Equal(HttpStatusCode.BadRequest, (await c.Post("/api/sales/price-simulations", bad)).StatusCode);
        // zero prices are fine, shape is case-insensitive
        Assert.Equal(HttpStatusCode.Created, (await c.Post("/api/sales/price-simulations", Sim() with { Shape = "round", PricePerKg = 0m, PricePerPiece = null })).StatusCode);
    }

    [Fact]
    public async Task Simulations_need_the_sell_policy_and_only_their_author_or_a_manager_can_delete_them()
    {
        foreach (var role in new[] { UserRole.Reader, UserRole.Stock })
        {
            var denied = await api.UserAsync(role);
            Assert.Equal(HttpStatusCode.Forbidden, (await denied.Post("/api/sales/price-simulations", Sim())).StatusCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await denied.GetAsync("/api/sales/price-simulations")).StatusCode);
        }
        var author = await api.UserAsync(UserRole.Sales);
        var peer = await api.UserAsync(UserRole.Sales);
        async Task<int> NewAsync() => (await (await author.Post("/api/sales/price-simulations", Sim())).Read<IdOnly>()).Id;

        var id = await NewAsync();
        Assert.Equal(HttpStatusCode.Forbidden, (await peer.DeleteAsync($"/api/sales/price-simulations/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await author.DeleteAsync($"/api/sales/price-simulations/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await author.DeleteAsync($"/api/sales/price-simulations/{id}")).StatusCode);

        var forManager = await NewAsync();
        Assert.Equal(HttpStatusCode.NoContent, (await (await api.UserAsync(UserRole.SalesManager)).DeleteAsync($"/api/sales/price-simulations/{forManager}")).StatusCode);
        var forAdmin = await NewAsync();
        Assert.Equal(HttpStatusCode.NoContent, (await (await api.AdminAsync()).DeleteAsync($"/api/sales/price-simulations/{forAdmin}")).StatusCode);
    }

    [Fact]
    public async Task Data_reset_of_sales_leaves_the_saved_simulations_alone()
    {
        var admin = await api.AdminAsync();
        var id = (await (await admin.Post("/api/sales/price-simulations", Sim(customerName: "Reset Co"))).Read<IdOnly>()).Id;
        await using var db = api.NewDb();
        var service = new Ebt.Core.Maintenance.DataResetService(db, new TestUser());
        var preview = await service.PreviewAsync([Ebt.Core.Maintenance.ResetScope.Sales], CancellationToken.None);
        Assert.DoesNotContain(preview, t => t.Table == "price_simulations");
        Assert.True(await db.PriceSimulations.AnyAsync(s => s.Id == id));
    }

    private sealed class TestUser : Ebt.Core.Data.ICurrentUser
    {
        public string? Name => "test";
    }
}
