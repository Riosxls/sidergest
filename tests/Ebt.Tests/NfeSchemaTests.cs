using Ebt.Core.Fiscal;

namespace Ebt.Tests;

public class NfeSchemaTests
{
    private static NfeTaxTests.Case First() => (NfeTaxTests.Case)NfeTaxTests.Cases().Cast<object[]>().First()[0];
    private static readonly NfeTransport Transport = new(0, "Transportes Rapido", "ABC1D23", 2, 10.5m);

    private static string Xml(NfeTaxTests.Case c, bool withInstallments = false)
    {
        var d = NfeTaxTests.Build(c);
        if (withInstallments) d.Installments.Add(new Ebt.Core.Entities.FiscalInstallment { Sequence = 1, DueDate = new DateOnly(2026, 11, 25), Amount = d.InvoiceTotal });
        d.AdditionalInfo = "PV-1 | OF-2";
        return NfeXml.Build(NfeTaxTests.Issuer(), d, NfeTaxTests.Cfop(c.Taxed), NfeTaxTests.Recipient(c.Contributor), Transport, interstate: false);
    }

    [Theory]
    [MemberData(nameof(NfeTaxTests.Cases), MemberType = typeof(NfeTaxTests))]
    public void Generated_xml_is_valid_against_the_official_layout(NfeTaxTests.Case c)
    {
        NfeSchema.ValidateNfe(Xml(c));
        NfeSchema.ValidateNfe(Xml(c, withInstallments: true));
    }

    [Fact]
    public void Invalid_xml_fails_with_a_readable_422_naming_the_element()
    {
        var xml = Xml(First()).Replace("<CEP>06800000</CEP>", "<CEP>123</CEP>");
        var e = Assert.Throws<FiscalException>(() => NfeSchema.ValidateNfe(xml));
        Assert.Equal(422, e.Status);
        Assert.Contains("official layout 4.00", e.Message);
        Assert.Contains("CEP", e.Message);
        Assert.Contains("nothing was sent to SEFAZ", e.Message);
    }

    [Fact]
    public void Missing_required_element_is_reported()
    {
        var xml = Xml(First()).Replace("<NCM>73063010</NCM>", "");
        var e = Assert.Throws<FiscalException>(() => NfeSchema.ValidateNfe(xml));
        Assert.Contains("det[1]", e.Message);
    }
}

public class NfeInutTests
{
    [Fact]
    public void Inutilization_xml_is_valid_against_the_official_layout()
    {
        var xml = NfeInut.Build(NfeTaxTests.Issuer(), new DateTimeOffset(2026, 10, 31, 9, 0, 0, TimeSpan.FromHours(-3)), 1, 2581, 2583, "Numeracao pulada por falha de comunicacao", Ebt.Core.Entities.SefazEnvironment.Homologation);
        Assert.Contains("Id=\"ID352611222333000181550010000025810000025" + "83\"", xml);
        NfeSchema.ValidateInutilizacao(xml);
    }

    [Fact]
    public void Short_reason_violates_the_layout()
    {
        var xml = NfeInut.Build(NfeTaxTests.Issuer(), DateTimeOffset.UtcNow, 1, 5, 5, "curto", Ebt.Core.Entities.SefazEnvironment.Homologation);
        Assert.Equal(422, Assert.Throws<FiscalException>(() => NfeSchema.ValidateInutilizacao(xml)).Status);
    }
}
