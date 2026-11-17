<#
.SYNOPSIS
    Envia uma mensagem de teste para a fila SQS para disparar o envio de email.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$To,
    [string]$Subject   = "Teste SQS Email Messenger",
    [string]$Body      = "<h1>Funcionando!</h1><p>Email enviado via Amazon SQS + AWS Lambda (Always Free).</p>",
    [bool]$Html        = $true,
    [string]$AwsRegion = $(if ($env:AWS_REGION) { $env:AWS_REGION } else { "us-east-1" }),
    [string]$AppName   = $(if ($env:APP_NAME) { $env:APP_NAME } else { "sqs-email-messenger" })
)

$ErrorActionPreference = "Stop"
$QueueUrl = aws sqs get-queue-url --queue-name "$AppName-queue" --region $AwsRegion --query "QueueUrl" --output text

$payload = @{
    to      = $To
    subject = $Subject
    body    = $Body
    html    = $Html
} | ConvertTo-Json -Compress

$tempFile = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($tempFile, $payload, [System.Text.UTF8Encoding]::new($false))
    aws sqs send-message --queue-url $QueueUrl --message-body "file://$tempFile" --region $AwsRegion
} finally {
    Remove-Item $tempFile -ErrorAction SilentlyContinue
}
Write-Host "Mensagem enviada para $QueueUrl" -ForegroundColor Green
