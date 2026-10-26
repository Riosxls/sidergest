namespace Ebt.Core.Inventory;

public enum StockErrorKind { Invalid, Conflict, NotFound }

public class StockException(StockErrorKind kind, string message, string? field = null) : Exception(message)
{
    public StockErrorKind Kind { get; } = kind;
    public string? Field { get; } = field;

    public static StockException Invalid(string message, string? field = null) => new(StockErrorKind.Invalid, message, field);
    public static StockException Conflict(string message) => new(StockErrorKind.Conflict, message);
    public static StockException NotFound(string message) => new(StockErrorKind.NotFound, message);
}
