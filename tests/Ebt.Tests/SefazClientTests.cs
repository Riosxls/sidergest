using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;

namespace Ebt.Tests;

public class SefazClientTests
{
    private const string Key = "35261011222333000181550010000025811123456785";
    private static readonly string Nfe = $"<NFe xmlns=\"{NfeSigner.Ns}\"><infNFe versao=\"4.00\" Id=\"NFe{Key}\"><ide><cUF>35</cUF></ide></infNFe></NFe>";

    private static X509Certificate2 Certificate()
    {
        using var rsa = RSA.Create(2048);
        var req = new CertificateRequest("CN=EBT TESTE:11222333000181", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        return new X509Certificate2(req.CreateSelfSigned(DateTimeOffset.Now.AddDays(-1), DateTimeOffset.Now.AddDays(30)).Export(X509ContentType.Pfx), (string?)null, X509KeyStorageFlags.Exportable);
    }

    private sealed class Fake(Func<HttpRequestMessage, string, HttpResponseMessage> reply) : HttpMessageHandler
    {
        public List<(string Url, string Body)> Calls { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var body = await request.Content!.ReadAsStringAsync(ct);
            Calls.Add((request.RequestUri!.ToString(), body));
            return reply(request, body);
        }
    }

    private static HttpResponseMessage Soap(string inner) => new(HttpStatusCode.OK)
    {
        Content = new StringContent($"<soap:Envelope xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\"><soap:Body><nfeResultMsg>{inner}</nfeResultMsg></soap:Body></soap:Envelope>", Encoding.UTF8, "application/soap+xml")
    };

    private static string Prot(string cStat, string motivo, string nProt = "135261234567890") =>
        $"<retEnviNFe xmlns=\"{NfeSigner.Ns}\" versao=\"4.00\"><tpAmb>2</tpAmb><cStat>104</cStat><xMotivo>Lote processado</xMotivo><protNFe versao=\"4.00\"><infProt><tpAmb>2</tpAmb><chNFe>{Key}</chNFe><cStat>{cStat}</cStat><xMotivo>{motivo}</xMotivo><nProt>{nProt}</nProt></infProt></protNFe></retEnviNFe>";

    [Fact]
    public void Signature_is_valid_and_breaks_when_the_document_changes()
    {
        var cert = Certificate();
        var signed = NfeSigner.SignNfe(Nfe, cert);
        Assert.Contains("<Signature", signed);
        Assert.Contains("rsa-sha1", signed);
        Assert.True(NfeSigner.Verify(signed, cert));
        Assert.False(NfeSigner.Verify(signed.Replace("<cUF>35</cUF>", "<cUF>41</cUF>"), cert));
    }

    [Fact]
    public async Task Authorized_batch_returns_protocol_and_nfeProc_with_the_signed_nfe()
    {
        var cert = Certificate();
        var handler = new Fake((_, _) => Soap(Prot("100", "Autorizado o uso da NF-e")));
        var r = await new SefazSpClient(new SefazOptions(), cert, handler).AuthorizeAsync(Key, Nfe, SefazEnvironment.Homologation, default);
        Assert.True(r.Authorized);
        Assert.Equal("135261234567890", r.Protocol);
        Assert.Contains("<nfeProc", r.AuthorizedXml);
        Assert.Contains("<protNFe", r.AuthorizedXml);
        Assert.Contains("<Signature", r.AuthorizedXml);
        var call = Assert.Single(handler.Calls);
        Assert.Equal("https://homologacao.nfe.fazenda.sp.gov.br/ws/nfeautorizacao4.asmx", call.Url);
        Assert.Contains("<indSinc>1</indSinc>", call.Body);
        Assert.Contains("NFeAutorizacao4", call.Body);
    }

    [Fact]
    public async Task Rejection_is_a_result_not_an_exception()
    {
        var r = await new SefazSpClient(new SefazOptions(), Certificate(), new Fake((_, _) => Soap(Prot("539", "Duplicidade de NF-e")))).AuthorizeAsync(Key, Nfe, SefazEnvironment.Production, default);
        Assert.False(r.Authorized);
        Assert.Equal("539", r.Status);
        Assert.Null(r.AuthorizedXml);
    }

    [Fact]
    public async Task Pending_batch_is_polled_until_processed()
    {
        var n = 0;
        var handler = new Fake((_, _) => ++n == 1
            ? Soap($"<retEnviNFe xmlns=\"{NfeSigner.Ns}\" versao=\"4.00\"><cStat>103</cStat><xMotivo>Lote recebido</xMotivo><infRec><nRec>351000000000001</nRec></infRec></retEnviNFe>".Replace("<infRec><nRec>351000000000001</nRec></infRec>", "<nRec>351000000000001</nRec>"))
            : Soap(Prot("100", "Autorizado").Replace("retEnviNFe", "retConsReciNFe")));
        var r = await new SefazSpClient(new SefazOptions { PollDelayMilliseconds = 1 }, Certificate(), handler).AuthorizeAsync(Key, Nfe, SefazEnvironment.Homologation, default);
        Assert.True(r.Authorized);
        Assert.Equal(2, handler.Calls.Count);
        Assert.EndsWith("nferetautorizacao4.asmx", handler.Calls[1].Url);
        Assert.Contains("<nRec>351000000000001</nRec>", handler.Calls[1].Body);
    }

    [Fact]
    public async Task Network_failure_is_an_error_that_names_the_key_because_the_outcome_is_unknown()
    {
        var client = new SefazSpClient(new SefazOptions(), Certificate(), new Fake((_, _) => throw new HttpRequestException("timeout")));
        var e = await Assert.ThrowsAsync<FiscalException>(() => client.AuthorizeAsync(Key, Nfe, SefazEnvironment.Homologation, default));
        Assert.Equal(502, e.Status);
        Assert.Contains(Key, e.Message);
    }

    [Fact]
    public async Task Cancellation_sends_a_signed_110111_event()
    {
        var cert = Certificate();
        var handler = new Fake((_, _) => Soap($"<retEnvEvento xmlns=\"{NfeSigner.Ns}\" versao=\"1.00\"><cStat>128</cStat><xMotivo>Lote de Evento Processado</xMotivo><retEvento versao=\"1.00\"><infEvento><cStat>135</cStat><xMotivo>Evento registrado</xMotivo><nProt>135269999999999</nProt></infEvento></retEvento></retEnvEvento>"));
        var r = await new SefazSpClient(new SefazOptions(), cert, handler).CancelAsync(Key, "135261234567890", "Erro de digitação no pedido", SefazEnvironment.Homologation, default);
        Assert.True(r.Authorized);
        Assert.Equal("135269999999999", r.Protocol);
        var call = Assert.Single(handler.Calls);
        Assert.EndsWith("recepcaoevento4.asmx", call.Url);
        Assert.Contains("<tpEvento>110111</tpEvento>", call.Body);
        Assert.Contains($"Id=\"ID110111{Key}01\"", call.Body);
        Assert.Contains("<Signature", call.Body);
        Assert.Contains("<CNPJ>11222333000181</CNPJ>", call.Body);
    }
}
