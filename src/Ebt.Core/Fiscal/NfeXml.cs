using System.Globalization;
using System.Text;
using System.Xml.Linq;
using Ebt.Core.Entities;

namespace Ebt.Core.Fiscal;

public static class NfeKey
{
    public static readonly IReadOnlyDictionary<string, int> UfCodes = new Dictionary<string, int>
    {
        ["RO"] = 11, ["AC"] = 12, ["AM"] = 13, ["RR"] = 14, ["PA"] = 15, ["AP"] = 16, ["TO"] = 17, ["MA"] = 21, ["PI"] = 22, ["CE"] = 23, ["RN"] = 24, ["PB"] = 25, ["PE"] = 26,
        ["AL"] = 27, ["SE"] = 28, ["BA"] = 29, ["MG"] = 31, ["ES"] = 32, ["RJ"] = 33, ["SP"] = 35, ["PR"] = 41, ["SC"] = 42, ["RS"] = 43, ["MS"] = 50, ["MT"] = 51, ["GO"] = 52, ["DF"] = 53
    };

    /// <summary>44-digit access key: cUF + AAMM + CNPJ + mod + serie + nNF + tpEmis + cNF + DV.</summary>
    public static string Build(int ufCode, DateTimeOffset issuedAt, string cnpj, int series, int number, string codeNumber)
    {
        var body = string.Create(CultureInfo.InvariantCulture, $"{ufCode:00}{issuedAt:yyMM}{cnpj}55{series:000}{number:000000000}1{codeNumber}");
        if (body.Length != 43 || !body.All(char.IsDigit)) throw new ArgumentException($"Invalid access key body '{body}'");
        return body + CheckDigit(body);
    }

    /// <summary>Modulo 11 with weights 2..9 from the right.</summary>
    public static int CheckDigit(string key43)
    {
        var sum = 0;
        var weight = 2;
        for (var i = key43.Length - 1; i >= 0; i--)
        {
            sum += (key43[i] - '0') * weight;
            weight = weight == 9 ? 2 : weight + 1;
        }
        var rest = sum % 11;
        return rest < 2 ? 0 : 11 - rest;
    }

    /// <summary>cNF: 8 random digits that must differ from the NF number.</summary>
    public static string NewCodeNumber(int number)
    {
        string code;
        do code = Random.Shared.Next(0, 100_000_000).ToString("00000000", CultureInfo.InvariantCulture);
        while (int.Parse(code, CultureInfo.InvariantCulture) == number);
        return code;
    }
}

/// <summary>Builds the NF-e 4.00 XML (unsigned <c>NFe</c> element). Signing and transmission belong to <see cref="ISefazClient"/>.</summary>
public static class NfeXml
{
    public const string HomologationText = "NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL";
    private static readonly XNamespace Ns = "http://www.portalfiscal.inf.br/nfe";
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    public static string Build(FiscalSettings issuer, FiscalDocument doc, Cfop cfop, NfeParty recipient, NfeTransport transport, bool interstate)
    {
        var key = doc.AccessKey;
        var local = doc.IssuedAt.ToOffset(TimeSpan.FromHours(-3));
        var ide = E("ide",
            E("cUF", key[..2]), E("cNF", key.Substring(35, 8)), E("natOp", Cut(cfop.Description, 60)), E("mod", "55"), E("serie", doc.Series.ToString(Inv)), E("nNF", doc.Number.ToString(Inv)),
            E("dhEmi", local.ToString("yyyy-MM-dd'T'HH:mm:sszzz", Inv)), E("tpNF", "1"), E("idDest", interstate ? "2" : "1"), E("cMunFG", issuer.CityIbgeCode), E("tpImp", "1"), E("tpEmis", "1"),
            E("cDV", key[43..]), E("tpAmb", ((int)doc.Environment).ToString(Inv)), E("finNFe", "1"), E("indFinal", "0"), E("indPres", "9"), E("procEmi", "0"), E("verProc", "SiderGest 1.0"));

        var emit = E("emit", E("CNPJ", issuer.Cnpj), E("xNome", Cut(issuer.CompanyName, 60)), OptE("xFant", Cut(issuer.TradeName, 60)),
            E("enderEmit", E("xLgr", Cut(issuer.Street, 60)), E("nro", Cut(issuer.Number, 60)), OptE("xCpl", Cut(issuer.Complement, 60)), E("xBairro", Cut(issuer.District, 60)), E("cMun", issuer.CityIbgeCode),
                E("xMun", Cut(issuer.City, 60)), E("UF", issuer.Uf), E("CEP", Digits(issuer.ZipCode)), E("cPais", "1058"), E("xPais", "BRASIL"), OptE("fone", Digits(issuer.Phone))),
            E("IE", Digits(issuer.StateRegistration)), E("CRT", issuer.TaxRegime.ToString(Inv)));

        var docDigits = Digits(recipient.Document);
        var hasIe = recipient.IcmsContributor && Digits(recipient.StateRegistration) is { Length: > 0 };
        var dest = E("dest", E(docDigits.Length == 11 ? "CPF" : "CNPJ", docDigits), E("xNome", doc.Environment == SefazEnvironment.Homologation ? HomologationText : Cut(recipient.Name, 60)),
            E("enderDest", E("xLgr", Cut(recipient.Street, 60)), E("nro", Cut(recipient.Number, 60)), OptE("xCpl", Cut(recipient.Complement, 60)), E("xBairro", Cut(recipient.District, 60)), E("cMun", recipient.CityIbgeCode),
                E("xMun", Cut(recipient.City, 60)), E("UF", recipient.Uf), E("CEP", Digits(recipient.ZipCode)), E("cPais", "1058"), E("xPais", "BRASIL"), OptE("fone", Digits(recipient.Phone))),
            E("indIEDest", hasIe ? "1" : "9"), hasIe ? E("IE", Digits(recipient.StateRegistration)) : null, OptE("email", Cut(recipient.Email, 60)));

        var details = doc.Lines.OrderBy(l => l.Sequence).Select((l, n) => Detail(doc, cfop, l, l.Freight, n + 1));

        var totals = E("total", E("ICMSTot", E("vBC", M(doc.IcmsBase)), E("vICMS", M(doc.IcmsTotal)), E("vICMSDeson", M(0)), E("vFCP", M(0)), E("vBCST", M(0)), E("vST", M(0)), E("vFCPST", M(0)), E("vFCPSTRet", M(0)),
            E("vProd", M(doc.ProductsTotal)), E("vFrete", M(doc.FreightTotal)), E("vSeg", M(0)), E("vDesc", M(0)), E("vII", M(0)), E("vIPI", M(doc.IpiTotal)), E("vIPIDevol", M(0)), E("vPIS", M(doc.PisTotal)),
            E("vCOFINS", M(doc.CofinsTotal)), E("vOutro", M(0)), E("vNF", M(doc.InvoiceTotal))));

        var transp = E("transp", E("modFrete", transport.FreightMode.ToString(Inv)),
            Cut(transport.Carrier, 60) is { Length: > 0 } carrier ? E("transporta", E("xNome", carrier)) : null,
            Digits(transport.VehiclePlate, letters: true) is { Length: > 0 } plate ? E("veicTransp", E("placa", plate), E("UF", issuer.Uf)) : null,
            transport.Packages > 0 ? E("vol", E("qVol", transport.Packages.ToString(Inv)), transport.GrossWeightKg is { } kg ? E("pesoB", kg.ToString("0.000", Inv)) : null) : null);

        var cobr = doc.Installments.Count == 0 ? null : E("cobr", E("fat", E("nFat", doc.Number.ToString("000000000", Inv)), E("vOrig", M(doc.InvoiceTotal)), E("vLiq", M(doc.InvoiceTotal))),
            doc.Installments.OrderBy(i => i.Sequence).Select(i => E("dup", E("nDup", i.Sequence.ToString("000", Inv)), E("dVenc", i.DueDate.ToString("yyyy-MM-dd", Inv)), E("vDup", M(i.Amount)))));

        var pag = E("pag", doc.Installments.Count > 0 ? E("detPag", E("tPag", "14"), E("vPag", M(doc.InvoiceTotal))) : E("detPag", E("tPag", "90"), E("vPag", M(0))));
        var info = OptE("infCpl", Cut(doc.AdditionalInfo, 2000)) is { } cpl ? E("infAdic", cpl) : null;

        var infNFe = E("infNFe", ide, emit, dest, details, totals, transp, cobr, pag, info);
        infNFe.SetAttributeValue("versao", "4.00");
        infNFe.SetAttributeValue("Id", "NFe" + key);
        var root = new XElement(Ns + "NFe", infNFe);
        return root.ToString(SaveOptions.DisableFormatting);
    }

    private static XElement Detail(FiscalDocument doc, Cfop cfop, FiscalDocumentLine l, decimal freight, int item)
    {
        var prod = E("prod", E("cProd", Cut(l.Code, 60)), E("cEAN", "SEM GTIN"), E("xProd", Cut(l.Description, 120)), E("NCM", l.Ncm), E("CFOP", doc.CfopCode), E("uCom", l.Unit), E("qCom", l.Quantity.ToString("0.0000", Inv)),
            E("vUnCom", l.UnitPrice.ToString("0.0000000000", Inv)), E("vProd", M(l.Total)), E("cEANTrib", "SEM GTIN"), E("uTrib", l.Unit), E("qTrib", l.Quantity.ToString("0.0000", Inv)),
            E("vUnTrib", l.UnitPrice.ToString("0.0000000000", Inv)), freight > 0 ? E("vFrete", M(freight)) : null, E("indTot", "1"));
        var imposto = E("imposto", Icms(l), Ipi(l, cfop), Pis(l), Cofins(l));
        var det = E("det", prod, imposto);
        det.SetAttributeValue("nItem", item.ToString(Inv));
        return det;
    }

    private static XElement Icms(FiscalDocumentLine l)
    {
        var group = l.IcmsCst switch
        {
            "00" => E("ICMS00", E("orig", "0"), E("CST", "00"), E("modBC", "3"), E("vBC", M(l.IcmsBase)), E("pICMS", P(l.IcmsPercent)), E("vICMS", M(l.IcmsValue))),
            "20" => E("ICMS20", E("orig", "0"), E("CST", "20"), E("modBC", "3"), E("pRedBC", P(l.IcmsBaseReductionPercent)), E("vBC", M(l.IcmsBase)), E("pICMS", P(l.IcmsPercent)), E("vICMS", M(l.IcmsValue))),
            "40" or "41" or "50" => E("ICMS40", E("orig", "0"), E("CST", l.IcmsCst)),
            "51" => E("ICMS51", E("orig", "0"), E("CST", "51")),
            _ => throw FiscalException.Blocked($"ICMS CST {l.IcmsCst} (item {l.Sequence}) is not supported; supported: 00, 20, 40, 41, 50, 51")
        };
        return E("ICMS", group);
    }

    private static XElement Ipi(FiscalDocumentLine l, Cfop cfop)
    {
        var inner = l.IpiCst switch
        {
            "00" or "49" or "50" or "99" => E("IPITrib", E("CST", l.IpiCst), E("vBC", M(l.IpiBase)), E("pIPI", P(l.IpiPercent)), E("vIPI", M(l.IpiValue))),
            "01" or "02" or "03" or "04" or "05" or "51" or "52" or "53" or "54" or "55" => E("IPINT", E("CST", l.IpiCst)),
            _ => throw FiscalException.Blocked($"IPI CST {l.IpiCst} (item {l.Sequence}) is not supported")
        };
        return E("IPI", E("cEnq", cfop.IpiFramingCode), inner);
    }

    private static XElement Pis(FiscalDocumentLine l) => E("PIS", l.PisCst switch
    {
        "01" or "02" => E("PISAliq", E("CST", l.PisCst), E("vBC", M(l.Total)), E("pPIS", P(l.PisPercent)), E("vPIS", M(l.PisValue))),
        "04" or "05" or "06" or "07" or "08" or "09" => E("PISNT", E("CST", l.PisCst)),
        _ => throw FiscalException.Blocked($"PIS CST {l.PisCst} (item {l.Sequence}) is not supported")
    });

    private static XElement Cofins(FiscalDocumentLine l) => E("COFINS", l.CofinsCst switch
    {
        "01" or "02" => E("COFINSAliq", E("CST", l.CofinsCst), E("vBC", M(l.Total)), E("pCOFINS", P(l.CofinsPercent)), E("vCOFINS", M(l.CofinsValue))),
        "04" or "05" or "06" or "07" or "08" or "09" => E("COFINSNT", E("CST", l.CofinsCst)),
        _ => throw FiscalException.Blocked($"COFINS CST {l.CofinsCst} (item {l.Sequence}) is not supported")
    });

    private static XElement E(string name, params object?[] content) => new(Ns + name, content);
    private static XElement? OptE(string name, string? value) => string.IsNullOrWhiteSpace(value) ? null : E(name, value);
    private static string M(decimal v) => v.ToString("0.00", Inv);
    private static string P(decimal v) => v.ToString("0.0000", Inv);

    private static string Digits(string? s, bool letters = false) => string.Concat((s ?? "").Where(c => char.IsDigit(c) || letters && char.IsLetter(c))).ToUpperInvariant();

    /// <summary>Collapses whitespace and truncates to the NF-e field size.</summary>
    private static string Cut(string? s, int max)
    {
        if (string.IsNullOrWhiteSpace(s)) return "";
        var sb = new StringBuilder();
        foreach (var part in s.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)) sb.Append(sb.Length == 0 ? "" : " ").Append(part);
        return sb.Length <= max ? sb.ToString() : sb.ToString(0, max).TrimEnd();
    }
}
