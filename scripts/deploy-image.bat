@echo off
setlocal enabledelayedexpansion

echo ================================================
echo    AWS ECS Fargate Deployment Script
echo ================================================
echo.

set PROJECT_NAME=crm-db-check-comp
set TASK_FAMILY=crm-db-check-comp-task
set SERVICE_NAME=crm-db-check-comp-service

set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter ECS Cluster Name: "

echo.
echo Checking if ECS cluster exists...
aws ecs describe-clusters --clusters !CLUSTER_NAME! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Cluster does not exist. Creating ECS cluster: !CLUSTER_NAME!
    aws ecs create-cluster --cluster-name !CLUSTER_NAME! --region !AWS_REGION!
)

echo.
echo --- Network Configuration ---
set /p VPC_ID="Enter VPC ID: "
set /p SUBNET_IDS="Enter Subnet IDs (comma-separated): "
set /p SECURITY_GROUP="Enter Security Group ID: "

echo.
set /p IMAGE_URI="Enter Docker Image URI: "

echo.
set /p NEED_LB="Do you need a load balancer for this service? (y/n): "

if /i "!NEED_LB!"=="y" (
    echo.
    echo Creating Application Load Balancer and Target Group...
    
    set SUBNET_ARRAY=!SUBNET_IDS:,= !
    
    for /f "tokens=*" %%i in ('aws elbv2 create-load-balancer --name !PROJECT_NAME!-alb --subnets !SUBNET_ARRAY! --security-groups !SECURITY_GROUP! --scheme internet-facing --type application --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text 2^>nul') do set ALB_ARN=%%i
    
    if "!ALB_ARN!"=="" (
        echo Load balancer may already exist, retrieving existing ARN...
        for /f "tokens=*" %%i in ('aws elbv2 describe-load-balancers --names !PROJECT_NAME!-alb --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text') do set ALB_ARN=%%i
    )
    
    echo Load Balancer ARN: !ALB_ARN!
    
    for /f "tokens=*" %%i in ('aws elbv2 create-target-group --name !PROJECT_NAME!-tg --protocol HTTP --port 8080 --vpc-id !VPC_ID! --target-type ip --health-check-path /appinfo/health --health-check-interval-seconds 30 --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text 2^>nul') do set TARGET_GROUP_ARN=%%i
    
    if "!TARGET_GROUP_ARN!"=="" (
        echo Target group may already exist, retrieving existing ARN...
        for /f "tokens=*" %%i in ('aws elbv2 describe-target-groups --names !PROJECT_NAME!-tg --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text') do set TARGET_GROUP_ARN=%%i
    )
    
    echo Target Group ARN: !TARGET_GROUP_ARN!
    
    aws elbv2 create-listener --load-balancer-arn !ALB_ARN! --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=!TARGET_GROUP_ARN! --region !AWS_REGION! >nul 2>&1
    
    set USE_LOAD_BALANCER=true
) else (
    set USE_LOAD_BALANCER=false
    set TARGET_GROUP_ARN=
)

echo.
echo Getting AWS Account ID...
for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%i
echo Account ID: !ACCOUNT_ID!

echo.
echo Updating ECS task definition...
copy ecs\task-definition.json ecs\task-definition-temp.json >nul
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{IMAGE_URI}}','!IMAGE_URI!' -replace '{{AWS_REGION}}','!AWS_REGION!' -replace '{{ACCOUNT_ID}}','!ACCOUNT_ID!' | Set-Content ecs\task-definition-temp.json"

echo Registering ECS task definition...
for /f "tokens=*" %%i in ('aws ecs register-task-definition --cli-input-json file://ecs/task-definition-temp.json --region !AWS_REGION! --query "taskDefinition.taskDefinitionArn" --output text') do set TASK_DEF_ARN=%%i
echo Task Definition ARN: !TASK_DEF_ARN!

echo.
echo Updating ECS service definition...
copy ecs\service-definition.json ecs\service-definition-temp.json >nul

set SUBNET_JSON=["!SUBNET_IDS:,=","!"]
powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{CLUSTER_NAME}}','!CLUSTER_NAME!' -replace '[\"{{SUBNET_1}}\", \"{{SUBNET_2}}\"]','!SUBNET_JSON!' -replace '{{SECURITY_GROUP}}','!SECURITY_GROUP!' | Set-Content ecs\service-definition-temp.json"

if "!USE_LOAD_BALANCER!"=="true" (
    powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{TARGET_GROUP_ARN}}','!TARGET_GROUP_ARN!' | Set-Content ecs\service-definition-temp.json"
) else (
    powershell -Command "(Get-Content ecs\service-definition-temp.json) | Where-Object {$_ -notmatch 'loadBalancers' -and $_ -notmatch 'healthCheckGracePeriodSeconds'} | Set-Content ecs\service-definition-temp.json"
)

echo.
echo Checking if ECS service exists...
for /f "tokens=*" %%i in ('aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[0].serviceName" --output text') do set SERVICE_EXISTS=%%i

if "!SERVICE_EXISTS!"=="!SERVICE_NAME!" (
    echo Service exists. Updating ECS service...
    aws ecs update-service --cluster !CLUSTER_NAME! --service !SERVICE_NAME! --task-definition !TASK_DEF_ARN! --region !AWS_REGION! --force-new-deployment
) else (
    echo Service does not exist. Creating ECS service...
    aws ecs create-service --cli-input-json file://ecs/service-definition-temp.json --region !AWS_REGION!
)

echo.
echo Waiting for service to stabilize...
aws ecs wait services-stable --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!

echo.
echo Verifying deployment...
aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[0].[serviceName,status,runningCount,desiredCount]" --output table

if "!USE_LOAD_BALANCER!"=="true" (
    echo.
    echo Getting Load Balancer DNS name...
    for /f "tokens=*" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns !ALB_ARN! --region !AWS_REGION! --query "LoadBalancers[0].DNSName" --output text') do set ALB_DNS=%%i
    echo.
    echo Application URL: http://!ALB_DNS!
)

echo.
echo ================================================
echo    Deployment Completed Successfully!
echo ================================================
echo Cluster: !CLUSTER_NAME!
echo Service: !SERVICE_NAME!
echo Task Definition: !TASK_DEF_ARN!
echo CloudWatch Logs: /ecs/!PROJECT_NAME!
echo.

del ecs\task-definition-temp.json ecs\service-definition-temp.json >nul 2>&1

endlocal
