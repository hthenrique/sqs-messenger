package com.sqsmessenger.handler;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sqsmessenger.config.SmtpConfig;
import com.sqsmessenger.service.SmtpEmailSender;
import com.sqsmessenger.service.SqsEmailProcessor;

/**
 * AWS Lambda entry point triggered by Amazon SQS.
 */
public class SqsEmailLambdaHandler implements RequestHandler<SQSEvent, SQSBatchResponse> {

    private final SqsEmailProcessor processor;

    public SqsEmailLambdaHandler() {
        SmtpConfig config = SmtpConfig.fromEnv();
        SmtpEmailSender emailSender = new SmtpEmailSender(config);
        this.processor = new SqsEmailProcessor(emailSender, new ObjectMapper());
    }

    SqsEmailLambdaHandler(SqsEmailProcessor processor) {
        this.processor = processor;
    }

    @Override
    public SQSBatchResponse handleRequest(SQSEvent event, Context context) {
        return processor.process(event);
    }
}
