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

public sealed record NfeTransport(int FreightMode, string? Carrier, string? VehiclePlate, int Packages, decimal? GrossWeightKg);

/// <param name="AuthorizedXml">nfeProc (signed NFe + protNFe) when SEFAZ authorized; null for the stub.</param>
public sealed record SefazResult(bool Authorized, string Status, string Message, string? Protocol, bool Simulated, string? AuthorizedXml = null);

public interface ISefazClient
{
    /// <summary>Signs and sends the NF-e (NFeAutorizacao4, SEFAZ-SP) and waits for the verdict. Returns the verdict, never throws for a rejection.</summary>
    Task<SefazResult> AuthorizeAsync(string accessKey, string xml, SefazEnvironment environment, CancellationToken ct);

    /// <summary>Registers the cancellation event (110111) of an authorized NF-e.</summary>
    Task<SefazResult> CancelAsync(string accessKey, string authorizationProtocol, string reason, SefazEnvironment environment, CancellationToken ct);
}

public sealed record FiscalDocumentSummary(int Id, FiscalKind Kind, FiscalStatus Status, string CfopCode, int Series, int Number, string AccessKey, string RecipientName, decimal InvoiceTotal, DateTimeOffset IssuedAt, bool Simulated);
