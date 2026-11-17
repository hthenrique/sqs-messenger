package com.sqsmessenger.service;

import com.sqsmessenger.config.SmtpConfig;
import com.sqsmessenger.model.EmailRequest;
import jakarta.mail.Message;
import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SmtpEmailSenderTest {

    private static final SmtpConfig TEST_CONFIG = new SmtpConfig(
            "smtp.example.com", 587, "user@example.com", "secret",
            "no-reply@example.com", true, true, false, 5000, 5000
    );

    @Test
    void sendsPlainTextEmailWithAllHeaders() throws Exception {
        AtomicReference<MimeMessage> captured = new AtomicReference<>();
        SmtpEmailSender sender = new SmtpEmailSender(TEST_CONFIG, captured::set);

        EmailRequest request = new EmailRequest(
                List.of("dest1@example.com", "dest2@example.com"),
                List.of("cc@example.com"),
                List.of("bcc@example.com"),
                "reply@example.com",
                "Assunto Teste",
                "Corpo em texto puro",
                false
        );

        sender.send(request);

        MimeMessage msg = captured.get();
        assertEquals("no-reply@example.com", msg.getFrom()[0].toString());
        assertEquals(2, msg.getRecipients(Message.RecipientType.TO).length);
        assertEquals(1, msg.getRecipients(Message.RecipientType.CC).length);
        assertEquals(1, msg.getRecipients(Message.RecipientType.BCC).length);
        assertEquals("reply@example.com", msg.getReplyTo()[0].toString());
        assertEquals("Assunto Teste", msg.getSubject());
        assertEquals("Corpo em texto puro", msg.getContent());
        assertTrue(msg.getContentType().toLowerCase().contains("text/plain"));
    }

    @Test
    void sendsHtmlEmailWhenHtmlFlagIsTrue() throws Exception {
        AtomicReference<MimeMessage> captured = new AtomicReference<>();
        SmtpEmailSender sender = new SmtpEmailSender(TEST_CONFIG, captured::set);

        EmailRequest request = new EmailRequest(
                List.of("dest@example.com"),
                null,
                null,
                null,
                "HTML Email",
                "<h1>Olá</h1>",
                true
        );

        sender.send(request);

        MimeMessage msg = captured.get();
        assertEquals("<h1>Olá</h1>", msg.getContent());
        assertTrue(msg.getContentType().toLowerCase().contains("text/html"));
    }

    @Test
    void wrapsMessagingExceptionInEmailDeliveryException() {
        SmtpEmailSender sender = new SmtpEmailSender(TEST_CONFIG, msg -> {
            throw new MessagingException("SMTP connection refused");
        });

        EmailRequest request = new EmailRequest(
                List.of("dest@example.com"),
                null, null, null,
                "Subject", "Body", false
        );

        assertThrows(EmailDeliveryException.class, () -> sender.send(request));
    }
}
