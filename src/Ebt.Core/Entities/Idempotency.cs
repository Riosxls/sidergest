namespace Ebt.Core.Entities;

/// <summary>
/// One write request that carried an <c>Idempotency-Key</c> header. The first request inserts the row (InFlight) and runs; when it ends the
/// response is stored here, so a retry of the same submit (lost answer, double click, flaky network) gets the same answer instead of running again.
/// Rows live 24 hours.
/// </summary>
public class IdempotencyKey
{
    public long Id { get; set; }
    public int UserId { get; set; }
    public required string Key { get; set; }
    public required string Method { get; set; }
    /// <summary>Path without the query string.</summary>
    public required string Path { get; set; }
    /// <summary>SHA-256 (hex) of the request body.</summary>
    public required string BodyHash { get; set; }
    /// <summary>True until the response is stored; a second request with the key meanwhile gets 409.</summary>
    public bool InFlight { get; set; } = true;
    public int? ResponseStatus { get; set; }
    public string? ResponseContentType { get; set; }
    public byte[]? ResponseBody { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
}
