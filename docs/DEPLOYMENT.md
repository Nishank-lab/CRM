# Spring Boot CRM Application - AWS ECS Fargate Deployment Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Local Development Setup](#local-development-setup)
3. [AWS ECS Fargate Prerequisites](#aws-ecs-fargate-prerequisites)
4. [Building and Pushing Docker Image](#building-and-pushing-docker-image)
5. [ECS Fargate Deployment](#ecs-fargate-deployment)
6. [Configuration Management](#configuration-management)
7. [Monitoring and Logging](#monitoring-and-logging)
8. [Troubleshooting](#troubleshooting)
9. [Scaling and Management](#scaling-and-management)
10. [Security Considerations](#security-considerations)

---

## Prerequisites

### Required Software
- **Docker** (v20.10 or later)
- **Docker Compose** (v2.0 or later)
- **AWS CLI** (v2.x)
- **Java 8** (for local development)
- **Maven 3.6+** (for local development)

### AWS Account Requirements
- Active AWS account with appropriate permissions
- IAM user with ECS, ECR, EC2, and CloudWatch permissions
- AWS CLI configured with credentials

### Verify Installations
```bash
# Check Docker
docker --version

# Check Docker Compose
docker-compose --version

# Check AWS CLI
aws --version

# Verify AWS credentials
aws sts get-caller-identity
```

---

## Local Development Setup

### 1. Clone and Build Application
```bash
# Navigate to project directory
cd /path/to/MContainer

# Build with Maven
mvn clean package -DskipTests

# Run locally
java -jar target/*.jar

# Access application
http://localhost:8080
```

### 2. Local Docker Development

#### Build Docker Image Locally
```bash
# Build image
docker build -t crm-app:local .

# Run container
docker run -d -p 8080:8080 \
  -e DB_HOST=mysql-host \
  -e DB_PORT=3306 \
  -e DB_NAME=crm \
  -e DB_USERNAME=root \
  -e DB_PASSWORD=password \
  crm-app:local

# Check logs
docker logs -f <container-id>
```

#### Using Docker Compose
```bash
# Start application
docker-compose up -d

# View logs
docker-compose logs -f crm-app

# Stop application
docker-compose down

# Rebuild and restart
docker-compose up -d --build
```

### 3. Environment Variables for Local Development
Create a `.env` file:
```env
DB_HOST=your-mysql-host
DB_PORT=3306
DB_NAME=crm
DB_USERNAME=your-username
DB_PASSWORD=your-password
```

---

## AWS ECS Fargate Prerequisites

### 1. VPC and Networking Setup

#### Create VPC (if needed)
```bash
# Create VPC
aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region us-east-1

# Create two subnets in different AZs
aws ec2 create-subnet \
  --vpc-id vpc-xxxxxx \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a

aws ec2 create-subnet \
  --vpc-id vpc-xxxxxx \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b

# Create Internet Gateway
aws ec2 create-internet-gateway

# Attach to VPC
aws ec2 attach-internet-gateway \
  --vpc-id vpc-xxxxxx \
  --internet-gateway-id igw-xxxxxx
```

#### Create Security Group
```bash
# Create security group
aws ec2 create-security-group \
  --group-name crm-app-sg \
  --description "Security group for CRM app" \
  --vpc-id vpc-xxxxxx

# Allow inbound HTTP traffic (port 8080)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxx \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0

# Allow inbound traffic from ALB (if using load balancer)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxx \
  --protocol tcp \
  --port 8080 \
  --source-group sg-alb-xxxxxx
```

### 2. IAM Roles Setup

#### ECS Task Execution Role
Required for ECS to pull images from ECR and write logs to CloudWatch.

```bash
# Create trust policy file (ecs-task-execution-trust-policy.json)
cat > ecs-task-execution-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://ecs-task-execution-trust-policy.json

# Attach AWS managed policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

#### ECS Task Role (Optional)
Required for application to access AWS services (S3, DynamoDB, etc.).

```bash
# Create task role
aws iam create-role \
  --role-name ecsTaskRole \
  --assume-role-policy-document file://ecs-task-execution-trust-policy.json

# Attach custom policies as needed
aws iam attach-role-policy \
  --role-name ecsTaskRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

### 3. CloudWatch Log Group Setup
```bash
# Create log group
aws logs create-log-group \
  --log-group-name /ecs/crm-app-task \
  --region us-east-1

# Set retention policy (optional, e.g., 7 days)
aws logs put-retention-policy \
  --log-group-name /ecs/crm-app-task \
  --retention-in-days 7
```

### 4. RDS MySQL Database Setup (Recommended)
```bash
# Create RDS MySQL instance
aws rds create-db-instance \
  --db-instance-identifier crm-db \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version 8.0.35 \
  --master-username admin \
  --master-user-password YourSecurePassword123! \
  --allocated-storage 20 \
  --vpc-security-group-ids sg-xxxxxx \
  --db-subnet-group-name your-db-subnet-group \
  --backup-retention-period 7 \
  --publicly-accessible false

# Get endpoint after creation
aws rds describe-db-instances \
  --db-instance-identifier crm-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text
```

---

## Building and Pushing Docker Image

### Option 1: Using AWS ECR

#### Step 1: Run build-push script
```bash
# Linux/macOS
cd scripts
chmod +x build-push.sh
./build-push.sh

# Windows
cd scripts
build-push.bat
```

#### Step 2: Follow interactive prompts
1. Select `1` for AWS ECR
2. Enter AWS Region (e.g., `us-east-1`)
3. Enter AWS Account ID (e.g., `123456789012`)
4. Enter ECR Repository Name (e.g., `crm-app`)
5. Enter image tag (e.g., `v1.0.0` or `latest`)

The script will:
- Authenticate with ECR
- Create repository if it doesn't exist
- Build Docker image
- Push image to ECR

### Option 2: Using Docker Hub

#### Run build-push script
```bash
# Linux/macOS
./scripts/build-push.sh

# Windows
scripts\build-push.bat
```

Follow prompts:
1. Select `2` for Docker Hub
2. Enter Docker Hub Username
3. Enter Docker Hub Password/Token
4. Enter image tag

### Manual Build and Push (Alternative)

#### AWS ECR
```bash
# Set variables
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
REPO_NAME=crm-app
IMAGE_TAG=v1.0.0

# Authenticate
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Create repository
aws ecr create-repository --repository-name $REPO_NAME --region $AWS_REGION

# Build and push
docker build -t $REPO_NAME:$IMAGE_TAG .
docker tag $REPO_NAME:$IMAGE_TAG \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG
```

---

## ECS Fargate Deployment

### Understanding ECS Components

#### Task Definition
- Defines container configuration (image, CPU, memory, ports, environment variables)
- Specifies IAM roles for task execution and application permissions
- Configures logging to CloudWatch
- Sets health check parameters

#### Service
- Maintains desired number of running tasks
- Integrates with Application Load Balancer
- Handles rolling updates and deployments
- Provides auto-scaling capabilities

#### Cluster
- Logical grouping of ECS services and tasks
- Can contain multiple services
- Provides centralized management

### ECS Fargate CPU and Memory Configurations

**Valid Fargate CPU/Memory Combinations:**

| CPU (vCPU) | Memory (MB) Options |
|------------|---------------------|
| 256 (.25)  | 512, 1024, 2048 |
| 512 (.5)   | 1024, 2048, 3072, 4096 |
| 1024 (1)   | 2048, 3072, 4096, 5120, 6144, 7168, 8192 |
| 2048 (2)   | 4096-16384 (increments of 1024) |
| 4096 (4)   | 8192-30720 (increments of 1024) |

**Default Configuration (task-definition.json):**
- CPU: `512` (.5 vCPU)
- Memory: `1024` MB

**Modify if needed based on application requirements.**

### Deployment Process

#### Step 1: Prepare Configuration Files

Ensure you have:
- `ecs/task-definition.json` - Task configuration
- `ecs/service-definition.json` - Service configuration

#### Step 2: Update Task Definition Environment Variables

Edit `ecs/task-definition.json` to configure database connection:

```json
"environment": [
  {
    "name": "DB_HOST",
    "value": "your-rds-endpoint.rds.amazonaws.com"
  },
  {
    "name": "DB_PORT",
    "value": "3306"
  },
  {
    "name": "DB_NAME",
    "value": "crm"
  },
  {
    "name": "DB_USERNAME",
    "value": "admin"
  },
  {
    "name": "DB_PASSWORD",
    "value": "your-secure-password"
  }
]
```

**Security Best Practice:** Use AWS Secrets Manager or SSM Parameter Store for sensitive values.

#### Step 3: Run Deployment Script

```bash
# Linux/macOS
cd scripts
chmod +x deploy-image.sh
./deploy-image.sh

# Windows
cd scripts
deploy-image.bat
```

#### Step 4: Follow Interactive Prompts

1. **AWS Region**: Enter your target region (e.g., `us-east-1`)
2. **ECS Cluster Name**: Enter cluster name (e.g., `crm-cluster`)
3. **VPC ID**: Enter VPC ID (e.g., `vpc-xxxxxx`)
4. **Subnet IDs**: Enter at least 2 subnet IDs, comma-separated (e.g., `subnet-xxxxx,subnet-yyyyy`)
5. **Security Group ID**: Enter security group ID (e.g., `sg-xxxxxx`)
6. **ECR Image URI**: Enter full image URI (e.g., `123456789012.dkr.ecr.us-east-1.amazonaws.com/crm-app:v1.0.0`)
7. **Load Balancer**: Answer `y` or `n` for Application Load Balancer creation

#### What the Script Does

1. **Creates/verifies ECS cluster**
2. **Creates Application Load Balancer** (if requested):
   - Creates ALB with provided subnets and security group
   - Creates Target Group (target-type: `ip` for Fargate)
   - Configures health checks on `/actuator/health`
   - Creates HTTP listener on port 80
3. **Registers task definition** with placeholders replaced
4. **Creates or updates ECS service**:
   - Creates new service if doesn't exist
   - Updates existing service with new task definition
5. **Waits for service stability**
6. **Displays deployment information**

#### Step 5: Verify Deployment

```bash
# Check service status
aws ecs describe-services \
  --cluster crm-cluster \
  --services crm-app-service \
  --region us-east-1

# List running tasks
aws ecs list-tasks \
  --cluster crm-cluster \
  --service-name crm-app-service \
  --region us-east-1

# View task details
aws ecs describe-tasks \
  --cluster crm-cluster \
  --tasks <task-arn> \
  --region us-east-1
```

---

## Configuration Management

### Environment Variables

**Application Configuration:**
- `JAVA_OPTS`: JVM options (memory, GC settings)
- `SPRING_PROFILES_ACTIVE`: Active Spring profile (e.g., `production`)
- `DB_HOST`: MySQL database host
- `DB_PORT`: MySQL database port
- `DB_NAME`: Database name
- `DB_USERNAME`: Database username
- `DB_PASSWORD`: Database password
- `TZ`: Timezone setting (default: `UTC`)

### Using AWS Secrets Manager

#### Create Secret
```bash
aws secretsmanager create-secret \
  --name crm-app/db-password \
  --secret-string "YourSecurePassword123!" \
  --region us-east-1
```

#### Update Task Definition to Use Secrets

In `ecs/task-definition.json`, replace environment variable with secret:

```json
"secrets": [
  {
    "name": "DB_PASSWORD",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:crm-app/db-password-xxxxxx"
  }
]
```

#### Grant Task Execution Role Access
```bash
# Create policy
cat > secrets-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-east-1:123456789012:secret:crm-app/*"
      ]
    }
  ]
}
EOF

# Attach to execution role
aws iam put-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-name SecretsManagerPolicy \
  --policy-document file://secrets-policy.json
```

---

## Monitoring and Logging

### CloudWatch Logs

#### View Logs
```bash
# Tail logs in real-time
aws logs tail /ecs/crm-app-task --follow --region us-east-1

# View logs from last hour
aws logs tail /ecs/crm-app-task --since 1h --region us-east-1

# Filter logs by pattern
aws logs filter-log-events \
  --log-group-name /ecs/crm-app-task \
  --filter-pattern "ERROR" \
  --region us-east-1
```

#### CloudWatch Console
1. Navigate to CloudWatch → Log groups
2. Select `/ecs/crm-app-task`
3. View log streams for each task

### Application Monitoring

#### Spring Boot Actuator Endpoints
- **Health Check**: `http://<alb-dns>/actuator/health`
- **Metrics**: `http://<alb-dns>/actuator/metrics`
- **Info**: `http://<alb-dns>/actuator/info`

#### CloudWatch Metrics

**ECS Service Metrics:**
- CPUUtilization
- MemoryUtilization
- Running task count

**ALB Metrics:**
- TargetResponseTime
- RequestCount
- HealthyHostCount
- UnHealthyHostCount

#### Create CloudWatch Alarms

```bash
# High CPU alarm
aws cloudwatch put-metric-alarm \
  --alarm-name crm-app-high-cpu \
  --alarm-description "Alarm when CPU exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=ServiceName,Value=crm-app-service Name=ClusterName,Value=crm-cluster

# Unhealthy target alarm
aws cloudwatch put-metric-alarm \
  --alarm-name crm-app-unhealthy-targets \
  --metric-name UnHealthyHostCount \
  --namespace AWS/ApplicationELB \
  --statistic Average \
  --period 60 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 2
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. Task Fails to Start

**Symptoms:**
- Tasks transition to STOPPED state immediately
- "Essential container exited" error

**Solutions:**
```bash
# Check task stopped reason
aws ecs describe-tasks \
  --cluster crm-cluster \
  --tasks <task-arn> \
  --query 'tasks[0].stoppedReason'

# Check CloudWatch logs for application errors
aws logs tail /ecs/crm-app-task --since 1h

# Common causes:
- Database connection failure (check DB_HOST, credentials)
- Insufficient memory (increase memory in task definition)
- Application startup failure (check JAVA_OPTS)
```

#### 2. Service Unhealthy in Target Group

**Symptoms:**
- ALB health checks failing
- HTTP 502/504 errors

**Solutions:**
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>

# Verify health check endpoint
curl http://<alb-dns>/actuator/health

# Common causes:
- Health check path incorrect (should be /actuator/health)
- Application not listening on port 8080
- Security group blocking ALB → ECS traffic
- Health check grace period too short (increase to 300s)
```

#### 3. Task Running but Not Accessible

**Symptoms:**
- Task shows as RUNNING
- Cannot access application via ALB

**Solutions:**
```bash
# Verify security group rules
aws ec2 describe-security-groups --group-ids <sg-id>

# Check if task has public IP (if assignPublicIp: ENABLED)
aws ecs describe-tasks \
  --cluster crm-cluster \
  --tasks <task-arn> \
  --query 'tasks[0].attachments[0].details'

# Common causes:
- Security group not allowing inbound traffic on port 8080
- Target group not associated with ALB listener
- Subnets not routed to Internet Gateway
```

#### 4. CPU/Memory Errors

**Error:** "InvalidParameterException: No Fargate configuration exists for given values"

**Solution:**
Use valid CPU/memory combinations:
```json
// Valid combinations
{"cpu": "512", "memory": "1024"}  // OK
{"cpu": "512", "memory": "1536"}  // INVALID
{"cpu": "1024", "memory": "2048"} // OK
```

#### 5. ECR Authentication Issues

**Error:** "CannotPullContainerError: pull image manifest has been retried"

**Solutions:**
```bash
# Verify execution role has ECR permissions
aws iam get-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-name AmazonECSTaskExecutionRolePolicy

# Check if image exists in ECR
aws ecr describe-images \
  --repository-name crm-app \
  --region us-east-1

# Verify image URI format
# Correct: 123456789012.dkr.ecr.us-east-1.amazonaws.com/crm-app:v1.0.0
```

### Debugging Commands

```bash
# Get task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster crm-cluster \
  --service-name crm-app-service \
  --query 'taskArns[0]' \
  --output text)

# Describe task
aws ecs describe-tasks \
  --cluster crm-cluster \
  --tasks $TASK_ARN

# Get task logs
LOG_STREAM=$(aws ecs describe-tasks \
  --cluster crm-cluster \
  --tasks $TASK_ARN \
  --query 'tasks[0].containers[0].name' \
  --output text)

aws logs get-log-events \
  --log-group-name /ecs/crm-app-task \
  --log-stream-name ecs/crm-app/$LOG_STREAM
```

---

## Scaling and Management

### Manual Scaling

```bash
# Update desired count
aws ecs update-service \
  --cluster crm-cluster \
  --service crm-app-service \
  --desired-count 4 \
  --region us-east-1
```

### Auto Scaling

#### Step 1: Register Scalable Target
```bash
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/crm-cluster/crm-app-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10 \
  --region us-east-1
```

#### Step 2: Create Scaling Policy (Target Tracking)
```bash
# CPU-based scaling
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/crm-cluster/crm-app-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name cpu-target-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration \
    '{"TargetValue":70.0,"PredefinedMetricSpecification":{"PredefinedMetricType":"ECSServiceAverageCPUUtilization"}}'

# ALB request count scaling
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/crm-cluster/crm-app-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name request-count-target-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration \
    '{"TargetValue":1000.0,"PredefinedMetricSpecification":{"PredefinedMetricType":"ALBRequestCountPerTarget","ResourceLabel":"app/my-alb/xxx/targetgroup/my-tg/yyy"}}'
```

### Blue/Green Deployments

#### Using AWS CodeDeploy

1. **Install CodeDeploy agent** (handled by ECS)
2. **Create deployment configuration**
3. **Update service to use CODE_DEPLOY deployment controller**

```bash
# Create CodeDeploy application
aws deploy create-application \
  --application-name crm-app \
  --compute-platform ECS

# Create deployment group
aws deploy create-deployment-group \
  --application-name crm-app \
  --deployment-group-name crm-app-dg \
  --service-role-arn arn:aws:iam::123456789012:role/CodeDeployRole \
  --ecs-services clusterName=crm-cluster,serviceName=crm-app-service \
  --load-balancer-info targetGroupInfoList=[{name=crm-app-tg}]
```

### Rolling Updates

**Current Configuration (in service-definition.json):**
- `maximumPercent: 200` - Can run up to 2x desired tasks during deployment
- `minimumHealthyPercent: 50` - Must maintain at least 50% of desired tasks

**Update Strategy:**
1. New task definition is registered
2. ECS launches new tasks with new definition
3. Once healthy, old tasks are stopped
4. Process repeats until all tasks updated

---

## Security Considerations

### 1. Container Security

**✅ Implemented:**
- Non-root user in Dockerfile
- Multi-stage build to reduce attack surface
- Minimal base image (Alpine)
- No unnecessary packages installed

**Recommendations:**
- Regularly update base images for security patches
- Scan images with AWS ECR image scanning
- Use specific image tags (not `latest`) in production

### 2. Network Security

**Security Group Rules:**
```bash
# ECS tasks security group
# Allow inbound from ALB only
aws ec2 authorize-security-group-ingress \
  --group-id sg-ecs-tasks \
  --protocol tcp \
  --port 8080 \
  --source-group sg-alb

# ALB security group
# Allow inbound HTTP from internet
aws ec2 authorize-security-group-ingress \
  --group-id sg-alb \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# For HTTPS, add port 443
aws ec2 authorize-security-group-ingress \
  --group-id sg-alb \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0
```

### 3. Secrets Management

**Never hardcode secrets in:**
- Task definitions
- Docker images
- Environment variables (plain text)

**Use:**
- AWS Secrets Manager
- AWS Systems Manager Parameter Store

### 4. IAM Least Privilege

**Task Execution Role** (minimal):
- `AmazonECSTaskExecutionRolePolicy`
- ECR pull permissions
- CloudWatch Logs write permissions
- Secrets Manager read (if using secrets)

**Task Role** (application-specific):
- Only permissions needed by application
- S3 bucket access (specific buckets only)
- DynamoDB table access (specific tables only)

### 5. Encryption

**Enable encryption for:**
- CloudWatch Logs: Use KMS key
- RDS Database: Enable encryption at rest
- Secrets Manager: Encrypted by default
- ALB: Use HTTPS with ACM certificate

### 6. Spring Boot Security

**Recommendations:**
- Keep Spring Boot and dependencies updated
- Configure Spring Security properly
- Disable unnecessary Actuator endpoints in production
- Use strong database passwords
- Enable CSRF protection
- Validate user input

---

## Spring Boot Specific Configuration

### JVM Memory Tuning

**Current Settings (task-definition.json):**
```json
"JAVA_OPTS": "-Xmx768m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"
```

**Explanation:**
- `-Xmx768m`: Maximum heap size 768MB (75% of 1024MB container memory)
- `-Xms256m`: Initial heap size 256MB
- `-XX:+UseContainerSupport`: Respect container memory limits
- `-XX:MaxRAMPercentage=75.0`: Use up to 75% of container memory
- `-Djava.security.egd=file:/dev/./urandom`: Faster startup

**Adjust based on:**
- Fargate task memory allocation
- Application memory requirements
- Expected traffic load

### Spring Profiles

**Production Profile (application-production.yml):**
```yaml
spring:
  profiles:
    active: production
  jpa:
    hibernate:
      ddl-auto: validate  # Never use create-drop in production
  datasource:
    url: jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}?useSSL=true&requireSSL=true
    hikari:
      maximum-pool-size: 10
      minimum-idle: 2
logging:
  level:
    root: INFO
    crm: INFO
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: when-authorized
```

### Health Check Configuration

**Customize health check timeout:**
```yaml
management:
  health:
    db:
      enabled: true
    defaults:
      enabled: false
  endpoint:
    health:
      show-details: when-authorized
      probes:
        enabled: true
```

---

## Cost Optimization

### 1. Right-Size Resources
- Start with CPU: 512, Memory: 1024
- Monitor actual usage in CloudWatch
- Adjust based on metrics

### 2. Use Fargate Spot (for non-critical workloads)
```bash
# Update service to use Fargate Spot
aws ecs update-service \
  --cluster crm-cluster \
  --service crm-app-service \
  --capacity-provider-strategy \
    capacityProvider=FARGATE_SPOT,weight=1,base=0
```

### 3. Optimize Auto Scaling
- Set appropriate min/max capacity
- Use target tracking scaling
- Scale based on actual application metrics

### 4. Log Retention
- Set CloudWatch log retention to 7-30 days
- Export old logs to S3 for archival

### 5. ECR Lifecycle Policies
```bash
# Keep only last 10 images
aws ecr put-lifecycle-policy \
  --repository-name crm-app \
  --lifecycle-policy-text '{"rules":[{"rulePriority":1,"description":"Keep last 10 images","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":10},"action":{"type":"expire"}}]}'
```

---

## Additional Resources

- [AWS ECS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [Spring Boot on AWS](https://spring.io/guides/gs/spring-boot-for-azure/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

---

## Support and Troubleshooting

For issues or questions:
1. Check CloudWatch logs first
2. Review ECS service events
3. Verify security group rules and IAM permissions
4. Consult AWS documentation
5. Contact your DevOps team or AWS Support

---

**Document Version:** 1.0  
**Last Updated:** 2026-01-16  
**Target Platform:** AWS ECS Fargate  
**Application:** Spring Boot 1.5.10 CRM Application