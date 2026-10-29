using System.Security.Cryptography.X509Certificates;
using System.Security.Cryptography.Xml;
using System.Xml;

namespace Ebt.Core.Fiscal;

/// <summary>XMLDSig as the NF-e manual requires: enveloped signature, C14N, RSA-SHA1 and SHA-1 digest, certificate in KeyInfo.</summary>
public static class NfeSigner
{
    public const string Ns = "http://www.portalfiscal.inf.br/nfe";

    /// <summary>Signs the <c>NFe</c> element of the document: the signature becomes its last child, referencing infNFe.</summary>
    public static string SignNfe(string nfeXml, X509Certificate2 cert) => Sign(nfeXml, "NFe", "infNFe", cert);

    /// <summary>Signs an event element (<c>evento</c>) of the document, referencing infEvento.</summary>
    public static string SignEvent(string eventXml, X509Certificate2 cert) => Sign(eventXml, "evento", "infEvento", cert);

    private static string Sign(string xml, string rootName, string signedName, X509Certificate2 cert)
    {
        var doc = new XmlDocument { PreserveWhitespace = true };
        doc.LoadXml(xml);
        var root = doc.DocumentElement ?? throw new InvalidOperationException("Empty XML");
        if (root.LocalName != rootName) throw new InvalidOperationException($"Expected <{rootName}> as root, found <{root.LocalName}>");
        var target = (XmlElement?)root.GetElementsByTagName(signedName, Ns)[0] ?? throw new InvalidOperationException($"<{signedName}> not found");
        var id = target.GetAttribute("Id");
        if (id.Length == 0) throw new InvalidOperationException($"<{signedName}> has no Id");

        using var key = cert.GetRSAPrivateKey() ?? throw new InvalidOperationException("The certificate has no RSA private key");
        var signed = new SignedXml(doc) { SigningKey = key };
        signed.SignedInfo!.CanonicalizationMethod = SignedXml.XmlDsigC14NTransformUrl;
        signed.SignedInfo.SignatureMethod = SignedXml.XmlDsigRSASHA1Url;
        var reference = new Reference("#" + id) { DigestMethod = SignedXml.XmlDsigSHA1Url };
        reference.AddTransform(new XmlDsigEnvelopedSignatureTransform());
        reference.AddTransform(new XmlDsigC14NTransform());
        signed.AddReference(reference);
        var info = new KeyInfo();
        info.AddClause(new KeyInfoX509Data(cert));
        signed.KeyInfo = info;
        signed.ComputeSignature();
        root.AppendChild(doc.ImportNode(signed.GetXml(), true));
        return doc.OuterXml;
    }

    /// <summary>Checks the signature of a document produced by this class (used by tests and diagnostics).</summary>
    public static bool Verify(string signedXml, X509Certificate2 cert)
    {
        var doc = new XmlDocument { PreserveWhitespace = true };
        doc.LoadXml(signedXml);
        var node = doc.GetElementsByTagName("Signature", SignedXml.XmlDsigNamespaceUrl)[0] as XmlElement ?? throw new InvalidOperationException("No signature");
        var signed = new SignedXml(doc);
        signed.LoadXml(node);
        return signed.CheckSignature(cert, true);
    }
}
