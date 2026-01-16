@echo off
setlocal enabledelayedexpansion

echo =====================================
echo AWS ECS Fargate Deployment Script
echo =====================================
echo.

REM Gather deployment configuration
echo === AWS Configuration ===
set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter ECS Cluster Name: "
set /p VPC_ID="Enter VPC ID: "
set /p SUBNETS_INPUT="Enter Subnet IDs (comma-separated, at least 2): "
set /p SECURITY_GROUP="Enter Security Group ID: "
set /p IMAGE_URI="Enter ECR Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/crm-app:latest): "
echo.

REM Parse subnets
for /f "tokens=1,2 delims=," %%a in ("!SUBNETS_INPUT!") do (
    set SUBNET_1=%%a
    set SUBNET_2=%%b
)
set SUBNET_1=!SUBNET_1: =!
set SUBNET_2=!SUBNET_2: =!

REM Get AWS Account ID
echo Retrieving AWS Account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%i
echo AWS Account ID: !ACCOUNT_ID!
echo.

REM Check/create ECS cluster
echo Checking if ECS cluster exists...
aws ecs describe-clusters --clusters !CLUSTER_NAME! --region !AWS_REGION! --query "clusters[0].clusterName" --output text >nul 2>&1

if !ERRORLEVEL! neq 0 (
    echo Creating ECS cluster: !CLUSTER_NAME!
    aws ecs create-cluster --cluster-name !CLUSTER_NAME! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECS cluster.
        exit /b 1
    )
    echo ECS cluster created successfully.
) else (
    echo ECS cluster already exists: !CLUSTER_NAME!
)
echo.

REM Load balancer configuration
set /p NEED_LB="Do you need a load balancer for this service? (y/n): "
echo.

if /i "!NEED_LB!"=="y" (
    echo Creating Application Load Balancer and Target Group...
    
    REM Create Application Load Balancer
    for /f "delims=" %%i in ('powershell -Command "Get-Date -Format 'yyyyMMddHHmmss'"') do set TIMESTAMP=%%i
    set ALB_NAME=crm-app-alb-!TIMESTAMP!
    echo Creating ALB: !ALB_NAME!
    
    for /f "delims=" %%i in ('aws elbv2 create-load-balancer --name !ALB_NAME! --subnets !SUBNET_1! !SUBNET_2! --security-groups !SECURITY_GROUP! --scheme internet-facing --type application --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text') do set ALB_ARN=%%i
    
    echo ALB created: !ALB_ARN!
    
    REM Get ALB DNS name
    for /f "delims=" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns !ALB_ARN! --region !AWS_REGION! --query "LoadBalancers[0].DNSName" --output text') do set ALB_DNS=%%i
    
    echo ALB DNS Name: !ALB_DNS!
    
    REM Create Target Group
    set TG_NAME=crm-app-tg-!TIMESTAMP!
    echo Creating Target Group: !TG_NAME!
    
    for /f "delims=" %%i in ('aws elbv2 create-target-group --name !TG_NAME! --protocol HTTP --port 8080 --vpc-id !VPC_ID! --target-type ip --health-check-enabled --health-check-path /actuator/health --health-check-interval-seconds 30 --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text') do set TARGET_GROUP_ARN=%%i
    
    echo Target Group created: !TARGET_GROUP_ARN!
    
    REM Create Listener
    echo Creating ALB Listener...
    aws elbv2 create-listener --load-balancer-arn !ALB_ARN! --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=!TARGET_GROUP_ARN! --region !AWS_REGION!
    
    echo ALB Listener created successfully.
    echo.
) else (
    echo Skipping load balancer creation.
    set TARGET_GROUP_ARN=
    echo.
)

REM Replace placeholders in task-definition.json
echo Preparing ECS task definition...
copy ecs\task-definition.json ecs\task-definition-temp.json >nul

powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{IMAGE_URI}}','!IMAGE_URI!' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{AWS_REGION}}','!AWS_REGION!' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{ACCOUNT_ID}}','!ACCOUNT_ID!' | Set-Content ecs\task-definition-temp.json"

echo Task definition prepared.
echo.

REM Register task definition
echo Registering ECS task definition...
for /f "delims=" %%i in ('aws ecs register-task-definition --cli-input-json file://ecs/task-definition-temp.json --region !AWS_REGION! --query "taskDefinition.taskDefinitionArn" --output text') do set TASK_DEF_ARN=%%i

echo Task definition registered: !TASK_DEF_ARN!
echo.

REM Prepare service definition
echo Preparing ECS service definition...
copy ecs\service-definition.json ecs\service-definition-temp.json >nul

powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{CLUSTER_NAME}}','!CLUSTER_NAME!' | Set-Content ecs\service-definition-temp.json"
powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{SUBNET_1}}','!SUBNET_1!' | Set-Content ecs\service-definition-temp.json"
powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{SUBNET_2}}','!SUBNET_2!' | Set-Content ecs\service-definition-temp.json"
powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{SECURITY_GROUP}}','!SECURITY_GROUP!' | Set-Content ecs\service-definition-temp.json"

if /i "!NEED_LB!"=="y" (
    powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{TARGET_GROUP_ARN}}','!TARGET_GROUP_ARN!' | Set-Content ecs\service-definition-temp.json"
) else (
    REM Remove loadBalancers section if no ALB
    powershell -Command "$content = Get-Content ecs\service-definition-temp.json -Raw; $content = $content -replace '(?s),\s*\"loadBalancers\":\s*\[.*?\],',''; $content = $content -replace ',\s*\"healthCheckGracePeriodSeconds\":\s*\d+',''; $content | Set-Content ecs\service-definition-temp.json"
)

echo Service definition prepared.
echo.

REM Check if service exists
set SERVICE_NAME=crm-app-service
echo Checking if ECS service exists...
for /f "delims=" %%i in ('aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[0].serviceName" --output text 2^>nul') do set EXISTING_SERVICE=%%i

if "!EXISTING_SERVICE!"=="None" (
    echo Creating new ECS service...
    aws ecs create-service --cli-input-json file://ecs/service-definition-temp.json --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECS service.
        exit /b 1
    )
    echo ECS service created successfully.
) else (
    echo Updating existing ECS service...
    aws ecs update-service --cluster !CLUSTER_NAME! --service !SERVICE_NAME! --task-definition !TASK_DEF_ARN! --force-new-deployment --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to update ECS service.
        exit /b 1
    )
    echo ECS service updated successfully.
)
echo.

REM Wait for service stability
echo Waiting for service to stabilize (this may take several minutes)...
aws ecs wait services-stable --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!

echo Service is stable.
echo.

REM Verify deployment
echo Verifying deployment...
aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount}"

echo.
echo =====================================
echo Deployment completed successfully!
echo =====================================
echo Cluster: !CLUSTER_NAME!
echo Service: !SERVICE_NAME!
echo Task Definition: !TASK_DEF_ARN!

if /i "!NEED_LB!"=="y" (
    echo Load Balancer DNS: !ALB_DNS!
    echo Access your application at: http://!ALB_DNS!
)

echo CloudWatch Logs: /ecs/crm-app-task
echo =====================================
echo.
echo To view logs:
echo aws logs tail /ecs/crm-app-task --follow --region !AWS_REGION!
echo.

REM Cleanup temporary files
del /q ecs\task-definition-temp.json ecs\service-definition-temp.json 2>nul

endlocal