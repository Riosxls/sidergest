using System.Xml.Linq;
using Ebt.Core.Entities;

namespace Ebt.Core.Fiscal;

/// <summary>
/// STUB. Stands in for SEFAZ-SP until the real webservice client exists: it checks that the XML is well formed, does not sign it, does not call
/// any network endpoint, and authorizes with a made-up protocol. Documents issued through it are flagged <c>Simulated</c>.
/// To test a rejection, put <see cref="RejectMarker"/> in the NF additional information (e.g. the delivery notes).
/// </summary>
public sealed class StubSefazClient : ISefazClient
{
    public const string RejectMarker = "#SEFAZ-REJEITAR#";

    public Task<SefazResult> AuthorizeAsync(string accessKey, string xml, SefazEnvironment environment, CancellationToken ct)
    {
        try { XDocument.Parse(xml); }
        catch (System.Xml.XmlException e) { return Task.FromResult(new SefazResult(false, "225", $"Falha no Schema XML: {e.Message}", null, true)); }
        if (xml.Contains(RejectMarker, StringComparison.Ordinal))
            return Task.FromResult(new SefazResult(false, "999", "Rejeição simulada pelo stub", null, true));
        return Task.FromResult(new SefazResult(true, "100", "Autorizado o uso da NF-e (simulado)", Protocol(), true));
    }

    public Task<SefazResult> CancelAsync(string accessKey, string authorizationProtocol, string reason, SefazEnvironment environment, CancellationToken ct) =>
        Task.FromResult(new SefazResult(true, "135", "Evento registrado e vinculado a NF-e (simulado)", Protocol(), true));

    private static string Protocol() => $"135{DateTime.UtcNow:yyMMddHHmmss}";
}
