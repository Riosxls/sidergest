using static Ebt.Core.Services.Text;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Fiscal;
using Ebt.Core.Inventory;
using Ebt.Core.Services;
using Ebt.Core.Production;
using Ebt.Core.Viability;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Sales;

/// <summary>Persistence helpers shared by the sales partials: event log, sequences, row locks and transactions.</summary>
public sealed partial class SalesService
{
    private void Log(SalesRecordKind kind, int id, string action, object? from, object? to, string? note, string? user) =>
        db.SalesEvents.Add(new SalesEvent { Kind = kind, RecordId = id, Action = action, FromStatus = from?.ToString(), ToStatus = to?.ToString(), Note = Clean(note), User = user, At = DateTimeOffset.UtcNow });

    private async Task<int> NextAsync(string sequence, CancellationToken ct) =>
        #pragma warning disable EF1003 // identifier sanitized by SqlIdentifier.Safe
        await db.Database.SqlQueryRaw<int>("SELECT nextval('" + SqlIdentifier.Safe(sequence) + "')::int AS \"Value\"").SingleAsync(ct);
        #pragma warning restore EF1003

    private async Task<Quote> LockQuoteAsync(int id, CancellationToken ct)
    {
        if ((await db.Database.SqlQuery<int>($"SELECT id AS \"Value\" FROM quotes WHERE id = {id} FOR UPDATE").ToListAsync(ct)).Count == 0) throw SalesException.NotFound("Quote");
        var q = await db.Quotes.Include(x => x.Lines).FirstAsync(x => x.Id == id, ct);
        await db.Entry(q).ReloadAsync(ct);
        return q;
    }

    private async Task<SalesOrder> LockOrderAsync(int id, CancellationToken ct)
    {
        if ((await db.Database.SqlQuery<int>($"SELECT id AS \"Value\" FROM sales_orders WHERE id = {id} FOR UPDATE").ToListAsync(ct)).Count == 0) throw SalesException.NotFound("Order");
        var o = await db.SalesOrders.Include(x => x.Lines).FirstAsync(x => x.Id == id, ct);
        await db.Entry(o).ReloadAsync(ct);
        return o;
    }

    private async Task<Delivery> LockDeliveryAsync(int id, CancellationToken ct)
    {
        if ((await db.Database.SqlQuery<int>($"SELECT id AS \"Value\" FROM deliveries WHERE id = {id} FOR UPDATE").ToListAsync(ct)).Count == 0) throw SalesException.NotFound("Delivery");
        var d = await db.Deliveries.Include(x => x.Lines).FirstAsync(x => x.Id == id, ct);
        await db.Entry(d).ReloadAsync(ct);
        return d;
    }

    /// <summary>
    /// Locks the order first, then the delivery. Every path that touches both (cancel order, close balance, ship, confirm, cancel delivery) takes the locks in this
    /// same order, so two of them running at once wait for each other instead of deadlocking.
    /// </summary>
    private async Task<(Delivery Delivery, SalesOrder Order)> LockDeliveryAndOrderAsync(int deliveryId, CancellationToken ct)
    {
        var orderId = await db.Deliveries.AsNoTracking().Where(x => x.Id == deliveryId).Select(x => (int?)x.OrderId).FirstOrDefaultAsync(ct) ?? throw SalesException.NotFound("Delivery");
        var o = await LockOrderAsync(orderId, ct);
        var d = await LockDeliveryAsync(deliveryId, ct);
        return (d, o);
    }

    /// <summary>How far back a typed shipping or planned date may reach before it is taken for a typo.</summary>
    private const int MaxBackdateDays = 365;

    private Task<T> InTransaction<T>(Func<Task<T>> work, CancellationToken ct) => db.InTransactionAsync(work, ct);
}
