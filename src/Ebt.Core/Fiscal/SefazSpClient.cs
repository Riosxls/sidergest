using System.Globalization;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Xml.Linq;
using Ebt.Core.Entities;

namespace Ebt.Core.Fiscal;

public sealed class SefazOptions
{
    /// <summary>"Stub" (default, simulated) or "Sp" (real SEFAZ-SP).</summary>
    public string Mode { get; set; } = "Stub";
    /// <summary>PFX/P12 file with the A1 certificate of the issuer.</summary>
    public string? CertificatePath { get; set; }
    /// <summary>Set through the environment (Fiscal__Sefaz__CertificatePassword); never store it in a file.</summary>
    public string? CertificatePassword { get; set; }
    public int TimeoutSeconds { get; set; } = 30;
    /// <summary>How many times to ask for the result when SEFAZ answers that the batch is still being processed.</summary>
    public int PollAttempts { get; set; } = 5;
    public int PollDelayMilliseconds { get; set; } = 2000;
    public bool IsReal => string.Equals(Mode, "Sp", StringComparison.OrdinalIgnoreCase);

    public X509Certificate2 LoadCertificate()
    {
        if (string.IsNullOrWhiteSpace(CertificatePath) || !File.Exists(CertificatePath))
            throw new InvalidOperationException($"Fiscal:Sefaz:CertificatePath not found: '{CertificatePath}'");
        var cert = X509CertificateLoader.LoadPkcs12FromFile(CertificatePath, CertificatePassword, X509KeyStorageFlags.EphemeralKeySet);
        if (!cert.HasPrivateKey) throw new InvalidOperationException("The A1 certificate has no private key");
        if (cert.NotAfter < DateTime.Now) throw new InvalidOperationException($"The A1 certificate expired on {cert.NotAfter:dd/MM/yyyy}");
        return cert;
    }
}

/// <summary>
/// SEFAZ-SP client: NF-e 4.00 over SOAP 1.2 with mutual TLS (NFeAutorizacao4, NFeRetAutorizacao4, NFeRecepcaoEvento4).
/// UNTESTED against the real webservice: it was written from the SEFAZ manual and is exercised only with canned responses.
/// Validate in homologation before trusting it.
/// </summary>
public sealed class SefazSpClient : ISefazClient, IDisposable
{
    private const string Nfe = NfeSigner.Ns;
    private const string Wsdl = "http://www.portalfiscal.inf.br/nfe/wsdl/";
    private static readonly XNamespace N = Nfe;

    private readonly SefazOptions options;
    private readonly X509Certificate2 certificate;
    private readonly HttpClient http;
    private readonly bool ownsHttp;

    /// <param name="handler">Test seam. When null, a handler presenting <paramref name="certificate"/> as client certificate is created.</param>
    public SefazSpClient(SefazOptions options, X509Certificate2 certificate, HttpMessageHandler? handler = null)
    {
        this.options = options;
        this.certificate = certificate;
        if (handler is null)
        {
            var h = new HttpClientHandler();
            h.ClientCertificates.Add(certificate);
            handler = h;
        }
        http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds) };
        ownsHttp = true;
    }

    public bool IsSimulated => false;

    public static string Host(SefazEnvironment env) => env == SefazEnvironment.Production ? "nfe.fazenda.sp.gov.br" : "homologacao.nfe.fazenda.sp.gov.br";

    public async Task<SefazResult> AuthorizeAsync(string accessKey, string xml, SefazEnvironment environment, CancellationToken ct)
    {
        var signed = NfeSigner.SignNfe(xml, certificate);
        var batch = $"{DateTime.UtcNow:yyMMddHHmmss}{Random.Shared.Next(0, 1000):000}";
        var body = $"<enviNFe xmlns=\"{Nfe}\" versao=\"4.00\"><idLote>{batch}</idLote><indSinc>1</indSinc>{StripDeclaration(signed)}</enviNFe>";
        var ret = await CallAsync(environment, "nfeautorizacao4", "NFeAutorizacao4", "nfeAutorizacaoLote", body, accessKey, ct);

        for (var attempt = 0; ret.Descendants(N + "protNFe").FirstOrDefault() is null && Text(ret, "cStat") is "103" or "105" && attempt < options.PollAttempts; attempt++)
        {
            await Task.Delay(options.PollDelayMilliseconds, ct);
            var receipt = Text(ret, "nRec") ?? throw new FiscalException(502, $"SEFAZ accepted the batch without a receipt number (key {accessKey})");
            var consult = $"<consReciNFe xmlns=\"{Nfe}\" versao=\"4.00\"><tpAmb>{(int)environment}</tpAmb><nRec>{receipt}</nRec></consReciNFe>";
            ret = await CallAsync(environment, "nferetautorizacao4", "NFeRetAutorizacao4", "nfeRetAutorizacaoLote", consult, accessKey, ct);
        }

        var prot = ret.Descendants(N + "protNFe").FirstOrDefault();
        if (prot is null) return new SefazResult(false, Text(ret, "cStat") ?? "?", Text(ret, "xMotivo") ?? "SEFAZ answered without a protocol", null, false);
        var info = prot.Element(N + "infProt") ?? throw new FiscalException(502, $"Malformed protNFe from SEFAZ (key {accessKey})");
        var status = (string?)info.Element(N + "cStat") ?? "?";
        var message = (string?)info.Element(N + "xMotivo") ?? "";
        // 100 authorized; 150 authorized outside the deadline. 110/205/301/302/303 are denied NFs and count as failures.
        if (status is not ("100" or "150")) return new SefazResult(false, status, message, null, false);
        var protocol = (string?)info.Element(N + "nProt") ?? throw new FiscalException(502, $"SEFAZ authorized without nProt (key {accessKey})");
        var proc = new XElement(N + "nfeProc", new XAttribute("versao", "4.00"), XElement.Parse(StripDeclaration(signed)), prot);
        return new SefazResult(true, status, message, protocol, false, proc.ToString(SaveOptions.DisableFormatting));
    }

    public Task<SefazResult> CancelAsync(string accessKey, string authorizationProtocol, string reason, SefazEnvironment environment, CancellationToken ct) =>
        SendEventAsync(accessKey, "110111", 1, environment, [new XElement(N + "descEvento", "Cancelamento"), new XElement(N + "nProt", authorizationProtocol), new XElement(N + "xJust", reason)], ct);

    /// <summary>CC-e (NT 2011.004): descEvento, xCorrecao and the fixed xCondUso text. UNTESTED against the real webservice.</summary>
    public Task<SefazResult> CorrectAsync(string accessKey, int sequence, string text, SefazEnvironment environment, CancellationToken ct) =>
        SendEventAsync(accessKey, "110110", sequence, environment, [new XElement(N + "descEvento", "Carta de Correção"), new XElement(N + "xCorrecao", text), new XElement(N + "xCondUso", CorrectionTerms)], ct);

    /// <summary>Fixed "condição de uso" text that must accompany every CC-e (NT 2011.004).</summary>
    public const string CorrectionTerms = "A Carta de Correção é disciplinada pelo § 1º-A do art. 7º do Convênio S/N, de 15 de dezembro de 1970 e pode ser utilizada para regularização de erro ocorrido na emissão de documento fiscal, desde que o erro não esteja relacionado com: I - as variáveis que determinam o valor do imposto tais como: base de cálculo, alíquota, diferença de preço, quantidade, valor da operação ou da prestação; II - a correção de dados cadastrais que implique mudança do remetente ou do destinatário; III - a data de emissão ou de saída.";

    private async Task<SefazResult> SendEventAsync(string accessKey, string eventType, int sequence, SefazEnvironment environment, XElement[] detail, CancellationToken ct)
    {
        var cnpj = accessKey.Substring(6, 14);
        var uf = accessKey[..2];
        var id = $"ID{eventType}{accessKey}{sequence:00}";
        var at = DateTimeOffset.UtcNow.ToOffset(TimeSpan.FromHours(-3)).ToString("yyyy-MM-dd'T'HH:mm:sszzz", CultureInfo.InvariantCulture);
        var ev = new XElement(N + "evento", new XAttribute("versao", "1.00"),
            new XElement(N + "infEvento", new XAttribute("Id", id),
                new XElement(N + "cOrgao", uf), new XElement(N + "tpAmb", (int)environment), new XElement(N + "CNPJ", cnpj), new XElement(N + "chNFe", accessKey),
                new XElement(N + "dhEvento", at), new XElement(N + "tpEvento", eventType), new XElement(N + "nSeqEvento", sequence), new XElement(N + "verEvento", "1.00"),
                new XElement(N + "detEvento", new XAttribute("versao", "1.00"), detail)));
        var signed = NfeSigner.SignEvent(ev.ToString(SaveOptions.DisableFormatting), certificate);
        var batch = $"{DateTime.UtcNow:yyMMddHHmmss}{Random.Shared.Next(0, 1000):000}";
        var body = $"<envEvento xmlns=\"{Nfe}\" versao=\"1.00\"><idLote>{batch}</idLote>{StripDeclaration(signed)}</envEvento>";
        var ret = await CallAsync(environment, "recepcaoevento4", "NFeRecepcaoEvento4", "nfeRecepcaoEvento", body, accessKey, ct);

        var info = ret.Descendants(N + "infEvento").FirstOrDefault(e => e.Element(N + "cStat") is not null);
        if (info is null) return new SefazResult(false, Text(ret, "cStat") ?? "?", Text(ret, "xMotivo") ?? "SEFAZ answered without an event result", null, false);
        var status = (string?)info.Element(N + "cStat") ?? "?";
        var message = (string?)info.Element(N + "xMotivo") ?? "";
        // 135 event registered; 155 registered after the deadline; 136 registered without linking (not accepted here).
        return status is "135" or "155"
            ? new SefazResult(true, status, message, (string?)info.Element(N + "nProt"), false)
            : new SefazResult(false, status, message, null, false);
    }

    public async Task<SefazResult> InutilizeAsync(string xml, SefazEnvironment environment, CancellationToken ct)
    {
        var signed = NfeSigner.SignInut(xml, certificate);
        var ret = await CallAsync(environment, "nfeinutilizacao4", "NFeInutilizacao4", "nfeInutilizacaoNF", StripDeclaration(signed), "inutilização", ct);
        var info = ret.Element(N + "infInut");
        var status = (string?)info?.Element(N + "cStat") ?? Text(ret, "cStat") ?? "?";
        var message = (string?)info?.Element(N + "xMotivo") ?? Text(ret, "xMotivo") ?? "";
        return status == "102"
            ? new SefazResult(true, status, message, (string?)info?.Element(N + "nProt") ?? throw new FiscalException(502, "SEFAZ homologated the inutilização without nProt"), false)
            : new SefazResult(false, status, message, null, false);
    }

    public async Task<SefazConsultResult> ConsultAsync(string accessKey, string xml, SefazEnvironment environment, CancellationToken ct)
    {
        var body = $"<consSitNFe xmlns=\"{Nfe}\" versao=\"4.00\"><tpAmb>{(int)environment}</tpAmb><xServ>CONSULTAR</xServ><chNFe>{accessKey}</chNFe></consSitNFe>";
        var ret = await CallAsync(environment, "nfeconsultaprotocolo4", "NFeConsultaProtocolo4", "nfeConsultaNF", body, accessKey, ct);
        var status = Text(ret, "cStat") ?? "?";
        var message = Text(ret, "xMotivo") ?? "";
        switch (status)
        {
            case "100" or "150":
            {
                var prot = ret.Element(N + "protNFe") ?? throw new FiscalException(502, $"SEFAZ reported the NF authorized without protNFe (key {accessKey})");
                var protocol = (string?)prot.Element(N + "infProt")?.Element(N + "nProt");
                string? proc = null;
                if (!string.IsNullOrWhiteSpace(xml))
                {
                    var signed = NfeSigner.SignNfe(xml, certificate); // RSA PKCS#1 v1.5 is deterministic: same bytes the SEFAZ authorized
                    proc = new XElement(N + "nfeProc", new XAttribute("versao", "4.00"), XElement.Parse(StripDeclaration(signed)), prot).ToString(SaveOptions.DisableFormatting);
                }
                return new SefazConsultResult(SefazConsultOutcome.Authorized, status, message, protocol, false, proc);
            }
            case "101" or "151" or "155":
            {
                var protocol = ret.Descendants(N + "infEvento").Select(e => (string?)e.Element(N + "nProt")).FirstOrDefault(p => p is not null);
                return new SefazConsultResult(SefazConsultOutcome.Cancelled, status, message, protocol, false);
            }
            case "217" or "562":
                return new SefazConsultResult(SefazConsultOutcome.NotFound, status, message, null, false);
            case "110" or "301" or "302" or "303":
                return new SefazConsultResult(SefazConsultOutcome.Denied, status, message, null, false);
            default:
                return new SefazConsultResult(SefazConsultOutcome.Unknown, status, message, null, false);
        }
    }

    private async Task<XElement> CallAsync(SefazEnvironment env, string service, string wsdlName, string operation, string payload, string accessKey, CancellationToken ct)
    {
        var url = $"https://{Host(env)}/ws/{service}.asmx";
        var envelope = $"<?xml version=\"1.0\" encoding=\"utf-8\"?><soap12:Envelope xmlns:soap12=\"http://www.w3.org/2003/05/soap-envelope\"><soap12:Body><nfeDadosMsg xmlns=\"{Wsdl}{wsdlName}\">{payload}</nfeDadosMsg></soap12:Body></soap12:Envelope>";
        using var req = new HttpRequestMessage(HttpMethod.Post, url) { Content = new StringContent(envelope, Encoding.UTF8, "application/soap+xml") };
        req.Content.Headers.ContentType = System.Net.Http.Headers.MediaTypeHeaderValue.Parse($"application/soap+xml; charset=utf-8; action=\"{Wsdl}{wsdlName}/{operation}\"");
        HttpResponseMessage res;
        string text;
        try
        {
            res = await http.SendAsync(req, ct);
            text = await res.Content.ReadAsStringAsync(ct);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            // The outcome is unknown: SEFAZ may have authorized the NF. Reconcile by key before issuing again.
            throw new FiscalException(502, $"SEFAZ did not answer ({e.Message}). The NF with key {accessKey} may have been authorized: check the SEFAZ portal before trying again");
        }
        if (!res.IsSuccessStatusCode) throw new FiscalException(502, $"SEFAZ answered HTTP {(int)res.StatusCode} (key {accessKey})");
        try
        {
            var doc = XDocument.Parse(text);
            return doc.Descendants().FirstOrDefault(e => e.Name.LocalName is "retEnviNFe" or "retConsReciNFe" or "retEnvEvento" or "retConsSitNFe" or "retInutNFe") ?? throw new FormatException("no result element");
        }
        catch (Exception e) when (e is System.Xml.XmlException or FormatException)
        {
            throw new FiscalException(502, $"Unreadable SEFAZ answer ({e.Message}); key {accessKey}");
        }
    }

    private static string? Text(XElement root, string name) => root.Elements(N + name).Select(e => e.Value).FirstOrDefault();

    private static string StripDeclaration(string xml) => xml.StartsWith("<?xml", StringComparison.Ordinal) ? xml[(xml.IndexOf("?>", StringComparison.Ordinal) + 2)..] : xml;

    public void Dispose()
    {
        if (ownsHttp) http.Dispose();
    }
}
