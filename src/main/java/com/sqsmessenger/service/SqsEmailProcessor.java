package com.sqsmessenger.service;

import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sqsmessenger.model.EmailRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/**
 * Processes SQS batch events and reports partial batch failures so only failed messages are retried.
 */
public class SqsEmailProcessor {

    private static final Logger log = LoggerFactory.getLogger(SqsEmailProcessor.class);

    private final EmailSender emailSender;
    private final ObjectMapper objectMapper;

    public SqsEmailProcessor(EmailSender emailSender, ObjectMapper objectMapper) {
        this.emailSender = Objects.requireNonNull(emailSender, "emailSender must not be null");
        this.objectMapper = Objects.requireNonNull(objectMapper, "objectMapper must not be null");
    }

    public SQSBatchResponse process(SQSEvent event) {
        List<SQSBatchResponse.BatchItemFailure> failures = new ArrayList<>();
        if (event == null || event.getRecords() == null || event.getRecords().isEmpty()) {
            return SQSBatchResponse.builder().withBatchItemFailures(failures).build();
        }

        for (SQSEvent.SQSMessage record : event.getRecords()) {
            String messageId = record.getMessageId();
            try {
                EmailRequest request = parseAndValidate(record.getBody());
                emailSender.send(request);
                log.info("Email sent successfully for SQS messageId={}", messageId);
            } catch (Exception e) {
                log.error("Failed to process SQS messageId={}: {}", messageId, e.getMessage(), e);
                failures.add(SQSBatchResponse.BatchItemFailure.builder()
                        .withItemIdentifier(messageId)
                        .build());
            }
        }

        return SQSBatchResponse.builder()
                .withBatchItemFailures(failures)
                .build();
    }

    private EmailRequest parseAndValidate(String body) throws JsonProcessingException {
        if (body == null || body.isBlank()) {
            throw new IllegalArgumentException("SQS message body is empty.");
        }
        EmailRequest request = objectMapper.readValue(body, EmailRequest.class);
        request.validate();
        return request;
    }
}
