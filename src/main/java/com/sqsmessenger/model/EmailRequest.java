package com.sqsmessenger.model;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.mail.internet.AddressException;
import jakarta.mail.internet.InternetAddress;

import java.util.List;

/**
 * Payload expected in each SQS message body (JSON).
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record EmailRequest(
        @JsonFormat(with = JsonFormat.Feature.ACCEPT_SINGLE_VALUE_AS_ARRAY)
        List<String> to,
        @JsonFormat(with = JsonFormat.Feature.ACCEPT_SINGLE_VALUE_AS_ARRAY)
        List<String> cc,
        @JsonFormat(with = JsonFormat.Feature.ACCEPT_SINGLE_VALUE_AS_ARRAY)
        List<String> bcc,
        String replyTo,
        String subject,
        String body,
        boolean html
) {
    /**
     * Validates required fields and email address syntax.
     *
     * @throws IllegalArgumentException if any required field is missing or invalid
     */
    public void validate() {
        if (to == null || to.isEmpty()) {
            throw new IllegalArgumentException("Field 'to' is required and must contain at least one recipient.");
        }
        validateAddressList("to", to);
        if (cc != null && !cc.isEmpty()) {
            validateAddressList("cc", cc);
        }
        if (bcc != null && !bcc.isEmpty()) {
            validateAddressList("bcc", bcc);
        }
        if (replyTo != null && !replyTo.isBlank()) {
            validateAddress("replyTo", replyTo);
        }
        if (subject == null || subject.isBlank()) {
            throw new IllegalArgumentException("Field 'subject' is required and cannot be blank.");
        }
        if (body == null || body.isBlank()) {
            throw new IllegalArgumentException("Field 'body' is required and cannot be blank.");
        }
    }

    private static void validateAddressList(String fieldName, List<String> addresses) {
        for (String address : addresses) {
            validateAddress(fieldName, address);
        }
    }

    private static void validateAddress(String fieldName, String address) {
        if (address == null || address.isBlank()) {
            throw new IllegalArgumentException("Field '" + fieldName + "' contains a blank email address.");
        }
        try {
            InternetAddress parsed = new InternetAddress(address.trim(), true);
            parsed.validate();
        } catch (AddressException e) {
            throw new IllegalArgumentException("Invalid email address in '" + fieldName + "': " + address, e);
        }
    }
}
