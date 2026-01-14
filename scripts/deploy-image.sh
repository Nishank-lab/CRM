#!/bin/bash
set -e
set -o pipefail

echo "================================================"
echo "   AWS ECS Fargate Deployment Script"
echo "================================================"
echo ""

# Project configuration
PROJECT_NAME="crm-db-check-comp"
TASK_FAMILY="crm-db-check-comp-task"
SERVICE_NAME="crm-db-check-comp-service"

# Prompt for AWS configuration
read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
read -p "Enter ECS Cluster Name: " CLUSTER_NAME

echo ""
echo "Checking if ECS cluster exists..."
aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || {
    echo "Cluster does not exist. Creating ECS cluster: $CLUSTER_NAME"
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
}

echo ""
echo "--- Network Configuration ---"
read -p "Enter VPC ID: " VPC_ID
read -p "Enter Subnet IDs (comma-separated, e.g., subnet-xxx,subnet-yyy): " SUBNET_IDS
read -p "Enter Security Group ID: " SECURITY_GROUP

echo ""
read -p "Enter Docker Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/crm:latest): " IMAGE_URI

echo ""
read -p "Do you need a load balancer for this service? (y/n): " NEED_LB

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Creating Application Load Balancer and Target Group..."
    
    # Convert comma-separated subnets to space-separated
    SUBNET_ARRAY=$(echo "$SUBNET_IDS" | tr ',' ' ')
    
    # Create Application Load Balancer
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "${PROJECT_NAME}-alb" \
        --subnets $SUBNET_ARRAY \
        --security-groups "$SECURITY_GROUP" \
        --scheme internet-facing \
        --type application \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$ALB_ARN" ]; then
        echo "Load balancer may already exist, retrieving existing ARN..."
        ALB_ARN=$(aws elbv2 describe-load-balancers \
            --names "${PROJECT_NAME}-alb" \
            --region "$AWS_REGION" \
            --query 'LoadBalancers[0].LoadBalancerArn' \
            --output text)
    fi
    
    echo "Load Balancer ARN: $ALB_ARN"
    
    # Create Target Group (CRITICAL: use target-type ip for Fargate)
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "${PROJECT_NAME}-tg" \
        --protocol HTTP \
        --port 8080 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-path "/appinfo/health" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$TARGET_GROUP_ARN" ]; then
        echo "Target group may already exist, retrieving existing ARN..."
        TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
            --names "${PROJECT_NAME}-tg" \
            --region "$AWS_REGION" \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text)
    fi
    
    echo "Target Group ARN: $TARGET_GROUP_ARN"
    
    # Create listener if it doesn't exist
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" >/dev/null 2>&1 || echo "Listener may already exist"
    
    echo "Load balancer configuration complete"
    USE_LOAD_BALANCER="true"
else
    USE_LOAD_BALANCER="false"
    TARGET_GROUP_ARN=""
fi

echo ""
echo "Getting AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

echo ""
echo "Updating ECS task definition with provided values..."

# Replace placeholders in task definition
cp ecs/task-definition.json ecs/task-definition-temp.json
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g" ecs/task-definition-temp.json
sed -i "s|{{AWS_REGION}}|${AWS_REGION}|g" ecs/task-definition-temp.json
sed -i "s|{{ACCOUNT_ID}}|${ACCOUNT_ID}|g" ecs/task-definition-temp.json

echo "Registering ECS task definition..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file://ecs/task-definition-temp.json \
    --region "$AWS_REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "Task Definition ARN: $TASK_DEF_ARN"

echo ""
echo "Updating ECS service definition with provided values..."

# Convert comma-separated subnets to JSON array
SUBNET_JSON=$(echo "$SUBNET_IDS" | sed 's/,/","/g' | sed 's/^/["/' | sed 's/$/"]/')

# Replace placeholders in service definition
cp ecs/service-definition.json ecs/service-definition-temp.json
sed -i "s|{{CLUSTER_NAME}}|${CLUSTER_NAME}|g" ecs/service-definition-temp.json
sed -i "s|\"{{SUBNET_1}}\", \"{{SUBNET_2}}\"|${SUBNET_JSON}|g" ecs/service-definition-temp.json
sed -i "s|{{SECURITY_GROUP}}|${SECURITY_GROUP}|g" ecs/service-definition-temp.json

# Handle load balancer configuration
if [ "$USE_LOAD_BALANCER" = "true" ]; then
    sed -i "s|{{TARGET_GROUP_ARN}}|${TARGET_GROUP_ARN}|g" ecs/service-definition-temp.json
else
    # Remove loadBalancers section if no load balancer is needed
    sed -i '/"loadBalancers"/,/],/d' ecs/service-definition-temp.json
    sed -i '/"healthCheckGracePeriodSeconds"/d' ecs/service-definition-temp.json
fi

echo ""
echo "Checking if ECS service exists..."
SERVICE_EXISTS=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0].serviceName' \
    --output text)

if [ "$SERVICE_EXISTS" = "$SERVICE_NAME" ]; then
    echo "Service exists. Updating ECS service..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$TASK_DEF_ARN" \
        --region "$AWS_REGION" \
        --force-new-deployment
else
    echo "Service does not exist. Creating ECS service..."
    aws ecs create-service \
        --cli-input-json file://ecs/service-definition-temp.json \
        --region "$AWS_REGION"
fi

echo ""
echo "Waiting for service to stabilize..."
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION"

echo ""
echo "Verifying deployment..."
aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0].[serviceName,status,runningCount,desiredCount]' \
    --output table

if [ "$USE_LOAD_BALANCER" = "true" ]; then
    echo ""
    echo "Getting Load Balancer DNS name..."
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    echo ""
    echo "Application URL: http://$ALB_DNS"
fi

echo ""
echo "================================================"
echo "   Deployment Completed Successfully!"
echo "================================================"
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Task Definition: $TASK_DEF_ARN"
echo "CloudWatch Logs: /ecs/$PROJECT_NAME"
echo ""

# Clean up temporary files
rm -f ecs/task-definition-temp.json ecs/service-definition-temp.json
