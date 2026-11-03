using MailKit;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using MimeKit;

namespace Ebt.Core.Mail;

/// <summary>SMTP account the system sends from (section <c>Mail</c>; env <c>Mail__Host</c>, <c>Mail__Password</c> ...). Without <see cref="Host"/> and <see cref="From"/> sending is off.</summary>
public sealed class MailOptions
{
    public string? Host { get; set; }
    public int Port { get; set; } = 587;
    public string? User { get; set; }
    public string? Password { get; set; }
    public string? From { get; set; }
    public string FromName { get; set; } = "EBT";

    /// <summary><c>Auto</c> (default: port 465 is SSL from the first byte, any other port uses STARTTLS when the server offers it), <c>Ssl</c>, <c>StartTls</c> (required) or <c>None</c> (relay inside the company network).</summary>
    public string Security { get; set; } = "Auto";

    public bool Enabled => !string.IsNullOrWhiteSpace(Host) && !string.IsNullOrWhiteSpace(From);

    internal SecureSocketOptions SocketOptions => Security.Trim().ToLowerInvariant() switch
    {
        "ssl" => SecureSocketOptions.SslOnConnect,
        "starttls" => SecureSocketOptions.StartTls,
        "none" => SecureSocketOptions.None,
        _ => Port == 465 ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTlsWhenAvailable,
    };
}

public sealed record MailAttachment(string FileName, byte[] Data, string ContentType = "application/pdf");

public sealed record OutgoingMail(IReadOnlyList<string> To, IReadOnlyList<string> Cc, string Subject, string Body, MailAttachment? Attachment = null, string? ReplyTo = null);

public interface IMailSender
{
    bool Enabled { get; }

    /// <summary>The address mail goes out from, or null when sending is off.</summary>
    string? From { get; }

    /// <summary>Sends the message; throws <see cref="MailException"/> with a message fit for the user when the server refuses or cannot be reached.</summary>
    Task SendAsync(OutgoingMail mail, CancellationToken ct = default);
}

public sealed class MailException(string message, Exception? inner = null) : Exception(message, inner);

public sealed class SmtpMailSender(MailOptions options) : IMailSender
{
    public bool Enabled => options.Enabled;

    public string? From => options.Enabled ? options.From : null;

    public async Task SendAsync(OutgoingMail mail, CancellationToken ct = default)
    {
        if (!Enabled) throw new MailException("O envio de e-mail não está configurado no servidor");
        var msg = new MimeMessage();
        msg.From.Add(new MailboxAddress(options.FromName, options.From));
        foreach (var a in mail.To) msg.To.Add(MailboxAddress.Parse(a));
        foreach (var a in mail.Cc) msg.Cc.Add(MailboxAddress.Parse(a));
        if (!string.IsNullOrWhiteSpace(mail.ReplyTo)) msg.ReplyTo.Add(MailboxAddress.Parse(mail.ReplyTo));
        msg.Subject = mail.Subject;
        var body = new BodyBuilder { TextBody = mail.Body };
        if (mail.Attachment is { } att) body.Attachments.Add(att.FileName, att.Data, ContentType.Parse(att.ContentType));
        msg.Body = body.ToMessageBody();

        using var smtp = new SmtpClient { Timeout = 30_000 };
        try
        {
            await smtp.ConnectAsync(options.Host, options.Port, options.SocketOptions, ct);
            if (!string.IsNullOrWhiteSpace(options.User)) await smtp.AuthenticateAsync(options.User, options.Password ?? "", ct);
            await smtp.SendAsync(msg, ct);
            await smtp.DisconnectAsync(true, ct);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (AuthenticationException e)
        {
            throw new MailException("O servidor de e-mail recusou o usuário ou a senha. Confira EBT_SMTP_USER e EBT_SMTP_PASSWORD.", e);
        }
        catch (SmtpCommandException e) when (e.StatusCode is SmtpStatusCode.MailboxUnavailable or SmtpStatusCode.MailboxNameNotAllowed or SmtpStatusCode.UserNotLocalTryAlternatePath)
        {
            throw new MailException("O servidor recusou um dos endereços. Confira os e-mails digitados e o remetente (EBT_SMTP_FROM).", e);
        }
        catch (SmtpCommandException e)
        {
            throw new MailException($"O servidor de e-mail recusou o envio ({(int)e.StatusCode}: {e.Message}).", e);
        }
        catch (Exception e) when (e is IOException or System.Net.Sockets.SocketException or SslHandshakeException or ProtocolException or ServiceNotConnectedException or ServiceNotAuthenticatedException)
        {
            throw new MailException("Não foi possível conectar ao servidor de e-mail. Confira o servidor, a porta e a criptografia (EBT_SMTP_PORT, EBT_SMTP_SECURITY).", e);
        }
    }
}

public static class MailRegistration
{
    public static IServiceCollection AddMail(this IServiceCollection services, IConfiguration config)
    {
        var options = config.GetSection("Mail").Get<MailOptions>() ?? new MailOptions();
        services.AddSingleton(options);
        services.AddSingleton<IMailSender, SmtpMailSender>();
        return services;
    }
}
