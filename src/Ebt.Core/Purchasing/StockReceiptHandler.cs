using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Purchasing;

public sealed class StockReceiptHandler(EbtDbContext db, StockService stock) : IGoodsReceiptHandler
{
    public const string DefaultLocationCode = "ALM";

    public async Task HandleAsync(GoodsReceived receipt, CancellationToken ct)
    {
        if (receipt.Lines.Count == 0) return;
        var locationId = await ReceivingLocationAsync(ct);
        var reference = string.IsNullOrEmpty(receipt.InvoiceSeries) ? $"NF {receipt.InvoiceNumber} / REC {receipt.ReceiptNumber}" : $"NF {receipt.InvoiceNumber}-{receipt.InvoiceSeries} / REC {receipt.ReceiptNumber}";
        var lines = receipt.Lines.Select(l => new StockLine(l.MaterialId, null, locationId, l.Quantity,
            LotCode: l.LotCode, UnitCost: l.UnitCost, IcmsRate: l.IcmsPercent, RequiresInspection: l.RequiresInspection)).ToList();
        await stock.PostAsync(new StockPost(MovementType.Receipt, DateOnly.FromDateTime(receipt.ReceivedAt.UtcDateTime), lines, reference, receipt.SupplierId),
            receipt.ReceivedBy ?? "system", ct);
    }

    private async Task<int> ReceivingLocationAsync(CancellationToken ct)
    {
        if (await db.PurchasingSettings.AsNoTracking().Select(s => s.ReceivingLocationId).FirstOrDefaultAsync(ct) is { } configured) return configured;
        return await db.StockLocations.AsNoTracking().Where(l => l.Code == DefaultLocationCode && l.Active).Select(l => (int?)l.Id).FirstOrDefaultAsync(ct)
               ?? throw PurchasingException.Conflict($"No receiving location: set receivingLocationId in /api/purchasing/settings or create stock location {DefaultLocationCode}");
    }
}
