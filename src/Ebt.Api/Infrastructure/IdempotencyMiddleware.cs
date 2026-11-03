using System.Security.Claims;
using System.Security.Cryptography;
using System.IdentityModel.Tokens.Jwt;
using System.Text.RegularExpressions;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Ebt.Api.Infrastructure;

/// <summary>
/// Server side of the <c>Idempotency-Key</c> header. A signed-in client sends one UUID per submit attempt and reuses it when it retries the
/// same submit; the first response is stored for 24 hours and a repeat gets it back (header <c>Idempotent-Replay: true</c>) without running again.
/// The same key with another method, path or body is refused (422); the same key while the first request still runs gets 409.
/// Requests without the header, multipart uploads and anonymous requests pass through untouched; responses over 1 MB and server errors are
/// not stored (the retry then runs normally).
/// </summary>
public sealed partial class IdempotencyMiddleware(RequestDelegate next, IServiceScopeFactory scopes, ILogger<IdempotencyMiddleware> log)
{
    public const string RequestHeader = "Idempotency-Key";
    public const string ReplayHeader = "Idempotent-Replay";
    public static readonly TimeSpan Retention = TimeSpan.FromHours(24);
    public const int MaxStoredBytes = 1024 * 1024;

    /// <summary>A key still marked in flight after this long belongs to a request that died (crash, restart); it no longer blocks a retry.</summary>
    private static readonly TimeSpan StaleInFlight = TimeSpan.FromMinutes(2);

    private static readonly TimeSpan CleanupEvery = TimeSpan.FromMinutes(10);
    private static DateTime lastCleanup = DateTime.MinValue;

    [GeneratedRegex("^[A-Za-z0-9_-]{8,64}$")]
    private static partial Regex ValidKey();

    public async Task InvokeAsync(HttpContext http)
    {
        var req = http.Request;
        if (!(HttpMethods.IsPost(req.Method) || HttpMethods.IsPut(req.Method) || HttpMethods.IsPatch(req.Method) || HttpMethods.IsDelete(req.Method))
            || !req.Headers.TryGetValue(RequestHeader, out var values) || values.Count == 0
            || !int.TryParse(http.User.FindFirstValue(JwtRegisteredClaimNames.Sub), out var userId)
            || (req.ContentType?.StartsWith("multipart/", StringComparison.OrdinalIgnoreCase) ?? false))
        {
            await next(http);
            return;
        }
        var key = values[0]!.Trim();
        if (!ValidKey().IsMatch(key))
        {
            await Results.Problem("A chave de idempotência (Idempotency-Key) deve ter de 8 a 64 caracteres: letras, números, hífen ou sublinhado.", statusCode: StatusCodes.Status400BadRequest).ExecuteAsync(http);
            return;
        }

        var method = req.Method.ToUpperInvariant();
        var path = req.Path.Value ?? "/";
        req.EnableBuffering();
        var bodyHash = Convert.ToHexString(await SHA256.HashDataAsync(req.Body, http.RequestAborted)).ToLowerInvariant();
        req.Body.Position = 0;

        using var scope = scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<EbtDbContext>();
        var ct = http.RequestAborted;
        var now = DateTimeOffset.UtcNow;

        var row = await db.IdempotencyKeys.AsNoTracking().Where(k => k.UserId == userId && k.Key == key).FirstOrDefaultAsync(ct);
        if (row is not null && (row.ExpiresAt <= now || row.InFlight && now - row.CreatedAt > StaleInFlight))
        {
            await db.IdempotencyKeys.Where(k => k.Id == row.Id).ExecuteDeleteAsync(ct);
            row = null;
        }
        if (row is not null)
        {
            if (row.Method != method || row.Path != path || row.BodyHash != bodyHash)
                await Results.Problem("Esta chave de idempotência já foi usada em outra requisição (outro endereço ou outro conteúdo).", statusCode: StatusCodes.Status422UnprocessableEntity).ExecuteAsync(http);
            else if (row.InFlight)
                await Results.Problem("Esta operação já está em andamento. Aguarde a resposta antes de tentar de novo.", statusCode: StatusCodes.Status409Conflict).ExecuteAsync(http);
            else await Replay(http, row);
            return;
        }

        var mine = new IdempotencyKey { UserId = userId, Key = key, Method = method, Path = path.Length > 300 ? path[..300] : path, BodyHash = bodyHash, CreatedAt = now, ExpiresAt = now + Retention };
        db.IdempotencyKeys.Add(mine);
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException e) when (e.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            // Two requests with the same key raced past the lookup: the other one won.
            await Results.Problem("Esta operação já está em andamento. Aguarde a resposta antes de tentar de novo.", statusCode: StatusCodes.Status409Conflict).ExecuteAsync(http);
            return;
        }
        if (DateTime.UtcNow - lastCleanup > CleanupEvery)
        {
            lastCleanup = DateTime.UtcNow;
            try { await db.IdempotencyKeys.Where(k => k.ExpiresAt < now).ExecuteDeleteAsync(CancellationToken.None); }
            catch (Exception e) { log.LogWarning(e, "Could not purge expired idempotency keys"); }
        }

        var original = http.Response.Body;
        var tee = new CapturingStream(original, MaxStoredBytes);
        http.Response.Body = tee;
        var stored = false;
        try
        {
            await next(http);
            if (!tee.Overflowed && http.Response.StatusCode < 500)
            {
                var status = http.Response.StatusCode;
                var type = http.Response.ContentType;
                var body = tee.Captured.ToArray();
                await db.IdempotencyKeys.Where(k => k.Id == mine.Id).ExecuteUpdateAsync(s => s
                    .SetProperty(k => k.InFlight, false).SetProperty(k => k.ResponseStatus, status)
                    .SetProperty(k => k.ResponseContentType, type != null && type.Length > 120 ? type[..120] : type).SetProperty(k => k.ResponseBody, body), CancellationToken.None);
                stored = true;
            }
        }
        finally
        {
            if (!stored) await ReleaseAsync(db, mine.Id);
            http.Response.Body = original;
        }
        await tee.FlushCapturedAsync(ct); // after the row is stored, so an immediate retry already finds the answer
    }

    private async Task ReleaseAsync(EbtDbContext db, long id)
    {
        try { await db.IdempotencyKeys.Where(k => k.Id == id).ExecuteDeleteAsync(CancellationToken.None); }
        catch (Exception e) { log.LogWarning(e, "Could not release idempotency key {Id}", id); }
    }

    private static async Task Replay(HttpContext http, IdempotencyKey row)
    {
        http.Response.StatusCode = row.ResponseStatus ?? StatusCodes.Status200OK;
        http.Response.Headers[ReplayHeader] = "true";
        if (row.ResponseContentType is { } type) http.Response.ContentType = type;
        if (row.ResponseBody is { Length: > 0 } body)
        {
            http.Response.ContentLength = body.Length;
            await http.Response.Body.WriteAsync(body, http.RequestAborted);
        }
    }

    /// <summary>
    /// Holds the response in memory so it can be stored before the client sees it. Past the limit it hands everything to the real stream and
    /// stops capturing (the response is then simply not stored).
    /// </summary>
    private sealed class CapturingStream(Stream inner, int limit) : Stream
    {
        public MemoryStream Captured { get; private set; } = new();
        public bool Overflowed { get; private set; }

        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();

        public override void Flush() { if (Overflowed) inner.Flush(); }
        public override Task FlushAsync(CancellationToken ct) => Overflowed ? inner.FlushAsync(ct) : Task.CompletedTask;

        public override void Write(byte[] buffer, int offset, int count) => WriteAsync(buffer.AsMemory(offset, count)).AsTask().GetAwaiter().GetResult();

        public override async ValueTask WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken ct = default)
        {
            if (!Overflowed && Captured.Length + buffer.Length <= limit)
            {
                Captured.Write(buffer.Span);
                return;
            }
            if (!Overflowed)
            {
                Overflowed = true;
                Captured.Position = 0;
                await Captured.CopyToAsync(inner, ct);
                Captured = new MemoryStream();
            }
            await inner.WriteAsync(buffer, ct);
        }

        public override Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken ct) => WriteAsync(buffer.AsMemory(offset, count), ct).AsTask();

        public async Task FlushCapturedAsync(CancellationToken ct)
        {
            if (Overflowed || Captured.Length == 0) return;
            Captured.Position = 0;
            await Captured.CopyToAsync(inner, ct);
        }
    }
}
