using System.Net;
using Ebt.Api.Endpoints;
using Ebt.Core.Entities;

namespace Ebt.Tests;

[Collection("api")]
public class SearchTests(ApiFixture api)
{
    private static string Code(string prefix, int length = 12) => $"{prefix}{Guid.NewGuid():N}"[..length].ToUpper();

    [Fact]
    public async Task Search_returns_grouped_hits_capped_by_take()
    {
        var admin = await api.AdminAsync();
        var tag = Code("ZQ", 8);
        for (var i = 0; i < 3; i++)
            (await admin.Post("/api/customers", new CustomerIn($"Cliente {tag} {i}", null, null, ConsumerType.Normal))).EnsureSuccessStatusCode();
        (await admin.Post("/api/products", new ProductIn(tag + "P", "Tubo " + tag, ProductKind.Part, TubeShape.Circular, 25.4m, null, null, 1.5m, 1000m, null, null, "73063010", "PC", 50, false, null, null))).EnsureSuccessStatusCode();

        var all = await (await admin.GetAsync($"/api/search?q={tag}")).Read<SearchOut>();
        Assert.Equal(["products", "customers"], all.Groups.Select(g => g.Key));
        Assert.Equal(3, all.Groups.Single(g => g.Key == "customers").Hits.Count);
        Assert.Contains(tag, all.Groups.Single(g => g.Key == "products").Hits.Single().Title);

        var capped = await (await admin.GetAsync($"/api/search?q={tag}&take=2")).Read<SearchOut>();
        Assert.Equal(2, capped.Groups.Single(g => g.Key == "customers").Hits.Count);
    }

    [Fact]
    public async Task Search_ignores_short_terms_and_requires_sign_in()
    {
        var admin = await api.AdminAsync();
        var res = await (await admin.GetAsync("/api/search?q=a")).Read<SearchOut>();
        Assert.Empty(res.Groups);
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().GetAsync("/api/search?q=abc")).StatusCode);
    }

    [Fact]
    public async Task Search_reader_role_can_search()
    {
        var reader = await api.UserAsync(UserRole.Reader);
        Assert.Equal(HttpStatusCode.OK, (await reader.GetAsync("/api/search?q=abc")).StatusCode);
    }
}
