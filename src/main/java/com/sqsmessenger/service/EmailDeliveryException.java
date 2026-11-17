package com.sqsmessenger.service;

/**
 * Runtime exception thrown when an email fails to be constructed or delivered.
 */
public class EmailDeliveryException extends RuntimeException {

    public EmailDeliveryException(String message, Throwable cause) {
        super(message, cause);
    }
}
