using System.Collections.Concurrent;
using System.Xml.Linq;
using Ebt.Core.Entities;

namespace Ebt.Core.Fiscal;

/// <summary>
/// STUB. Stands in for SEFAZ-SP until the real webservice client exists: it checks that the XML is well formed, does not sign it, does not call
/// any network endpoint, and authorizes with a made-up protocol. Documents issued through it are flagged <c>Simulated</c>.
/// To test a rejection, put <see cref="RejectMarker"/> in the NF additional information (e.g. the delivery notes).
/// To test a lost answer, put <see cref="TimeoutMarker"/> (SEFAZ never saw the NF) or <see cref="TimeoutAuthorizedMarker"/> (SEFAZ authorized it but the answer was lost).
/// The stub remembers what it authorized, so <see cref="ConsultAsync"/> can answer by access key until the API restarts.
/// </summary>
public sealed class StubSefazClient : ISefazClient
{
    public const string RejectMarker = "#SEFAZ-REJEITAR#";
    /// <summary>Answers 204 (duplicidade): the number must not be reused before the access key is consulted.</summary>
    public const string DuplicateMarker = "#SEFAZ-DUPLICIDADE#";
    public const string TimeoutMarker = "#SEFAZ-TIMEOUT#";
    public const string TimeoutAuthorizedMarker = "#SEFAZ-TIMEOUT-AUTORIZADA#";

    public bool IsSimulated => true;

    private readonly ConcurrentDictionary<string, string> authorized = new();
    private readonly ConcurrentDictionary<string, string> cancelled = new();

    public Task<SefazResult> AuthorizeAsync(string accessKey, string xml, SefazEnvironment environment, CancellationToken ct)
    {
        try { XDocument.Parse(xml); }
        catch (System.Xml.XmlException e) { return Task.FromResult(new SefazResult(false, "225", $"Falha no Schema XML: {e.Message}", null, true)); }
        if (xml.Contains(RejectMarker, StringComparison.Ordinal))
            return Task.FromResult(new SefazResult(false, "999", "Rejeição simulada pelo stub", null, true));
        if (xml.Contains(DuplicateMarker, StringComparison.Ordinal))
            return Task.FromResult(new SefazResult(false, "204", "Duplicidade de NF-e (simulado)", null, true));
        if (xml.Contains(TimeoutAuthorizedMarker, StringComparison.Ordinal)) authorized[accessKey] = Protocol();
        if (xml.Contains(TimeoutMarker, StringComparison.Ordinal) || xml.Contains(TimeoutAuthorizedMarker, StringComparison.Ordinal))
            throw new FiscalException(502, $"SEFAZ did not answer (simulated timeout). The NF with key {accessKey} may have been authorized: it stays Pending until the reconciliation resolves it");
        var protocol = Protocol();
        authorized[accessKey] = protocol;
        return Task.FromResult(new SefazResult(true, "100", "Autorizado o uso da NF-e (simulado)", protocol, true));
    }

    public Task<SefazResult> CancelAsync(string accessKey, string authorizationProtocol, string reason, SefazEnvironment environment, CancellationToken ct)
    {
        var protocol = Protocol();
        cancelled[accessKey] = protocol;
        return Task.FromResult(new SefazResult(true, "135", "Evento registrado e vinculado a NF-e (simulado)", protocol, true));
    }

    /// <summary>Always authorizes (status 135) unless the correction text contains <see cref="RejectMarker"/>.</summary>
    public Task<SefazResult> CorrectAsync(string accessKey, int sequence, string text, SefazEnvironment environment, CancellationToken ct) =>
        Task.FromResult(text.Contains(RejectMarker, StringComparison.Ordinal)
            ? new SefazResult(false, "999", "Rejeição simulada pelo stub", null, true)
            : new SefazResult(true, "135", "Evento registrado e vinculado a NF-e (simulado)", Protocol(), true));

    public Task<SefazResult> InutilizeAsync(string xml, SefazEnvironment environment, CancellationToken ct)
    {
        try { XDocument.Parse(xml); }
        catch (System.Xml.XmlException e) { return Task.FromResult(new SefazResult(false, "225", $"Falha no Schema XML: {e.Message}", null, true)); }
        if (xml.Contains(RejectMarker, StringComparison.Ordinal)) return Task.FromResult(new SefazResult(false, "999", "Rejeição simulada pelo stub", null, true));
        return Task.FromResult(new SefazResult(true, "102", "Inutilização de número homologado (simulado)", Protocol(), true));
    }

    public Task<SefazConsultResult> ConsultAsync(string accessKey, string xml, SefazEnvironment environment, CancellationToken ct)
    {
        if (cancelled.TryGetValue(accessKey, out var cp)) return Task.FromResult(new SefazConsultResult(SefazConsultOutcome.Cancelled, "101", "Cancelamento de NF-e homologado (simulado)", cp, true));
        if (authorized.TryGetValue(accessKey, out var p)) return Task.FromResult(new SefazConsultResult(SefazConsultOutcome.Authorized, "100", "Autorizado o uso da NF-e (simulado)", p, true));
        return Task.FromResult(new SefazConsultResult(SefazConsultOutcome.NotFound, "217", "NF-e nao consta na base de dados da SEFAZ (simulado)", null, true));
    }

    private static string Protocol() => $"135{DateTime.UtcNow:yyMMddHHmmssfff}";
}
