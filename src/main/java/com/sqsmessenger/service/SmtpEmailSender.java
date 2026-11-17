package com.sqsmessenger.service;

import com.sqsmessenger.config.SmtpConfig;
import com.sqsmessenger.model.EmailRequest;
import jakarta.mail.Authenticator;
import jakarta.mail.Message;
import jakarta.mail.MessagingException;
import jakarta.mail.PasswordAuthentication;
import jakarta.mail.Session;
import jakarta.mail.Transport;
import jakarta.mail.internet.InternetAddress;
import jakarta.mail.internet.MimeMessage;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Objects;

/**
 * {@link EmailSender} implementation using Jakarta Mail over SMTP.
 */
public class SmtpEmailSender implements EmailSender {

    @FunctionalInterface
    public interface MessageTransport {
        void send(MimeMessage message) throws MessagingException;
    }

    private final SmtpConfig config;
    private final Session session;
    private final MessageTransport transport;

    public SmtpEmailSender(SmtpConfig config) {
        this(config, Transport::send);
    }

    public SmtpEmailSender(SmtpConfig config, MessageTransport transport) {
        this.config = Objects.requireNonNull(config, "config must not be null");
        this.transport = Objects.requireNonNull(transport, "transport must not be null");
        this.session = createSession(config);
    }

    @Override
    public void send(EmailRequest request) {
        Objects.requireNonNull(request, "request must not be null");
        try {
            MimeMessage message = buildMessage(request);
            transport.send(message);
        } catch (MessagingException e) {
            throw new EmailDeliveryException("Failed to send email to " + request.to(), e);
        }
    }

    MimeMessage buildMessage(EmailRequest request) throws MessagingException {
        MimeMessage message = new MimeMessage(session);
        message.setFrom(new InternetAddress(config.from()));

        setRecipients(message, Message.RecipientType.TO, request.to());
        setRecipients(message, Message.RecipientType.CC, request.cc());
        setRecipients(message, Message.RecipientType.BCC, request.bcc());

        if (request.replyTo() != null && !request.replyTo().isBlank()) {
            message.setReplyTo(InternetAddress.parse(request.replyTo().trim()));
        }

        message.setSubject(request.subject(), StandardCharsets.UTF_8.name());
        String subtype = request.html() ? "html" : "plain";
        message.setText(request.body(), StandardCharsets.UTF_8.name(), subtype);
        message.saveChanges();
        return message;
    }

    private static void setRecipients(
            MimeMessage message,
            Message.RecipientType type,
            List<String> addresses
    ) throws MessagingException {
        if (addresses == null || addresses.isEmpty()) {
            return;
        }
        InternetAddress[] parsed = new InternetAddress[addresses.size()];
        for (int i = 0; i < addresses.size(); i++) {
            parsed[i] = new InternetAddress(addresses.get(i).trim());
        }
        message.setRecipients(type, parsed);
    }

    private static Session createSession(SmtpConfig config) {
        if (!config.auth()) {
            return Session.getInstance(config.toMailProperties());
        }
        return Session.getInstance(config.toMailProperties(), new Authenticator() {
            @Override
            protected PasswordAuthentication getPasswordAuthentication() {
                return new PasswordAuthentication(config.username(), config.password());
            }
        });
    }
}
