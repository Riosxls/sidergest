using System.Net;
using System.Text.Json;
using Ebt.Api.Endpoints;
using Ebt.Core.Entities;
using Ebt.Core.Mail;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;

namespace Ebt.Tests;

[Collection("api")]
public class OpsHealthTests(ApiFixture api)
{
    private static readonly DateTimeOffset Now = new(2026, 11, 3, 12, 0, 0, TimeSpan.Zero);

    private sealed class FakeMail(bool enabled = true) : IMailSender
    {
        public List<OutgoingMail> Sent { get; } = [];
        public bool Enabled => enabled;
        public string? From => "alertas@ebt.test";
        public Task SendAsync(OutgoingMail mail, CancellationToken ct = default) { Sent.Add(mail); return Task.CompletedTask; }
    }

    [Fact]
    public async Task Ready_answers_200_without_a_login_and_without_secrets()
    {
        var res = await api.Anonymous().GetAsync("/health/ready");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var text = await res.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(text);
        var root = doc.RootElement;
        Assert.Equal("ok", root.GetProperty("db").GetString());
        Assert.Equal(0, root.GetProperty("pendingMigrations").GetInt32());
        Assert.True(root.GetProperty("backup").TryGetProperty("agentSeenAt", out _));
        Assert.DoesNotContain("Password", text, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Host=", text);
    }

    [Fact]
    public void Evaluate_is_503_material_only_for_database_and_migrations()
    {
        var plan = new BackupSettings { Enabled = true, AgentSeenAt = Now.AddMinutes(-1), LastRunOk = true, LastRunAt = Now.AddHours(-2) };
        var ok = OpsHealth.Evaluate(true, 0, plan, null, null, Now);
        Assert.True(ok.Ready);
        Assert.Equal("ok", ok.Status);
        Assert.Equal(2.0, ok.Backup.AgeHours);

        var pending = OpsHealth.Evaluate(true, 2, plan, null, null, Now);
        Assert.False(pending.Ready);
        Assert.Equal("unavailable", pending.Status);

        var down = OpsHealth.Evaluate(false, null, null, null, null, Now);
        Assert.False(down.Ready);
        Assert.Equal("down", down.Db);
    }

    [Fact]
    public void Backup_trouble_is_a_warning_and_never_makes_the_system_unready()
    {
        var plan = new BackupSettings { Enabled = true, AgentSeenAt = Now.AddMinutes(-30), LastRunOk = false, LastRunAt = Now.AddHours(-3) };
        var r = OpsHealth.Evaluate(true, 0, plan, Now.AddHours(-30), new OpsHealth.DrillStatus(false, Now.AddDays(-1)), Now);
        Assert.True(r.Ready);
        Assert.Equal("degraded", r.Status);
        Assert.Equal(["backup_failed", "backup_stale", "agent_silent", "drill_failed"], r.Warnings);
        Assert.Equal(30.0, r.Backup.AgeHours);

        // A plan that is off has no stale/agent warnings; a fresh status.json counts as the last good backup.
        var off = OpsHealth.Evaluate(true, 0, new BackupSettings { Enabled = false }, Now.AddHours(-40), null, Now);
        Assert.Empty(off.Warnings);
        var fresh = OpsHealth.Evaluate(true, 0, new BackupSettings { Enabled = true, AgentSeenAt = Now }, Now.AddHours(-1), null, Now);
        Assert.Empty(fresh.Warnings);
    }

    [Fact]
    public async Task Alert_service_mails_once_per_six_hours_and_resets_when_healthy()
    {
        var dir = Directory.CreateTempSubdirectory("metagest-alert").FullName;
        await using (var db = api.NewDb())
        {
            var s = await db.BackupSettings.SingleOrDefaultAsync(x => x.Id == 1) ?? db.BackupSettings.Add(new BackupSettings { Id = 1 }).Entity;
            s.Enabled = false; s.LastRunOk = null; s.LastRunAt = null;
            await db.SaveChangesAsync();
        }
        try
        {
            var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Alerts:To"] = "ti@ebt.test; chefe@ebt.test",
                ["Backup:Directory"] = dir,
            }).Build();
            var mail = new FakeMail();
            var scopes = api.CreateScope().ServiceProvider.GetRequiredService<IServiceScopeFactory>();
            var svc = new AlertService(scopes, mail, config, NullLogger<AlertService>.Instance);

            Assert.False(await svc.CheckAsync(Now, default));   // healthy
            Assert.Empty(mail.Sent);

            await File.WriteAllTextAsync(Path.Combine(dir, "drill.json"), "{\"ok\":false,\"finishedAt\":\"2026-11-02T03:00:00Z\"}");
            Assert.True(await svc.CheckAsync(Now, default));
            var m = Assert.Single(mail.Sent);
            Assert.Equal(["ti@ebt.test", "chefe@ebt.test"], m.To);
            Assert.Contains("restauração", m.Body);

            Assert.False(await svc.CheckAsync(Now.AddHours(5), default));    // throttled
            Assert.True(await svc.CheckAsync(Now.AddHours(7), default));     // still bad after 6 h
            Assert.Equal(2, mail.Sent.Count);

            await File.WriteAllTextAsync(Path.Combine(dir, "drill.json"), "{\"ok\":true}");
            Assert.False(await svc.CheckAsync(Now.AddHours(8), default));    // recovered resets the throttle
            await File.WriteAllTextAsync(Path.Combine(dir, "drill.json"), "{\"ok\":false}");
            Assert.True(await svc.CheckAsync(Now.AddHours(9), default));
            Assert.Equal(3, mail.Sent.Count);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Alert_service_stays_off_without_an_address_or_without_mail()
    {
        var dir = Directory.CreateTempSubdirectory("metagest-alert").FullName;
        try
        {
            await File.WriteAllTextAsync(Path.Combine(dir, "drill.json"), "{\"ok\":false}");
            var scopes = api.CreateScope().ServiceProvider.GetRequiredService<IServiceScopeFactory>();
            var noAddress = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> { ["Backup:Directory"] = dir }).Build();
            var mail = new FakeMail();
            Assert.False(await new AlertService(scopes, mail, noAddress, NullLogger<AlertService>.Instance).CheckAsync(Now, default));
            var withAddress = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> { ["Alerts:To"] = "ti@ebt.test", ["Backup:Directory"] = dir }).Build();
            Assert.False(await new AlertService(scopes, new FakeMail(enabled: false), withAddress, NullLogger<AlertService>.Instance).CheckAsync(Now, default));
            Assert.Empty(mail.Sent);
        }
        finally { Directory.Delete(dir, true); }
    }
}
