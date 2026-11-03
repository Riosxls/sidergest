using Ebt.Core.Entities;

namespace Ebt.Core.Fiscal;

public sealed class FiscalException(int status, string message, string? field = null) : Exception(message)
{
    public int Status { get; } = status;
    public string? Field { get; } = field;

    public static FiscalException Invalid(string field, string message) => new(400, message, field);
    public static FiscalException Conflict(string message) => new(409, message);
    public static FiscalException NotFound(string what) => new(404, $"{what} not found");
    /// <summary>The NF cannot be issued (missing registration data, no price...). Nothing was sent to SEFAZ.</summary>
    public static FiscalException Blocked(string message) => new(422, message);
    /// <summary>SEFAZ answered with a rejection. Nothing was recorded.</summary>
    public static FiscalException Rejected(string status, string message) => new(422, $"SEFAZ rejected the NF ({status}): {message}");
}

public sealed record SaleInvoiceOptions(string? Cfop = null, decimal Freight = 0m, string? Carrier = null, string? VehiclePlate = null, decimal? GrossWeightKg = null);

public sealed record OutsideInvoiceOptions(decimal UnitValue, string? Cfop = null);

public sealed record NfeParty(string Name, string Document, string? StateRegistration, bool IcmsContributor, string? Street, string? Number, string? Complement, string? District, string? City, string? CityIbgeCode, string Uf, string? ZipCode, string? Email, string? Phone);

/// <param name="GrossWeightKg">pesoB.</param>
/// <param name="NetWeightKg">pesoL.</param>
/// <param name="CarrierDocument">CNPJ/CPF of the carrier, from the carrier registry when the delivery's carrier name matches.</param>
/// <param name="VehicleUf">UF of the plate; falls back to the carrier UF, never to the issuer's.</param>
public sealed record NfeTransport(int FreightMode, string? Carrier, string? VehiclePlate, int Packages, decimal? GrossWeightKg, decimal? NetWeightKg = null, string? CarrierDocument = null, string? CarrierStateRegistration = null,
    string? CarrierAddress = null, string? CarrierCity = null, string? CarrierUf = null, string? VehicleUf = null);

public sealed record ReturnLineInput(int ItemId, decimal Quantity);

/// <param name="Lines">Lines of the sale NF (fiscal document line ids) with the quantity coming back.</param>
public sealed record ReturnInput(IReadOnlyList<ReturnLineInput> Lines, int LocationId, string? Reason);

/// <param name="AuthorizedXml">nfeProc (signed NFe + protNFe) when SEFAZ authorized; null for the stub.</param>
public sealed record SefazResult(bool Authorized, string Status, string Message, string? Protocol, bool Simulated, string? AuthorizedXml = null);

public enum SefazConsultOutcome { Authorized, Cancelled, NotFound, Denied, Unknown }

/// <summary>Situation of an access key at SEFAZ (NFeConsultaProtocolo4). <paramref name="AuthorizedXml"/> is the nfeProc when the NF-e is authorized (real client only).</summary>
public sealed record SefazConsultResult(SefazConsultOutcome Outcome, string Status, string Message, string? Protocol, bool Simulated, string? AuthorizedXml = null);

public interface ISefazClient
{
    /// <summary>True for the local stub: documents reserved through it are flagged Simulated from the start.</summary>
    bool IsSimulated { get; }

    /// <summary>Asks SEFAZ what happened to an access key (NFeConsultaProtocolo4). <paramref name="xml"/> is the unsigned NFe stored locally, used to rebuild the nfeProc. Throws a 502 <see cref="FiscalException"/> when SEFAZ cannot be reached.</summary>
    Task<SefazConsultResult> ConsultAsync(string accessKey, string xml, SefazEnvironment environment, CancellationToken ct);

    /// <summary>Signs and sends the NF-e (NFeAutorizacao4, SEFAZ-SP) and waits for the verdict. Returns the verdict, never throws for a rejection.</summary>
    Task<SefazResult> AuthorizeAsync(string accessKey, string xml, SefazEnvironment environment, CancellationToken ct);

    /// <summary>Sends an unsigned <c>inutNFe</c> request (NFeInutilizacao4) and returns the verdict (status 102 = homologated).</summary>
    Task<SefazResult> InutilizeAsync(string xml, SefazEnvironment environment, CancellationToken ct);

    /// <summary>Registers the cancellation event (110111) of an authorized NF-e.</summary>
    Task<SefazResult> CancelAsync(string accessKey, string authorizationProtocol, string reason, SefazEnvironment environment, CancellationToken ct);

    /// <summary>Registers a carta de correção (CC-e, event 110110) with sequence number <paramref name="sequence"/> (1..20) for an authorized NF-e.</summary>
    Task<SefazResult> CorrectAsync(string accessKey, int sequence, string text, SefazEnvironment environment, CancellationToken ct);
}

public sealed record FiscalDocumentSummary(int Id, FiscalKind Kind, FiscalStatus Status, string CfopCode, int Series, int Number, string AccessKey, string RecipientName, decimal InvoiceTotal, DateTimeOffset IssuedAt, bool Simulated);

/// <summary>Result of reconciling one Pending NF. <paramref name="Outcome"/>: authorized, cancelled, released, rejected, waiting, unreachable, unknown, skipped.</summary>
public sealed record ReconcileResult(int Id, int Series, int Number, string AccessKey, string Outcome, string Message, FiscalStatus Status, bool Unlinked);
