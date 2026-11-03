using System.Text;
using Ebt.Core.Data;
using Ebt.Core.Mail;

namespace Ebt.Api.Endpoints;

/// <summary>
/// Every 5 minutes evaluates what <c>/health/ready</c> reports and, when something is wrong, mails <c>Alerts:To</c> (env <c>EBT_ALERT_TO</c>; several addresses
/// separated by ; or ,) at most once every 6 hours. Off when the address is empty or e-mail sending is not configured. The last alert time is kept in memory
/// (a restart of the API may repeat one alert; no schema change needed). Warning codes: see <see cref="OpsHealth.Evaluate"/>.
/// </summary>
public sealed class AlertService(IServiceScopeFactory scopes, IMailSender mail, IConfiguration config, ILogger<AlertService> logger) : BackgroundService
{
    public static readonly TimeSpan Repeat = TimeSpan.FromHours(6);
    private DateTimeOffset? lastAlertAt;

    private static readonly Dictionary<string, string> Texts = new()
    {
        ["db_down"] = "O banco de dados não responde.",
        ["migrations_pending"] = "Há migrações do banco pendentes.",
        ["backup_failed"] = "O último backup falhou.",
        ["backup_stale"] = "Não há backup recente (mais de 26 horas).",
        ["agent_silent"] = "O agente de backup não dá sinal há mais de 10 minutos.",
        ["drill_failed"] = "O último teste de restauração falhou.",
    };

    public IReadOnlyList<string> Recipients => (config["Alerts:To"] ?? "")
        .Split([';', ','], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Where(a => a.Contains('@')).ToList();

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var seconds = Math.Max(1, config.GetValue("Alerts:IntervalSeconds", 300));
        try { await Task.Delay(TimeSpan.FromSeconds(Math.Min(120, seconds)), stoppingToken); } catch (OperationCanceledException) { return; }   // let the host and the agent settle after a start
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(seconds));
        do
        {
            try { await CheckAsync(DateTimeOffset.UtcNow, stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch (Exception e) { logger.LogError(e, "Alert check failed"); }
            try { if (!await timer.WaitForNextTickAsync(stoppingToken)) return; } catch (OperationCanceledException) { return; }
        } while (true);
    }

    /// <summary>One evaluation. Returns true when an alert mail was sent.</summary>
    public async Task<bool> CheckAsync(DateTimeOffset now, CancellationToken ct)
    {
        if (Recipients.Count == 0 || !mail.Enabled) return false;
        await using var scope = scopes.CreateAsyncScope();
        var report = await OpsHealth.EvaluateAsync(scope.ServiceProvider.GetRequiredService<EbtDbContext>(), config, now, ct);

        var problems = new List<string>();
        if (report.Db != "ok") problems.Add("db_down");
        else if (report.PendingMigrations is > 0) problems.Add("migrations_pending");
        problems.AddRange(report.Warnings);
        if (problems.Count == 0) { lastAlertAt = null; return false; }   // recovered: the next problem alerts at once
        if (lastAlertAt is { } last && now - last < Repeat) return false;

        var body = new StringBuilder("O MetaGest precisa de atenção:\n\n");
        foreach (var p in problems) body.Append("- ").Append(Texts.GetValueOrDefault(p, p)).Append('\n');
        body.Append("\nVeja Configurações > Administração > Cópia de segurança no aplicativo e o arquivo backup-status\\agent.log no servidor. ");
        body.Append("Este aviso se repete a cada 6 horas enquanto o problema continuar.\n");
        try
        {
            await mail.SendAsync(new OutgoingMail(Recipients, [], "[MetaGest] Alerta de operação", body.ToString()), ct);
            lastAlertAt = now;
            logger.LogWarning("Alert sent to {Count} recipient(s): {Problems}", Recipients.Count, string.Join(", ", problems));
            return true;
        }
        catch (MailException e)
        {
            logger.LogError("Alert mail failed: {Message}", e.Message);
            lastAlertAt = now;   // do not hammer a broken mail server every 5 minutes
            return false;
        }
    }
}
