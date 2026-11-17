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

ENV_FILE="${1:-.env}"
if [[ -f "$ENV_FILE" ]]; then
  echo "Carregando configuracoes de $ENV_FILE..."
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" == *"="* ]]; then
      key="${line%%=*}"
      val="${line#*=}"
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"
      val="${val#"${val%%[![:space:]]*}"}"
      val="${val%"${val##*[![:space:]]}"}"
      if [[ ( "$val" == \"*\" && "$val" == *\" ) || ( "$val" == \'*\' && "$val" == *\' ) ]]; then
        val="${val:1:${#val}-2}"
      fi
      export "$key=$val"
    fi
  done < "$ENV_FILE"
elif [[ -z "${SMTP_HOST:-}" ]]; then
  echo "Erro: arquivo '$ENV_FILE' nao encontrado e SMTP_HOST nao esta definido no ambiente." >&2
  echo "Copie 'env.example' para '.env' e preencha suas credenciais SMTP:" >&2
  echo "  cp env.example .env" >&2
  exit 1
fi

AWS_REGION="${AWS_REGION:-us-east-1}"
APP_NAME="${APP_NAME:-sqs-email-messenger}"
QUEUE_NAME="${APP_NAME}-queue"
DLQ_NAME="${APP_NAME}-dlq"
ROLE_NAME="${APP_NAME}-lambda-role"
LOG_GROUP="/aws/lambda/${APP_NAME}"
HANDLER="com.sqsmessenger.handler.SqsEmailLambdaHandler::handleRequest"
JAR_PATH="target/sqs-email-messenger-1.0.0.jar"

: "${SMTP_HOST:?Variavel SMTP_HOST obrigatoria}"
: "${SMTP_USERNAME:?Variavel SMTP_USERNAME obrigatoria}"
: "${SMTP_PASSWORD:?Variavel SMTP_PASSWORD obrigatoria}"

SMTP_PORT="${SMTP_PORT:-587}"
SMTP_FROM="${SMTP_FROM:-$SMTP_USERNAME}"
SMTP_AUTH="${SMTP_AUTH:-true}"
SMTP_STARTTLS="${SMTP_STARTTLS:-true}"
SMTP_SSL="${SMTP_SSL:-false}"

echo "1/6 Compilando e empacotando aplicacao Java 21..."
mvn clean package -DskipTests

echo "2/6 Criando Dead Letter Queue (${DLQ_NAME})..."
DLQ_URL=$(aws sqs create-queue \
  --queue-name "$DLQ_NAME" \
  --attributes '{"MessageRetentionPeriod":"1209600"}' \
  --region "$AWS_REGION" \
  --query "QueueUrl" --output text)

DLQ_ARN=$(aws sqs get-queue-attributes \
  --queue-url "$DLQ_URL" \
  --attribute-names QueueArn \
  --region "$AWS_REGION" \
  --query "Attributes.QueueArn" --output text)

echo "3/6 Criando Fila SQS principal (${QUEUE_NAME}) com Long Polling (20s)..."
QUEUE_ATTRS=$(cat <<EOF
{
  "ReceiveMessageWaitTimeSeconds": "20",
  "VisibilityTimeout": "60",
  "RedrivePolicy": "{\"deadLetterTargetArn\":\"${DLQ_ARN}\",\"maxReceiveCount\":\"3\"}"
}
EOF
)

QUEUE_URL=$(aws sqs create-queue \
  --queue-name "$QUEUE_NAME" \
  --attributes "$QUEUE_ATTRS" \
  --region "$AWS_REGION" \
  --query "QueueUrl" --output text)

QUEUE_ARN=$(aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names QueueArn \
  --region "$AWS_REGION" \
  --query "Attributes.QueueArn" --output text)

echo "4/6 Configurando IAM Role (${ROLE_NAME})..."
TRUST_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
if ! ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text 2>/dev/null); then
  ROLE_ARN=$(aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --query "Role.Arn" --output text)
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
  echo "Aguardando propagacao da IAM Role (10s)..."
  sleep 10
fi

echo "5/6 Configurando CloudWatch Log Group com retencao de 7 dias (Always Free)..."
aws logs create-log-group --log-group-name "$LOG_GROUP" --region "$AWS_REGION" 2>/dev/null || true
aws logs put-retention-policy --log-group-name "$LOG_GROUP" --retention-in-days 7 --region "$AWS_REGION"

echo "6/6 Publicando AWS Lambda (${APP_NAME}) diretamente via ZIP (sem S3)..."
ENV_TMP_FILE=".tmp-lambda-env.json"
trap 'rm -f "$ENV_TMP_FILE"' EXIT
cat <<EOF > "$ENV_TMP_FILE"
{"Variables":{"SMTP_HOST":"${SMTP_HOST}","SMTP_PORT":"${SMTP_PORT}","SMTP_USERNAME":"${SMTP_USERNAME}","SMTP_PASSWORD":"${SMTP_PASSWORD}","SMTP_FROM":"${SMTP_FROM}","SMTP_AUTH":"${SMTP_AUTH}","SMTP_STARTTLS":"${SMTP_STARTTLS}","SMTP_SSL":"${SMTP_SSL}"}}
EOF

if ! aws lambda get-function --function-name "$APP_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda create-function \
    --function-name "$APP_NAME" \
    --runtime java21 \
    --architectures arm64 \
    --role "$ROLE_ARN" \
    --handler "$HANDLER" \
    --zip-file "fileb://${JAR_PATH}" \
    --timeout 30 \
    --memory-size 512 \
    --environment "file://${ENV_TMP_FILE}" \
    --region "$AWS_REGION" >/dev/null
else
  aws lambda update-function-code \
    --function-name "$APP_NAME" \
    --zip-file "fileb://${JAR_PATH}" \
    --region "$AWS_REGION" >/dev/null
  for _ in $(seq 1 20); do
    STATUS=$(aws lambda get-function-configuration --function-name "$APP_NAME" --region "$AWS_REGION" --query "LastUpdateStatus" --output text)
    [[ "$STATUS" == "Successful" ]] && break
    [[ "$STATUS" == "Failed" ]] && { echo "Erro ao atualizar codigo da Lambda." >&2; exit 1; }
    sleep 3
  done
  aws lambda update-function-configuration \
    --function-name "$APP_NAME" \
    --timeout 30 \
    --memory-size 512 \
    --environment "file://${ENV_TMP_FILE}" \
    --region "$AWS_REGION" >/dev/null
fi
rm -f "$ENV_TMP_FILE"

EXISTING_UUID=$(aws lambda list-event-source-mappings \
  --function-name "$APP_NAME" \
  --event-source-arn "$QUEUE_ARN" \
  --region "$AWS_REGION" \
  --query "EventSourceMappings[0].UUID" \
  --output text)

if [[ -z "$EXISTING_UUID" || "$EXISTING_UUID" == "None" ]]; then
  aws lambda create-event-source-mapping \
    --function-name "$APP_NAME" \
    --event-source-arn "$QUEUE_ARN" \
    --batch-size 10 \
    --maximum-batching-window-in-seconds 5 \
    --function-response-types "ReportBatchItemFailures" \
    --scaling-config '{"MaximumConcurrency":2}' \
    --region "$AWS_REGION" >/dev/null
fi

echo ""
echo "Deploy concluido com sucesso (100% AWS Always Free)!"
echo "SQS Queue URL: ${QUEUE_URL}"
echo "SQS Queue ARN: ${QUEUE_ARN}"
echo "Lambda Function: ${APP_NAME} (${AWS_REGION})"
