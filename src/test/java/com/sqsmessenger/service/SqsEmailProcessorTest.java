package com.sqsmessenger.service;

import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sqsmessenger.model.EmailRequest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class SqsEmailProcessorTest {

    @Mock
    private EmailSender emailSender;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void processesSingleRecipientAsStringAndReturnsNoFailures() {
        SqsEmailProcessor processor = new SqsEmailProcessor(emailSender, objectMapper);

        SQSEvent event = new SQSEvent();
        SQSEvent.SQSMessage msg = new SQSEvent.SQSMessage();
        msg.setMessageId("msg-1");
        msg.setBody("""
                {
                  "to": "alice@example.com",
                  "subject": "Bem-vinda",
                  "body": "Olá Alice!",
                  "html": false
                }
                """);
        event.setRecords(List.of(msg));

        SQSBatchResponse response = processor.process(event);

        assertTrue(response.getBatchItemFailures().isEmpty());
        ArgumentCaptor<EmailRequest> captor = ArgumentCaptor.forClass(EmailRequest.class);
        verify(emailSender).send(captor.capture());
        assertEquals(List.of("alice@example.com"), captor.getValue().to());
        assertEquals("Bem-vinda", captor.getValue().subject());
    }

    @Test
    void reportsPartialBatchFailuresWhenOneMessageIsInvalidOrFailsDelivery() {
        SqsEmailProcessor processor = new SqsEmailProcessor(emailSender, objectMapper);

        SQSEvent.SQSMessage validMsg = new SQSEvent.SQSMessage();
        validMsg.setMessageId("msg-ok");
        validMsg.setBody("""
                {"to": ["ok@example.com"], "subject": "OK", "body": "Body"}
                """);

        SQSEvent.SQSMessage invalidMsg = new SQSEvent.SQSMessage();
        invalidMsg.setMessageId("msg-invalid-email");
        invalidMsg.setBody("""
                {"to": ["not-an-email"], "subject": "Bad", "body": "Body"}
                """);

        SQSEvent.SQSMessage deliveryFailMsg = new SQSEvent.SQSMessage();
        deliveryFailMsg.setMessageId("msg-smtp-fail");
        deliveryFailMsg.setBody("""
                {"to": ["fail@example.com"], "subject": "Fail", "body": "Body"}
                """);

        org.mockito.Mockito.doAnswer(invocation -> {
            EmailRequest req = invocation.getArgument(0);
            if (req.to().contains("fail@example.com")) {
                throw new EmailDeliveryException("SMTP error", new RuntimeException());
            }
            return null;
        }).when(emailSender).send(any());

        SQSEvent event = new SQSEvent();
        event.setRecords(List.of(validMsg, invalidMsg, deliveryFailMsg));

        SQSBatchResponse response = processor.process(event);

        verify(emailSender, times(2)).send(any());
        assertEquals(2, response.getBatchItemFailures().size());
        assertEquals("msg-invalid-email", response.getBatchItemFailures().get(0).getItemIdentifier());
        assertEquals("msg-smtp-fail", response.getBatchItemFailures().get(1).getItemIdentifier());
    }

    @Test
    void handlesEmptyEventGracefully() {
        SqsEmailProcessor processor = new SqsEmailProcessor(emailSender, objectMapper);
        SQSBatchResponse response = processor.process(new SQSEvent());
        assertTrue(response.getBatchItemFailures().isEmpty());
    }
}
