package com.sqsmessenger.handler;

import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.sqsmessenger.service.SqsEmailProcessor;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertSame;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SqsEmailLambdaHandlerTest {

    @Mock
    private SqsEmailProcessor processor;

    @Test
    void delegatesHandleRequestToProcessor() {
        SQSEvent event = new SQSEvent();
        SQSBatchResponse expected = SQSBatchResponse.builder()
                .withBatchItemFailures(List.of())
                .build();
        when(processor.process(event)).thenReturn(expected);

        SqsEmailLambdaHandler handler = new SqsEmailLambdaHandler(processor);
        SQSBatchResponse actual = handler.handleRequest(event, null);

        assertSame(expected, actual);
    }
}
