using System.Xml.Linq;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;

namespace Ebt.Tests;

/// <summary>
/// Table-driven tests of the NF-e tax math (<see cref="FiscalService.CalculateTaxes"/>) and of how <see cref="NfeXml"/> prints it.
/// ATTENTION: every expected value below is a SAMPLE CASE computed by hand from the rules documented in FISCAL.md (per-item rounding to
/// 2 decimals, half away from zero; ICMS/IPI on goods + freight; IPI joins the ICMS base for non-contributors; PIS/COFINS on goods).
/// They lock the current behaviour, they are not fiscal truth: the accountant must approve the rules and these expected values
/// before the first real NF-e.
/// </summary>
public class NfeTaxTests
{
    /// <summary>One invoice line of a sample case: goods value (qty x price already rounded), freight share and the rates in force.</summary>
    public sealed record Item(decimal Total, decimal Freight = 0m, string IcmsCst = "00", decimal Icms = 18m, decimal Reduction = 0m, string IpiCst = "50", decimal Ipi = 0m,
        string PisCst = "01", decimal Pis = 0.65m, string CofinsCst = "01", decimal Cofins = 3m);

    public sealed record Expected(decimal IcmsBase, decimal Icms, decimal Ipi, decimal Pis, decimal Cofins, decimal InvoiceTotal);

    public sealed record Case(string Name, bool Taxed, bool Contributor, Item[] Items, decimal Freight, Expected Want)
    {
        public override string ToString() => Name;
    }

    public static TheoryData<Case> Cases() => new()
    {
        new Case("contributor, no freight, IPI 5%", true, true, [new Item(1000m, Ipi: 5m)], 0m, new Expected(1000m, 180m, 50m, 6.50m, 30m, 1050m)),
        new Case("non-contributor: IPI joins the ICMS base", true, false, [new Item(1000m, Ipi: 5m)], 0m, new Expected(1050m, 189m, 50m, 6.50m, 30m, 1050m)),
        new Case("freight goes into ICMS and IPI bases", true, true, [new Item(1000m, 100m, Ipi: 5m)], 100m, new Expected(1100m, 198m, 55m, 6.50m, 30m, 1155m)),
        new Case("rounds 5.9994 to 6.00 and 1.6665 to 1.67", true, true, [new Item(33.33m, Ipi: 5m)], 0m, new Expected(33.33m, 6.00m, 1.67m, 0.22m, 1.00m, 35.00m)),
        new Case("IPI midpoint 0.525 rounds away from zero to 0.53", true, true, [new Item(10.50m, Ipi: 5m)], 0m, new Expected(10.50m, 1.89m, 0.53m, 0.07m, 0.32m, 11.03m)),
        new Case("rounding is per item, not on the sum", true, true, [new Item(10.50m, Ipi: 5m), new Item(10.50m, Ipi: 5m)], 0m, new Expected(21.00m, 3.78m, 1.06m, 0.14m, 0.64m, 22.06m)),
        new Case("ICMS CST 20 reduces the base by 33.33%", true, true, [new Item(1000m, IcmsCst: "20", Icms: 12m, Reduction: 33.33m)], 0m, new Expected(666.70m, 80.00m, 0m, 6.50m, 30m, 1000m)),
        new Case("ICMS CST 50 (suspended) and IPI CST 55 compute nothing", true, true, [new Item(500m, IcmsCst: "50", IpiCst: "55", Ipi: 5m, PisCst: "09", CofinsCst: "09")], 0m, new Expected(0m, 0m, 0m, 0m, 0m, 500m)),
        new Case("non taxed CFOP (5901) zeroes every tax", false, false, [new Item(250m, Ipi: 5m)], 0m, new Expected(0m, 0m, 0m, 0m, 0m, 250m)),
        new Case("two items, odd freight split keeps the total", true, true, [new Item(100m, Ipi: 10m), new Item(200m, Ipi: 10m)], 10m, new Expected(310m, 55.80m, 31m, 1.95m, 9m, 341m)),
    };

    internal static FiscalDocument Build(Case c)
    {
        var doc = new FiscalDocument
        {
            CfopCode = c.Taxed ? "5101" : "5901", AccessKey = Key, Protocol = "", RecipientName = "Cliente", RecipientDocument = "26133636000103", RecipientUf = "SP", Xml = "", IssuedAt = new DateTimeOffset(2026, 10, 28, 9, 0, 0, TimeSpan.FromHours(-3)),
            Series = 1, Number = 2581, Environment = SefazEnvironment.Homologation
        };
        foreach (var (i, n) in c.Items.Select((i, n) => (i, n)))
            doc.Lines.Add(new FiscalDocumentLine
            {
                Sequence = (n + 1) * 10, Code = "T1", Description = "Tubo", Ncm = "73063010", Unit = "PC", Quantity = 1m, UnitPrice = i.Total, Total = i.Total,
                IcmsCst = i.IcmsCst, IcmsPercent = i.Icms, IcmsBaseReductionPercent = i.Reduction, IpiCst = i.IpiCst, IpiPercent = i.Ipi, PisCst = i.PisCst, PisPercent = i.Pis, CofinsCst = i.CofinsCst, CofinsPercent = i.Cofins
            });
        doc.ProductsTotal = doc.Lines.Sum(l => l.Total);
        doc.FreightTotal = c.Freight;
        FiscalService.AllocateFreight(doc);
        FiscalService.CalculateTaxes(doc, Cfop(c.Taxed), c.Contributor);
        return doc;
    }

    private const string Key = "35261011222333000181550010000025811123456785";

    internal static Cfop Cfop(bool taxed) => new()
    {
        Code = taxed ? "5101" : "5901", Description = taxed ? "Venda de producao do estabelecimento" : "Remessa para industrializacao", Taxed = taxed, IcmsCst = "00", IpiCst = "50", PisCst = "01", CofinsCst = "01", IpiFramingCode = "999"
    };

    [Theory]
    [MemberData(nameof(Cases))]
    public void Totals_match_the_sample_case(Case c)
    {
        var d = Build(c);
        Assert.Equal(c.Want.IcmsBase, d.IcmsBase);
        Assert.Equal(c.Want.Icms, d.IcmsTotal);
        Assert.Equal(c.Want.Ipi, d.IpiTotal);
        Assert.Equal(c.Want.Pis, d.PisTotal);
        Assert.Equal(c.Want.Cofins, d.CofinsTotal);
        Assert.Equal(c.Want.InvoiceTotal, d.InvoiceTotal);
    }

    [Theory]
    [MemberData(nameof(Cases))]
    public void Document_totals_equal_the_sum_of_the_rounded_lines_and_have_two_decimals(Case c)
    {
        var d = Build(c);
        Assert.Equal(d.Lines.Sum(l => l.IcmsValue), d.IcmsTotal);
        Assert.Equal(d.Lines.Sum(l => l.IpiValue), d.IpiTotal);
        Assert.Equal(d.Lines.Sum(l => l.Freight), d.FreightTotal);
        foreach (var v in new[] { d.IcmsBase, d.IcmsTotal, d.IpiTotal, d.PisTotal, d.CofinsTotal, d.InvoiceTotal }.Concat(d.Lines.SelectMany(l => new[] { l.IcmsValue, l.IpiValue, l.PisValue, l.CofinsValue, l.Freight })))
            Assert.Equal(v, Math.Round(v, 2, MidpointRounding.AwayFromZero));
    }

    [Theory]
    [MemberData(nameof(Cases))]
    public void Xml_prints_the_same_values_with_fixed_decimals(Case c)
    {
        var d = Build(c);
        var xml = XDocument.Parse(NfeXml.Build(Issuer(), d, Cfop(c.Taxed), Recipient(c.Contributor), new NfeTransport(0, null, null, 0, null), interstate: false));
        XNamespace ns = "http://www.portalfiscal.inf.br/nfe";
        var tot = xml.Descendants(ns + "ICMSTot").Single();
        string T(string name) => (string)tot.Element(ns + name)!;
        Assert.Equal(c.Want.IcmsBase.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture), T("vBC"));
        Assert.Equal(c.Want.Icms.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture), T("vICMS"));
        Assert.Equal(c.Want.Ipi.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture), T("vIPI"));
        Assert.Equal(c.Want.Pis.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture), T("vPIS"));
        Assert.Equal(c.Want.Cofins.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture), T("vCOFINS"));
        Assert.Equal(c.Want.InvoiceTotal.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture), T("vNF"));
        Assert.Equal(d.Lines.Count, xml.Descendants(ns + "det").Count());
    }

    [Fact]
    public void Xml_item_prints_quantity_with_four_and_unit_price_with_ten_decimals_and_rates_with_four()
    {
        var d = Build(new Case("x", true, true, [new Item(33.33m, Ipi: 5m)], 0m, new Expected(0, 0, 0, 0, 0, 0)));
        d.Lines[0].Quantity = 3m;
        d.Lines[0].UnitPrice = 11.11m;
        var xml = NfeXml.Build(Issuer(), d, Cfop(true), Recipient(true), new NfeTransport(0, null, null, 0, null), false);
        Assert.Contains("<qCom>3.0000</qCom>", xml);
        Assert.Contains("<vUnCom>11.1100000000</vUnCom>", xml);
        Assert.Contains("<pICMS>18.0000</pICMS>", xml);
        Assert.Contains("<pPIS>0.6500</pPIS>", xml);
        Assert.Contains("<pCOFINS>3.0000</pCOFINS>", xml);
        Assert.Contains("<pIPI>5.0000</pIPI>", xml);
    }

    [Fact]
    public void Unsupported_cst_blocks_the_xml_with_a_422()
    {
        var d = Build(new Case("x", true, true, [new Item(100m)], 0m, new Expected(0, 0, 0, 0, 0, 0)));
        d.Lines[0].IcmsCst = "10";
        var e = Assert.Throws<FiscalException>(() => NfeXml.Build(Issuer(), d, Cfop(true), Recipient(true), new NfeTransport(0, null, null, 0, null), false));
        Assert.Equal(422, e.Status);
    }

    internal static FiscalSettings Issuer() => new()
    {
        CompanyName = "EBT Tubos Ltda", TradeName = "EBT", Cnpj = "11222333000181", StateRegistration = "111222333444", TaxRegime = 3, Street = "Rua das Industrias", Number = "10", District = "Distrito", City = "Embu das Artes",
        CityIbgeCode = "3515004", Uf = "SP", ZipCode = "06800000", Phone = "1144444444"
    };

    internal static NfeParty Recipient(bool contributor) =>
        new("Cliente Teste", "26133636000103", contributor ? "148061942112" : null, contributor, "Av. Brasil", "100", null, "Centro", "Embu", "3515004", "SP", "06800000", "compras@cliente.com", null);
}
