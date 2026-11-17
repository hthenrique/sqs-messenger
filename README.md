# SQS Email Messenger

Aplicação **Java 21** compatível com **Amazon SQS** para envio de e-mails de forma assíncrona e serverless na AWS, projetada para operar com **custo zero para sempre (AWS Always Free Tier)**.

---

## Arquitetura e Garantia de Custo Zero (Always Free)

A aplicação foi desenhada para não depender de nenhum serviço pago ou que expire após os 12 meses iniciais do Free Tier:

| Recurso AWS | Limite Always Free (permanente) | Configuração adotada para manter custo $0 |
| :--- | :--- | :--- |
| **AWS Lambda** (`java21`, `arm64`) | 1.000.000 req/mês + 400.000 GB-s/mês | Memória de 512 MB, timeout 30s, sem VPC/NAT Gateway. |
| **Amazon SQS** (Fila + DLQ) | 1.000.000 req/mês | **Long Polling (20s)** + `MaximumConcurrency=2` no Event Source Mapping, reduzindo polling vazio. |
| **CloudWatch Logs** | 5 GB de ingestão e armazenamento | Retenção configurada para **7 dias**. |
| **IAM Role & Policies** | Gratuito para sempre | Apenas permissões mínimas (`AWSLambdaBasicExecutionRole` e `AWSLambdaSQSQueueExecutionRole`). |
| **Deploy sem S3** | — | Upload do JAR diretamente via `aws lambda create-function --zip-file`, sem criar bucket S3. |
| **Envio SMTP** (Jakarta Mail) | — | Usa qualquer servidor SMTP gratuito (ex.: Gmail com Senha de App, Brevo, etc.), evitando custos do Amazon SES. |

> **Atenção ao polling do SQS**: Com Long Polling de 20s e `MaximumConcurrency=2`, o consumo de requisições SQS em repouso fica muito abaixo de 1.000.000/mês. Caso não utilize a fila por longos períodos, você também pode pausar o Event Source Mapping ou rodar o script `destroy`.

---

## Estrutura do Projeto

```text
sqs-messenger/
├── pom.xml
├── env.example
├── README.md
├── scripts/
│   ├── deploy.ps1            # Deploy idempotente (Windows PowerShell)
│   ├── deploy.sh             # Deploy idempotente (Linux / macOS / Git Bash)
│   ├── destroy.ps1           # Remoção completa dos recursos AWS (PowerShell)
│   ├── destroy.sh            # Remoção completa dos recursos AWS (Bash)
│   └── send-test-email.ps1   # Envio de mensagem de teste para a fila SQS
└── src/
    ├── main/java/com/sqsmessenger/
    │   ├── config/SmtpConfig.java
    │   ├── handler/SqsEmailLambdaHandler.java
    │   ├── model/EmailRequest.java
    │   └── service/
    │       ├── EmailDeliveryException.java
    │       ├── EmailSender.java
    │       ├── SmtpEmailSender.java
    │       └── SqsEmailProcessor.java
    └── test/java/com/sqsmessenger/
        ├── handler/SqsEmailLambdaHandlerTest.java
        └── service/
            ├── SmtpEmailSenderTest.java
            └── SqsEmailProcessorTest.java
```

---

## Pré-requisitos

- **Java 21** (JDK 21)
- **Apache Maven 3.9+**
- **AWS CLI v2** configurada (`aws configure`) com permissões para SQS, Lambda, IAM e CloudWatch Logs
- Uma conta SMTP gratuita (ex.: Gmail com **Verificação em 2 etapas** + **Senha de App**)

---

## Formato da Mensagem SQS (JSON)

Cada mensagem enviada para a fila SQS deve conter um JSON no seguinte formato:

```json
{
  "to": ["destinatario@exemplo.com"],
  "cc": ["copia@exemplo.com"],
  "bcc": ["oculta@exemplo.com"],
  "replyTo": "resposta@exemplo.com",
  "subject": "Assunto do e-mail",
  "body": "<h1>Olá!</h1><p>Mensagem em HTML.</p>",
  "html": true
}
```

- `to`: obrigatório (aceita uma única string `"email@exemplo.com"` ou lista de strings `["a@exemplo.com", "b@exemplo.com"]`).
- `subject`: obrigatório.
- `body`: obrigatório.
- `cc`, `bcc`, `replyTo`: opcionais.
- `html`: opcional (padrão `false` para texto puro `text/plain`; `true` envia `text/html`).

A Lambda utiliza **Partial Batch Failure Reporting** (`ReportBatchItemFailures`): se uma mensagem do lote falhar, apenas ela retorna para retry e, após 3 tentativas (`maxReceiveCount=3`), é movida automaticamente para a Dead Letter Queue (`sqs-email-messenger-dlq`).

---

## Configuração

Copie o arquivo `env.example` para `.env` e preencha suas credenciais SMTP:

```bash
cp env.example .env
```

Variáveis disponíveis:

| Variável | Obrigatória | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `AWS_REGION` | Não | `us-east-1` | Região AWS do deploy |
| `APP_NAME` | Não | `sqs-email-messenger` | Prefixo dos recursos na AWS |
| `SMTP_HOST` | Sim | — | Host SMTP (ex.: `smtp.gmail.com`) |
| `SMTP_PORT` | Não | `587` | Porta SMTP |
| `SMTP_USERNAME` | Sim (se `SMTP_AUTH=true`) | — | Usuário SMTP |
| `SMTP_PASSWORD` | Sim (se `SMTP_AUTH=true`) | — | Senha ou Senha de App SMTP |
| `SMTP_FROM` | Não | `SMTP_USERNAME` | Remetente padrão |
| `SMTP_AUTH` | Não | `true` | Habilita autenticação SMTP |
| `SMTP_STARTTLS` | Não | `true` | Habilita STARTTLS |
| `SMTP_SSL` | Não | `false` | Habilita SSL direto (porta 465) |

---

## Testes Locais

Execute os testes unitários e gere o JAR empacotado (`target/sqs-email-messenger-1.0.0.jar`):

```bash
mvn test package
```

---

## Deploy na AWS (Always Free)

### Windows (PowerShell)

```powershell
.\scripts\deploy.ps1
```

### Linux / macOS / Git Bash

```bash
chmod +x scripts/deploy.sh scripts/destroy.sh
./scripts/deploy.sh
```

O script compila o projeto, cria a fila SQS + DLQ, a IAM Role, o Log Group com retenção de 7 dias, publica a Lambda Java 21 diretamente via ZIP (sem S3) e configura o gatilho SQS.

---

## Testando o Envio na AWS

Via PowerShell:

```powershell
.\scripts\send-test-email.ps1 -To "seu-destino@exemplo.com"
```

Ou diretamente via AWS CLI:

```bash
QUEUE_URL=$(aws sqs get-queue-url --queue-name sqs-email-messenger-queue --query "QueueUrl" --output text)
aws sqs send-message \
  --queue-url "$QUEUE_URL" \
  --message-body '{"to":"seu-destino@exemplo.com","subject":"Teste SQS","body":"Olá via SQS!","html":false}'
```

---

## Remover Recursos da AWS

Para apagar completamente a Lambda, filas SQS, Log Group e IAM Role:

```powershell
.\scripts\destroy.ps1
```

ou:

```bash
./scripts/destroy.sh
```
