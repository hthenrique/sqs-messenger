package com.sqsmessenger.service;

import com.sqsmessenger.model.EmailRequest;

/**
 * Contract for sending email messages.
 */
public interface EmailSender {

    /**
     * Sends an email described by {@code request}.
     *
     * @param request validated email request
     * @throws EmailDeliveryException when email delivery fails
     */
    void send(EmailRequest request);
}
