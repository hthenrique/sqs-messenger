<#
.SYNOPSIS
    Deploy idempotente da aplicacao SQS Email Messenger na AWS usando apenas recursos Always Free (custo zero).
#>
param(
    [string]$EnvFile = ".env"
)

$ErrorActionPreference = "Stop"

# Carrega variaveis do arquivo .env se existir
if (Test-Path $EnvFile) {
    Write-Host "Carregando configuracoes de $EnvFile..." -ForegroundColor Cyan
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $key = $parts[0].Trim()
            $val = $parts[1].Trim()
            if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
                $val = $val.Substring(1, $val.Length - 2)
            }
            [Environment]::SetEnvironmentVariable($key, $val, "Process")
        }
    }
}

$AwsRegion   = if ($env:AWS_REGION) { $env:AWS_REGION } else { "us-east-1" }
$AppName     = if ($env:APP_NAME) { $env:APP_NAME } else { "sqs-email-messenger" }
$QueueName   = "$AppName-queue"
$DlqName     = "$AppName-dlq"
$RoleName    = "$AppName-lambda-role"
$LogGroup    = "/aws/lambda/$AppName"
$Handler     = "com.sqsmessenger.handler.SqsEmailLambdaHandler::handleRequest"
$JarPath     = "target/sqs-email-messenger-1.0.0.jar"

# Validacao de variaveis SMTP obrigatorias
$requiredVars = @("SMTP_HOST", "SMTP_USERNAME", "SMTP_PASSWORD")
foreach ($varName in $requiredVars) {
    if (-not [Environment]::GetEnvironmentVariable($varName)) {
        throw "Variavel obrigatoria '$varName' nao definida. Configure no .env ou no ambiente."
    }
}

$SmtpPort     = if ($env:SMTP_PORT) { $env:SMTP_PORT } else { "587" }
$SmtpFrom     = if ($env:SMTP_FROM) { $env:SMTP_FROM } else { $env:SMTP_USERNAME }
$SmtpAuth     = if ($env:SMTP_AUTH) { $env:SMTP_AUTH } else { "true" }
$SmtpStartTls = if ($env:SMTP_STARTTLS) { $env:SMTP_STARTTLS } else { "true" }
$SmtpSsl      = if ($env:SMTP_SSL) { $env:SMTP_SSL } else { "false" }

Write-Host "1/6 Compilando e empacotando aplicacao Java 21..." -ForegroundColor Yellow
mvn clean package -DskipTests
if (-not (Test-Path $JarPath)) {
    throw "JAR nao encontrado em $JarPath"
}

Write-Host "2/6 Criando Dead Letter Queue ($DlqName)..." -ForegroundColor Yellow
$dlqAttrsFile = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($dlqAttrsFile, '{"MessageRetentionPeriod":"1209600"}', [System.Text.UTF8Encoding]::new($false))
    $DlqUrl = aws sqs create-queue --queue-name $DlqName --attributes "file://$dlqAttrsFile" --region $AwsRegion --query "QueueUrl" --output text
    if ($LASTEXITCODE -ne 0) { throw "Falha ao criar DLQ." }
} finally {
    Remove-Item $dlqAttrsFile -ErrorAction SilentlyContinue
}
$DlqArn = aws sqs get-queue-attributes --queue-url $DlqUrl --attribute-names QueueArn --region $AwsRegion --query "Attributes.QueueArn" --output text

Write-Host "3/6 Criando Fila SQS principal ($QueueName) com Long Polling (20s)..." -ForegroundColor Yellow
$redrivePolicy = "{`"deadLetterTargetArn`":`"$DlqArn`",`"maxReceiveCount`":`"3`"}"
$queueAttrsJson = @{
    ReceiveMessageWaitTimeSeconds = "20"
    VisibilityTimeout             = "60"
    RedrivePolicy                 = $redrivePolicy
} | ConvertTo-Json -Compress

$queueAttrsFile = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($queueAttrsFile, $queueAttrsJson, [System.Text.UTF8Encoding]::new($false))
    $QueueUrl = aws sqs create-queue --queue-name $QueueName --attributes "file://$queueAttrsFile" --region $AwsRegion --query "QueueUrl" --output text
    if ($LASTEXITCODE -ne 0) { throw "Falha ao criar fila SQS principal." }
} finally {
    Remove-Item $queueAttrsFile -ErrorAction SilentlyContinue
}
$QueueArn = aws sqs get-queue-attributes --queue-url $QueueUrl --attribute-names QueueArn --region $AwsRegion --query "Attributes.QueueArn" --output text

Write-Host "4/6 Configurando IAM Role ($RoleName)..." -ForegroundColor Yellow
$trustPolicy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
$roleExists = $true
try {
    $RoleArn = aws iam get-role --role-name $RoleName --query "Role.Arn" --output text 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $RoleArn) { $roleExists = $false }
} catch {
    $roleExists = $false
}

if (-not $roleExists) {
    $trustPolicyFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($trustPolicyFile, $trustPolicy, [System.Text.UTF8Encoding]::new($false))
        $RoleArn = aws iam create-role --role-name $RoleName --assume-role-policy-document "file://$trustPolicyFile" --query "Role.Arn" --output text
        if ($LASTEXITCODE -ne 0) { throw "Falha ao criar IAM Role." }
    } finally {
        Remove-Item $trustPolicyFile -ErrorAction SilentlyContinue
    }
    aws iam attach-role-policy --role-name $RoleName --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    aws iam attach-role-policy --role-name $RoleName --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
    Write-Host "Aguardando propagacao da IAM Role (10s)..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 10
}

Write-Host "5/6 Configurando CloudWatch Log Group com retencao de 7 dias (Always Free)..." -ForegroundColor Yellow
try {
    aws logs create-log-group --log-group-name $LogGroup --region $AwsRegion 2>$null
} catch {}
aws logs put-retention-policy --log-group-name $LogGroup --retention-in-days 7 --region $AwsRegion

Write-Host "6/6 Publicando AWS Lambda ($AppName) diretamente via ZIP (sem S3)..." -ForegroundColor Yellow
$envVarsJson = @{
    Variables = @{
        SMTP_HOST     = $env:SMTP_HOST
        SMTP_PORT     = $SmtpPort
        SMTP_USERNAME = $env:SMTP_USERNAME
        SMTP_PASSWORD = $env:SMTP_PASSWORD
        SMTP_FROM     = $SmtpFrom
        SMTP_AUTH     = $SmtpAuth
        SMTP_STARTTLS = $SmtpStartTls
        SMTP_SSL      = $SmtpSsl
    }
} | ConvertTo-Json -Compress

$lambdaExists = $true
try {
    aws lambda get-function --function-name $AppName --region $AwsRegion >$null 2>&1
    if ($LASTEXITCODE -ne 0) { $lambdaExists = $false }
} catch {
    $lambdaExists = $false
}

$envTmpFile = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($envTmpFile, $envVarsJson, [System.Text.UTF8Encoding]::new($false))

    if (-not $lambdaExists) {
        aws lambda create-function `
            --function-name $AppName `
            --runtime java21 `
            --architectures arm64 `
            --role $RoleArn `
            --handler $Handler `
            --zip-file "fileb://$JarPath" `
            --timeout 30 `
            --memory-size 512 `
            --environment "file://$envTmpFile" `
            --region $AwsRegion | Out-Null
    } else {
        aws lambda update-function-code `
            --function-name $AppName `
            --zip-file "fileb://$JarPath" `
            --region $AwsRegion | Out-Null

        aws lambda wait function-updated --function-name $AppName --region $AwsRegion

        aws lambda update-function-configuration `
            --function-name $AppName `
            --timeout 30 `
            --memory-size 512 `
            --environment "file://$envTmpFile" `
            --region $AwsRegion | Out-Null
    }
} finally {
    Remove-Item $envTmpFile -ErrorAction SilentlyContinue
}

# Vincula a fila SQS ao Lambda (se ainda nao existir)
$existingMapping = aws lambda list-event-source-mappings `
    --function-name $AppName `
    --event-source-arn $QueueArn `
    --region $AwsRegion `
    --query "EventSourceMappings[0].UUID" `
    --output text

if (-not $existingMapping -or $existingMapping -eq "None") {
    aws lambda create-event-source-mapping `
        --function-name $AppName `
        --event-source-arn $QueueArn `
        --batch-size 10 `
        --maximum-batching-window-in-seconds 5 `
        --function-response-types "ReportBatchItemFailures" `
        --scaling-config "MaximumConcurrency=2" `
        --region $AwsRegion | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Falha ao vincular SQS ao Lambda." }
}

Write-Host "`nDeploy concluido com sucesso (100% AWS Always Free)!" -ForegroundColor Green
Write-Host "SQS Queue URL: $QueueUrl" -ForegroundColor Cyan
Write-Host "SQS Queue ARN: $QueueArn" -ForegroundColor Cyan
Write-Host "Lambda Function: $AppName ($AwsRegion)" -ForegroundColor Cyan
