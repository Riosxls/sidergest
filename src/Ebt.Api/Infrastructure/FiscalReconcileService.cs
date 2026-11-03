using Ebt.Core.Fiscal;

namespace Ebt.Api.Infrastructure;

/// <summary>
/// Reconciles Pending NF-e documents with SEFAZ (consulta por chave) every 10 minutes, so a lost answer resolves without anyone pressing the button.
/// Only documents older than 5 minutes are touched (a request may still be waiting for SEFAZ). Off with <c>Fiscal:Reconcile:Enabled=false</c>.
/// The first run happens one interval after start, never at startup.
/// </summary>
public sealed class FiscalReconcileService(IServiceScopeFactory scopes, IConfiguration configuration, ILogger<FiscalReconcileService> logger) : BackgroundService
{
    internal static readonly TimeSpan Interval = TimeSpan.FromMinutes(10);
    internal const int MinAgeMinutes = 5;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!configuration.GetValue("Fiscal:Reconcile:Enabled", true))
        {
            logger.LogInformation("Scheduled NF-e reconciliation is off (Fiscal:Reconcile:Enabled=false)");
            return;
        }
        using var timer = new PeriodicTimer(Interval);
        try
        {
            while (await timer.WaitForNextTickAsync(stoppingToken)) await RunOnceAsync(stoppingToken);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
    }

    /// <summary>One sweep; returns the results (also used by tests).</summary>
    public async Task<IReadOnlyList<ReconcileResult>> RunOnceAsync(CancellationToken ct)
    {
        try
        {
            await using var scope = scopes.CreateAsyncScope();
            var results = await scope.ServiceProvider.GetRequiredService<FiscalService>().ReconcilePendingAsync(MinAgeMinutes, ct);
            foreach (var r in results.Where(r => r.Outcome is not ("waiting" or "unreachable")))
            {
                if (r.Unlinked || r.Outcome is "rejected") logger.LogWarning("NF {Number} reconciled as {Outcome}: {Message}", r.Number, r.Outcome, r.Message);
                else logger.LogInformation("NF {Number} reconciled as {Outcome}", r.Number, r.Outcome);
            }
            if (results.Any(r => r.Outcome == "unreachable")) logger.LogWarning("SEFAZ unreachable: {Count} pending NF-e left for the next run", results.Count(r => r.Outcome == "unreachable"));
            return results;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (Exception e)
        {
            logger.LogError(e, "NF-e reconciliation run failed");
            return [];
        }
    }
}
