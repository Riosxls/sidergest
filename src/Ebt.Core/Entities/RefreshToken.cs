namespace Ebt.Core.Entities;

/// <summary>Server-side record of an issued refresh token. Only a SHA-256 hash of the token is stored.</summary>
public class RefreshToken
{
    public long Id { get; set; }
    public int UserId { get; set; }
    public AppUser? User { get; set; }
    public required string TokenHash { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
}
