using System.Reflection;
using System.Xml;
using System.Xml.Linq;
using System.Xml.Schema;

namespace Ebt.Core.Fiscal;

/// <summary>
/// Validates fiscal XML against the official layout 4.00 XSDs embedded from <c>Fiscal/Schemas</c> (see the README there for the package version).
/// A failure becomes a 422 <see cref="FiscalException"/> that names the offending element, so nothing malformed ever reaches SEFAZ.
/// </summary>
public static class NfeSchema
{
    private const string Prefix = "Ebt.Core.Fiscal.Schemas.";
    private const int MaxErrors = 5;

    private static readonly Lazy<XmlSchemaSet> Nfe = new(() => Load("nfe_v4.00.xsd"));
    private static readonly Lazy<XmlSchemaSet> Inutilizacao = new(() => Load("inutNFe_v4.00.xsd"));

    /// <summary>Validates an unsigned <c>NFe</c> element.</summary>
    public static void ValidateNfe(string xml) => Validate(WithPlaceholderSignature(xml), Nfe.Value, "NF-e");

    /// <summary>The schema requires a <c>Signature</c>, but the XML is signed only at transmission; a structurally valid placeholder stands in for it.</summary>
    private static string WithPlaceholderSignature(string xml)
    {
        XElement root;
        try { root = XElement.Parse(xml); }
        catch (XmlException) { return xml; }
        XNamespace ds = "http://www.w3.org/2000/09/xmldsig#";
        if (root.Element(ds + "Signature") is not null) return xml;
        root.Add(new XElement(ds + "Signature",
            new XElement(ds + "SignedInfo",
                new XElement(ds + "CanonicalizationMethod", new XAttribute("Algorithm", "http://www.w3.org/TR/2001/REC-xml-c14n-20010315")),
                new XElement(ds + "SignatureMethod", new XAttribute("Algorithm", "http://www.w3.org/2000/09/xmldsig#rsa-sha1")),
                new XElement(ds + "Reference", new XAttribute("URI", "#" + (string?)root.Element(root.Name.Namespace + "infNFe")?.Attribute("Id")),
                    new XElement(ds + "Transforms",
                        new XElement(ds + "Transform", new XAttribute("Algorithm", "http://www.w3.org/2000/09/xmldsig#enveloped-signature")),
                        new XElement(ds + "Transform", new XAttribute("Algorithm", "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"))),
                    new XElement(ds + "DigestMethod", new XAttribute("Algorithm", "http://www.w3.org/2000/09/xmldsig#sha1")), new XElement(ds + "DigestValue", "AAAAAAAAAAAAAAAAAAAAAAAAAAA="))),
            new XElement(ds + "SignatureValue", "AAAA"),
            new XElement(ds + "KeyInfo", new XElement(ds + "X509Data", new XElement(ds + "X509Certificate", "AAAA")))));
        return root.ToString(SaveOptions.DisableFormatting);
    }

    /// <summary>Validates an <c>inutNFe</c> element.</summary>
    public static void ValidateInutilizacao(string xml) => Validate(xml, Inutilizacao.Value, "inutilização");

    /// <summary>Returns the validation errors (at most five, with the element path); empty when the XML is valid.</summary>
    public static IReadOnlyList<string> Check(string xml, XmlSchemaSet schemas)
    {
        var errors = new List<string>();
        XDocument doc;
        try { doc = XDocument.Parse(xml); }
        catch (XmlException e) { return [$"XML malformado: {e.Message}"]; }
        doc.Validate(schemas, (sender, e) =>
        {
            if (errors.Count >= MaxErrors) return;
            var where = sender is XObject o ? Path(o) : "";
            errors.Add(where.Length > 0 ? $"{where}: {e.Message}" : e.Message);
        });
        return errors;
    }

    private static void Validate(string xml, XmlSchemaSet schemas, string what)
    {
        var errors = Check(xml, schemas);
        if (errors.Count > 0)
            throw FiscalException.Blocked($"The {what} XML does not match the official layout 4.00 (nothing was sent to SEFAZ): {string.Join(" | ", errors)}");
    }

    private static string Path(XObject o)
    {
        var parts = new List<string>();
        for (XObject? n = o is XAttribute a ? a.Parent : o; n is XElement e; n = e.Parent)
        {
            var nItem = e.Name.LocalName == "det" ? e.Attribute("nItem")?.Value : null;
            parts.Add(nItem is null ? e.Name.LocalName : $"{e.Name.LocalName}[{nItem}]");
        }
        parts.Reverse();
        return string.Join("/", parts);
    }

    private static XmlSchemaSet Load(string entry)
    {
        var resolver = new EmbeddedResolver();
        var set = new XmlSchemaSet { XmlResolver = resolver };
        using var stream = Open(entry) ?? throw new InvalidOperationException($"Embedded schema {entry} not found");
        using var reader = XmlReader.Create(stream, new XmlReaderSettings { XmlResolver = resolver, DtdProcessing = DtdProcessing.Ignore }, EmbeddedResolver.Root + entry);
        set.Add(null, reader);
        set.Compile();
        return set;
    }

    private static Stream? Open(string file) => typeof(NfeSchema).Assembly.GetManifestResourceStream(Prefix + file);

    /// <summary>Serves the XSDs (and their includes) from the assembly; never touches disk or network.</summary>
    private sealed class EmbeddedResolver : XmlResolver
    {
        public const string Root = "embedded:///";

        public override Uri ResolveUri(Uri? baseUri, string? relativeUri) => new(Root + System.IO.Path.GetFileName(relativeUri ?? ""));

        public override object? GetEntity(Uri absoluteUri, string? role, Type? ofObjectToReturn) =>
            Open(System.IO.Path.GetFileName(absoluteUri.AbsolutePath)) ?? throw new FileNotFoundException($"Embedded schema {absoluteUri} not found");
    }
}
