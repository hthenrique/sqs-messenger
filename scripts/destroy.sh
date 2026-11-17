#!/usr/bin/env bash
set -euo pipefail

if ! command -v aws >/dev/null 2>&1; then
  if command -v aws.exe >/dev/null 2>&1; then
    aws() { aws.exe "$@" | tr -d '\r'; }
  else
    echo "Erro: AWS CLI ('aws') nao encontrado no WSL nem no Windows." >&2
    exit 1
  fi
fi

AWS_REGION="${AWS_REGION:-us-east-1}"
APP_NAME="${APP_NAME:-sqs-email-messenger}"
QUEUE_NAME="${APP_NAME}-queue"
DLQ_NAME="${APP_NAME}-dlq"
ROLE_NAME="${APP_NAME}-lambda-role"
LOG_GROUP="/aws/lambda/${APP_NAME}"

echo "Removendo event source mappings..."
UUIDS=$(aws lambda list-event-source-mappings --function-name "$APP_NAME" --region "$AWS_REGION" --query "EventSourceMappings[].UUID" --output text 2>/dev/null || true)
for uuid in $UUIDS; do
  if [[ -n "$uuid" && "$uuid" != "None" ]]; then
    aws lambda delete-event-source-mapping --uuid "$uuid" --region "$AWS_REGION" >/dev/null || true
  fi
done

echo "Removendo Lambda (${APP_NAME})..."
aws lambda delete-function --function-name "$APP_NAME" --region "$AWS_REGION" 2>/dev/null || true

echo "Removendo Log Group (${LOG_GROUP})..."
aws logs delete-log-group --log-group-name "$LOG_GROUP" --region "$AWS_REGION" 2>/dev/null || true

echo "Removendo Filas SQS (${QUEUE_NAME}, ${DLQ_NAME})..."
if Q_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --region "$AWS_REGION" --query "QueueUrl" --output text 2>/dev/null); then
  aws sqs delete-queue --queue-url "$Q_URL" --region "$AWS_REGION"
fi
if DLQ_URL=$(aws sqs get-queue-url --queue-name "$DLQ_NAME" --region "$AWS_REGION" --query "QueueUrl" --output text 2>/dev/null); then
  aws sqs delete-queue --queue-url "$DLQ_URL" --region "$AWS_REGION"
fi

echo "Removendo IAM Role (${ROLE_NAME})..."
aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole" 2>/dev/null || true
aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true

echo "Recursos removidos com sucesso."
