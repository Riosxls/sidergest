namespace Ebt.Core.Data;

public static class DbTransactions
{
    /// <summary>Runs <paramref name="work"/> in a transaction, joining the current one if present. Rolls back and clears tracked entities on failure.</summary>
    public static async Task<T> InTransactionAsync<T>(this EbtDbContext db, Func<Task<T>> work, CancellationToken ct)
    {
        if (db.Database.CurrentTransaction is not null) return await work();
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        try
        {
            var result = await work();
            await tx.CommitAsync(ct);
            return result;
        }
        catch
        {
            await tx.RollbackAsync(CancellationToken.None);
            db.ChangeTracker.Clear();
            throw;
        }
    }
}
