using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Ebt.Api.Infrastructure;

public class DatabaseExceptionHandler(ILogger<DatabaseExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception exception, CancellationToken ct)
    {
        if (exception is DbUpdateConcurrencyException)
        {
            await Results.Problem("The record was changed by someone else; reload and try again", statusCode: StatusCodes.Status409Conflict, title: "Concurrent update").ExecuteAsync(http);
            return true;
        }
        if (exception is not DbUpdateException { InnerException: PostgresException pg }) return false;
        var (status, title) = pg.SqlState switch
        {
            PostgresErrorCodes.UniqueViolation => (StatusCodes.Status409Conflict, "Duplicate value"),
            PostgresErrorCodes.ForeignKeyViolation => (StatusCodes.Status409Conflict, "Referenced record missing or still in use"),
            PostgresErrorCodes.CheckViolation => (StatusCodes.Status400BadRequest, "Invalid value"),
            PostgresErrorCodes.NotNullViolation => (StatusCodes.Status400BadRequest, "Required value missing"),
            PostgresErrorCodes.StringDataRightTruncation => (StatusCodes.Status400BadRequest, "Value too long"),
            _ => (0, "")
        };
        if (status == 0) return false;
        // Constraint and column names stay in the log; clients only get the generic reason.
        logger.LogWarning("Database rejected a write: {SqlState} {Constraint} {Table}.{Column}", pg.SqlState, pg.ConstraintName, pg.TableName, pg.ColumnName);
        await Results.Problem(title: title, statusCode: status, extensions: new Dictionary<string, object?> { ["traceId"] = http.TraceIdentifier }).ExecuteAsync(http);
        return true;
    }
}

public class StockExceptionHandler : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception exception, CancellationToken ct)
    {
        if (exception is not Ebt.Core.Inventory.StockException e) return false;
        IResult result = e.Kind switch
        {
            Ebt.Core.Inventory.StockErrorKind.Invalid => Results.ValidationProblem(new Dictionary<string, string[]> { [e.Field ?? ""] = [e.Message] }),
            Ebt.Core.Inventory.StockErrorKind.NotFound => Results.Problem(e.Message, statusCode: StatusCodes.Status404NotFound),
            _ => Results.Problem(e.Message, statusCode: StatusCodes.Status409Conflict)
        };
        await result.ExecuteAsync(http);
        return true;
    }
}
