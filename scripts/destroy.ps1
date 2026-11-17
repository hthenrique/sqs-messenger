<#
.SYNOPSIS
    Remove todos os recursos criados na AWS pelo deploy.ps1.
#>
param(
    [string]$AwsRegion = $(if ($env:AWS_REGION) { $env:AWS_REGION } else { "us-east-1" }),
    [string]$AppName   = $(if ($env:APP_NAME) { $env:APP_NAME } else { "sqs-email-messenger" })
)

$ErrorActionPreference = "Continue"
$QueueName = "$AppName-queue"
$DlqName   = "$AppName-dlq"
$RoleName  = "$AppName-lambda-role"
$LogGroup  = "/aws/lambda/$AppName"

Write-Host "Removendo event source mappings..." -ForegroundColor Yellow
$uuids = aws lambda list-event-source-mappings --function-name $AppName --region $AwsRegion --query "EventSourceMappings[].UUID" --output text 2>$null
if ($uuids) {
    foreach ($uuid in $uuids -split "\s+") {
        if ($uuid -and $uuid -ne "None") {
            aws lambda delete-event-source-mapping --uuid $uuid --region $AwsRegion | Out-Null
        }
    }
}

Write-Host "Removendo Lambda ($AppName)..." -ForegroundColor Yellow
aws lambda delete-function --function-name $AppName --region $AwsRegion 2>$null

Write-Host "Removendo Log Group ($LogGroup)..." -ForegroundColor Yellow
aws logs delete-log-group --log-group-name $LogGroup --region $AwsRegion 2>$null

Write-Host "Removendo Filas SQS ($QueueName, $DlqName)..." -ForegroundColor Yellow
$qUrl = aws sqs get-queue-url --queue-name $QueueName --region $AwsRegion --query "QueueUrl" --output text 2>$null
if ($qUrl) { aws sqs delete-queue --queue-url $qUrl --region $AwsRegion }

$dlqUrl = aws sqs get-queue-url --queue-name $DlqName --region $AwsRegion --query "QueueUrl" --output text 2>$null
if ($dlqUrl) { aws sqs delete-queue --queue-url $dlqUrl --region $AwsRegion }

Write-Host "Removendo IAM Role ($RoleName)..." -ForegroundColor Yellow
aws iam detach-role-policy --role-name $RoleName --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>$null
aws iam detach-role-policy --role-name $RoleName --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole" 2>$null
aws iam delete-role --role-name $RoleName 2>$null

Write-Host "Recursos removidos com sucesso." -ForegroundColor Green
