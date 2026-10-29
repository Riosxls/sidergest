using Ebt.Core.Sales;

namespace Ebt.Api.Infrastructure;

/// <summary>Marks overdue quotes as expired in the background, so GET endpoints stay read-only.</summary>
public sealed class QuoteExpiryService(IServiceScopeFactory scopes, ILogger<QuoteExpiryService> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromMinutes(10);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval);
        do
        {
            try
            {
                await using var scope = scopes.CreateAsyncScope();
                var expired = await scope.ServiceProvider.GetRequiredService<SalesService>().ExpireOverdueAsync(stoppingToken);
                if (expired > 0) logger.LogInformation("Expired {Count} overdue quotes", expired);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch (Exception e) { logger.LogError(e, "Quote expiry run failed"); }
        } while (await WaitAsync(timer, stoppingToken));
    }

    private static async Task<bool> WaitAsync(PeriodicTimer timer, CancellationToken ct)
    {
        try { return await timer.WaitForNextTickAsync(ct); }
        catch (OperationCanceledException) { return false; }
    }
}
