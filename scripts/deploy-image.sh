#!/bin/bash

# Enable strict error handling
set -e
set -o pipefail

echo "====================================="
echo "AWS ECS Fargate Deployment Script"
echo "====================================="
echo ""

# Gather deployment configuration
echo "=== AWS Configuration ==="
read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
read -p "Enter ECS Cluster Name: " CLUSTER_NAME
read -p "Enter VPC ID: " VPC_ID
read -p "Enter Subnet IDs (comma-separated, at least 2): " SUBNETS_INPUT
read -p "Enter Security Group ID: " SECURITY_GROUP
read -p "Enter ECR Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/crm-app:latest): " IMAGE_URI
echo ""

# Convert comma-separated subnets to array
IFS=',' read -ra SUBNETS <<< "$SUBNETS_INPUT"
SUBNET_1=$(echo "${SUBNETS[0]}" | xargs)
SUBNET_2=$(echo "${SUBNETS[1]}" | xargs)

# Get AWS Account ID
echo "Retrieving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"
echo ""

# Check/create ECS cluster
echo "Checking if ECS cluster exists..."
if ! aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" --query "clusters[0].clusterName" --output text 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    echo "Creating ECS cluster: $CLUSTER_NAME"
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
    echo "ECS cluster created successfully."
else
    echo "ECS cluster already exists: $CLUSTER_NAME"
fi
echo ""

# Load balancer configuration
read -p "Do you need a load balancer for this service? (y/n): " NEED_LB
echo ""

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo "Creating Application Load Balancer and Target Group..."
    
    # Create Application Load Balancer
    ALB_NAME="crm-app-alb-$(date +%s)"
    echo "Creating ALB: $ALB_NAME"
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "$ALB_NAME" \
        --subnets ${SUBNETS[@]} \
        --security-groups "$SECURITY_GROUP" \
        --scheme internet-facing \
        --type application \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    echo "ALB created: $ALB_ARN"
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    echo "ALB DNS Name: $ALB_DNS"
    
    # Create Target Group (target-type: ip for Fargate)
    TG_NAME="crm-app-tg-$(date +%s)"
    echo "Creating Target Group: $TG_NAME"
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "$TG_NAME" \
        --protocol HTTP \
        --port 8080 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-enabled \
        --health-check-path /actuator/health \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    echo "Target Group created: $TARGET_GROUP_ARN"
    
    # Create Listener
    echo "Creating ALB Listener..."
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION"
    
    echo "ALB Listener created successfully."
    echo ""
else
    echo "Skipping load balancer creation."
    TARGET_GROUP_ARN=""
    echo ""
fi

# Replace placeholders in task-definition.json
echo "Preparing ECS task definition..."
cp ecs/task-definition.json ecs/task-definition-temp.json

sed -i "s|{{IMAGE_URI}}|$IMAGE_URI|g" ecs/task-definition-temp.json
sed -i "s|{{AWS_REGION}}|$AWS_REGION|g" ecs/task-definition-temp.json
sed -i "s|{{ACCOUNT_ID}}|$ACCOUNT_ID|g" ecs/task-definition-temp.json

echo "Task definition prepared."
echo ""

# Register task definition
echo "Registering ECS task definition..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file://ecs/task-definition-temp.json \
    --region "$AWS_REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "Task definition registered: $TASK_DEF_ARN"
echo ""

# Prepare service definition
echo "Preparing ECS service definition..."
cp ecs/service-definition.json ecs/service-definition-temp.json

sed -i "s|{{CLUSTER_NAME}}|$CLUSTER_NAME|g" ecs/service-definition-temp.json
sed -i "s|{{SUBNET_1}}|$SUBNET_1|g" ecs/service-definition-temp.json
sed -i "s|{{SUBNET_2}}|$SUBNET_2|g" ecs/service-definition-temp.json
sed -i "s|{{SECURITY_GROUP}}|$SECURITY_GROUP|g" ecs/service-definition-temp.json

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    sed -i "s|{{TARGET_GROUP_ARN}}|$TARGET_GROUP_ARN|g" ecs/service-definition-temp.json
else
    # Remove loadBalancers section if no ALB
    sed -i '/"loadBalancers":/,/],/d' ecs/service-definition-temp.json
    sed -i '/"healthCheckGracePeriodSeconds":/d' ecs/service-definition-temp.json
fi

echo "Service definition prepared."
echo ""

# Check if service exists
SERVICE_NAME="crm-app-service"
echo "Checking if ECS service exists..."
EXISTING_SERVICE=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0].serviceName' \
    --output text 2>/dev/null || echo "None")

if [ "$EXISTING_SERVICE" = "None" ] || [ "$EXISTING_SERVICE" = "" ]; then
    echo "Creating new ECS service..."
    aws ecs create-service \
        --cli-input-json file://ecs/service-definition-temp.json \
        --region "$AWS_REGION"
    echo "ECS service created successfully."
else
    echo "Updating existing ECS service..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$TASK_DEF_ARN" \
        --force-new-deployment \
        --region "$AWS_REGION"
    echo "ECS service updated successfully."
fi
echo ""

# Wait for service stability
echo "Waiting for service to stabilize (this may take several minutes)..."
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION"

echo "Service is stable."
echo ""

# Verify deployment
echo "Verifying deployment..."
aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

echo ""
echo "====================================="
echo "Deployment completed successfully!"
echo "====================================="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Task Definition: $TASK_DEF_ARN"

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo "Load Balancer DNS: $ALB_DNS"
    echo "Access your application at: http://$ALB_DNS"
fi

echo "CloudWatch Logs: /ecs/crm-app-task"
echo "====================================="
echo ""
echo "To view logs:"
echo "aws logs tail /ecs/crm-app-task --follow --region $AWS_REGION"
echo ""

# Cleanup temporary files
rm -f ecs/task-definition-temp.json ecs/service-definition-temp.json