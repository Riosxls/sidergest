using System.Data.Common;
using System.Text.Json;
using Ebt.Core.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Ebt.Core.Maintenance;

/// <summary>Groups of movement data that can be cleared. Master data (products, materials, customers, tools, prices, users...) is never part of a scope.</summary>
public enum ResetScope { Sales, Purchasing, Production, Stock }

public sealed record ResetTableCount(string Table, long Rows);

public sealed class DataResetException(string message) : Exception(message);

/// <summary>
/// Deletes the movement (transactional) data of the chosen scopes in foreign-key-safe order, inside one transaction.
/// The order and the safety checks come from the database's own constraints, so a scope that would orphan or silently
/// delete rows outside the selection is refused instead of half-applied.
/// </summary>
public sealed class DataResetService(EbtDbContext db, ICurrentUser user)
{
    private static readonly Dictionary<ResetScope, string[]> Tables = new()
    {
        [ResetScope.Sales] =
        [
            "certificate_measures", "quality_certificates", "fiscal_installments", "fiscal_document_lines", "fiscal_documents",
            "delivery_lines", "deliveries", "sales_order_lines", "sales_orders", "quote_request_files", "quote_lines", "quotes",
            "feasibility_studies", "sales_events",
        ],
        [ResetScope.Purchasing] =
        [
            "goods_receipt_lines", "payable_installments", "goods_receipts", "quotation_bids", "quotation_items", "quotations",
            "purchase_order_lines", "purchase_orders", "purchase_requisitions",
        ],
        [ResetScope.Production] =
        [
            "overrun_releases", "outside_shipments", "production_reports", "production_occurrences", "production_order_materials",
            "production_order_operations", "production_orders",
        ],
        [ResetScope.Stock] =
        [
            "stock_movements", "stock_documents", "stock_reservations", "stock_balances", "average_costs", "stock_closings",
            "stock_lots", "steel_usages", "slitter_jobs", "steel_lots",
        ],
    };

    private sealed record Fk(string Child, string Parent, char Rule, string[] Columns);

    private static List<string> TablesOf(IEnumerable<ResetScope> scopes) => scopes.Distinct().SelectMany(s => Tables[s]).Distinct().ToList();

    public async Task<IReadOnlyList<ResetTableCount>> PreviewAsync(IReadOnlyCollection<ResetScope> scopes, CancellationToken ct)
    {
        var tables = TablesOf(scopes);
        var conn = await OpenAsync(ct);
        var result = new List<ResetTableCount>();
        foreach (var t in tables) result.Add(new ResetTableCount(t, await ScalarAsync(conn, $"select count(*) from \"{t}\"", ct)));
        return result;
    }

    public async Task<IReadOnlyList<ResetTableCount>> ResetAsync(IReadOnlyCollection<ResetScope> scopes, CancellationToken ct)
    {
        if (scopes.Count == 0) throw new DataResetException("Choose at least one group of data to clear");
        var tables = TablesOf(scopes);
        var set = tables.ToHashSet();
        var conn = await OpenAsync(ct);

        foreach (var t in tables)
            if (await ScalarAsync(conn, $"select count(*) from information_schema.tables where table_schema = 'public' and table_name = '{t}'", ct) == 0)
                throw new DataResetException($"Table {t} does not exist");

        if (set.Contains("fiscal_documents") && await ScalarAsync(conn, "select count(*) from fiscal_documents where simulated = false", ct) > 0)
            throw new DataResetException("Real (non-simulated) fiscal documents exist; they are legal records and cannot be cleared here");

        var fks = await ForeignKeysAsync(conn, ct);
        foreach (var fk in fks.Where(f => set.Contains(f.Parent) && !set.Contains(f.Child)))
        {
            if (fk.Rule == 'c') throw new DataResetException($"Clearing {fk.Parent} would also delete {fk.Child}; include the group that owns {fk.Child}");
            if (fk.Rule is 'a' or 'r')
            {
                var used = await ScalarAsync(conn, $"select count(*) from \"{fk.Child}\" where \"{fk.Columns[0]}\" is not null", ct);
                if (used > 0) throw new DataResetException($"{fk.Child} still has {used} record(s) that point to {fk.Parent}; clear the group that owns {fk.Child} too");
            }
        }

        var order = DeleteOrder(set, fks);
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var counts = new List<ResetTableCount>();
        // A table that points at itself (parent/previous production order) cannot be emptied row by row under RESTRICT.
        foreach (var fk in fks.Where(f => f.Child == f.Parent && set.Contains(f.Child)))
            await ExecAsync(conn, $"update \"{fk.Child}\" set \"{fk.Columns[0]}\" = null where \"{fk.Columns[0]}\" is not null", ct);
        foreach (var t in order) counts.Add(new ResetTableCount(t, await ExecAsync(conn, $"delete from \"{t}\"", ct)));

        db.AuditLog.Add(new AuditEntry
        {
            At = DateTimeOffset.UtcNow, User = user.Name, Entity = "DataReset", EntityId = string.Join(",", scopes.Distinct().Select(s => s.ToString())),
            Action = "Delete", Changes = JsonSerializer.Serialize(counts.Where(c => c.Rows > 0).ToDictionary(c => c.Table, c => c.Rows)),
        });
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        return counts;
    }

    /// <summary>Children before parents (for RESTRICT / NO ACTION constraints), so every delete is legal when it runs.</summary>
    private static List<string> DeleteOrder(HashSet<string> set, List<Fk> fks)
    {
        var mustFollow = set.ToDictionary(t => t, _ => new HashSet<string>()); // parent -> children that have to go first
        foreach (var fk in fks.Where(f => f.Rule is 'a' or 'r' && f.Child != f.Parent && set.Contains(f.Child) && set.Contains(f.Parent))) mustFollow[fk.Parent].Add(fk.Child);
        var done = new List<string>();
        var left = set.OrderBy(t => t).ToList();
        while (left.Count > 0)
        {
            var next = left.FirstOrDefault(t => mustFollow[t].All(done.Contains));
            if (next is null) throw new DataResetException("Circular dependency between tables; nothing was deleted");
            done.Add(next);
            left.Remove(next);
        }
        return done;
    }

    private async Task<DbConnection> OpenAsync(CancellationToken ct)
    {
        var conn = db.Database.GetDbConnection();
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        return conn;
    }

    private async Task<long> ScalarAsync(DbConnection conn, string sql, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        cmd.Transaction = db.Database.CurrentTransaction?.GetDbTransaction();
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct));
    }

    private async Task<long> ExecAsync(DbConnection conn, string sql, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        cmd.Transaction = db.Database.CurrentTransaction?.GetDbTransaction();
        return await cmd.ExecuteNonQueryAsync(ct);
    }

    private async Task<List<Fk>> ForeignKeysAsync(DbConnection conn, CancellationToken ct)
    {
        const string sql = """
            select c.conrelid::regclass::text, c.confrelid::regclass::text, c.confdeltype::text,
                   array(select a.attname from unnest(c.conkey) with ordinality k(n, o) join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.n order by k.o)
            from pg_constraint c where c.contype = 'f'
            """;
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        cmd.Transaction = db.Database.CurrentTransaction?.GetDbTransaction();
        var list = new List<Fk>();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) list.Add(new Fk(r.GetString(0).Trim('"'), r.GetString(1).Trim('"'), r.GetString(2)[0], (string[])r.GetValue(3)));
        return list;
    }
}
