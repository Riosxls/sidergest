namespace Ebt.Core.Purchasing;

public sealed record GoodsReceived(
    int ReceiptId,
    int ReceiptNumber,
    int SupplierId,
    DateTimeOffset ReceivedAt,
    string InvoiceNumber,
    string InvoiceSeries,
    DateOnly InvoiceDate,
    string? ReceivedBy,
    IReadOnlyList<GoodsReceivedLine> Lines);

public sealed record GoodsReceivedLine(
    int ReceiptLineId,
    int PurchaseOrderId,
    int PurchaseOrderLineId,
    int MaterialId,
    decimal Quantity,
    string StockUnit,
    decimal UnitCost,
    decimal IcmsPercent,
    decimal IpiPercent,
    string? LotCode,
    bool RequiresInspection);

public interface IGoodsReceiptHandler
{
    Task HandleAsync(GoodsReceived receipt, CancellationToken ct);
}
