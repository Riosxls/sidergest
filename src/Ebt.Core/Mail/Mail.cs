using System.Net;
using System.Net.Mail;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

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

    /// <summary>STARTTLS on the port (587, the usual one). Turn it off only for a relay inside the company network.</summary>
    public bool StartTls { get; set; } = true;

    public bool Enabled => !string.IsNullOrWhiteSpace(Host) && !string.IsNullOrWhiteSpace(From);
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
        using var msg = new MailMessage
        {
            From = new MailAddress(options.From!, options.FromName, Encoding.UTF8),
            Subject = mail.Subject,
            SubjectEncoding = Encoding.UTF8,
            Body = mail.Body,
            BodyEncoding = Encoding.UTF8,
            IsBodyHtml = false,
        };
        foreach (var a in mail.To) msg.To.Add(a);
        foreach (var a in mail.Cc) msg.CC.Add(a);
        if (!string.IsNullOrWhiteSpace(mail.ReplyTo)) msg.ReplyToList.Add(mail.ReplyTo);
        if (mail.Attachment is { } att) msg.Attachments.Add(new Attachment(new MemoryStream(att.Data), att.FileName, att.ContentType));

        using var smtp = new SmtpClient(options.Host!, options.Port)
        {
            EnableSsl = options.StartTls,
            Timeout = 30_000,
            DeliveryMethod = SmtpDeliveryMethod.Network,
        };
        if (!string.IsNullOrWhiteSpace(options.User)) smtp.Credentials = new NetworkCredential(options.User, options.Password);
        try
        {
            await smtp.SendMailAsync(msg, ct);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (SmtpException e)
        {
            throw new MailException(Describe(e), e);
        }
        catch (Exception e) when (e is IOException or System.Net.Sockets.SocketException or InvalidOperationException)
        {
            throw new MailException("Não foi possível conectar ao servidor de e-mail. Confira o servidor e a porta.", e);
        }
    }

    private static string Describe(SmtpException e) => e.StatusCode switch
    {
        SmtpStatusCode.MustIssueStartTlsFirst or SmtpStatusCode.ClientNotPermitted => "O servidor de e-mail exige login seguro. Confira usuário, senha e a opção de TLS.",
        SmtpStatusCode.MailboxUnavailable or SmtpStatusCode.MailboxNameNotAllowed => "O servidor recusou um dos endereços. Confira os e-mails digitados.",
        SmtpStatusCode.GeneralFailure or SmtpStatusCode.ServiceNotAvailable => "Não foi possível conectar ao servidor de e-mail. Confira o servidor e a porta.",
        _ => $"O servidor de e-mail recusou o envio ({e.StatusCode}).",
    };
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
