using System.Text;
using Ebt.Core.Data;

namespace Ebt.DbfImport;

public interface IImportStep
{
    Task RunAsync(EbtDbContext db, ImportOptions options, Encoding encoding, ImportReport report, CancellationToken ct);
}
