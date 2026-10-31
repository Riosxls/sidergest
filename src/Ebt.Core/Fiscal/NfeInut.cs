using System.Globalization;
using System.Xml.Linq;
using Ebt.Core.Entities;

namespace Ebt.Core.Fiscal;

/// <summary>Builds the unsigned <c>inutNFe</c> request (layout 4.00) that gives up a range of NF numbers for good.</summary>
public static class NfeInut
{
    private static readonly XNamespace Ns = "http://www.portalfiscal.inf.br/nfe";
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    public static string Build(FiscalSettings issuer, DateTimeOffset now, int series, int from, int to, string reason, SefazEnvironment environment)
    {
        var uf = NfeKey.UfCodes[issuer.Uf];
        var year = now.ToOffset(TimeSpan.FromHours(-3)).ToString("yy", Inv);
        var id = string.Create(Inv, $"ID{uf:00}{year}{issuer.Cnpj}55{series:000}{from:000000000}{to:000000000}");
        var info = new XElement(Ns + "infInut", new XAttribute("Id", id),
            new XElement(Ns + "tpAmb", ((int)environment).ToString(Inv)), new XElement(Ns + "xServ", "INUTILIZAR"), new XElement(Ns + "cUF", uf.ToString("00", Inv)), new XElement(Ns + "ano", year),
            new XElement(Ns + "CNPJ", issuer.Cnpj), new XElement(Ns + "mod", "55"), new XElement(Ns + "serie", series.ToString(Inv)), new XElement(Ns + "nNFIni", from.ToString(Inv)),
            new XElement(Ns + "nNFFin", to.ToString(Inv)), new XElement(Ns + "xJust", reason));
        return new XElement(Ns + "inutNFe", new XAttribute("versao", "4.00"), info).ToString(SaveOptions.DisableFormatting);
    }
}
