# CRM Application - AWS ECS Fargate Deployment Guide

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Local Development Setup](#local-development-setup)
4. [Building and Pushing Docker Image](#building-and-pushing-docker-image)
5. [AWS ECS Fargate Prerequisites](#aws-ecs-fargate-prerequisites)
6. [ECS Task Definition Explained](#ecs-task-definition-explained)
7. [ECS Service Configuration](#ecs-service-configuration)
8. [Deployment to AWS ECS Fargate](#deployment-to-aws-ecs-fargate)
9. [Configuration Management](#configuration-management)
10. [Monitoring and Logging](#monitoring-and-logging)
11. [Troubleshooting](#troubleshooting)
12. [Scaling and Management](#scaling-and-management)
13. [Security Considerations](#security-considerations)

---

## Overview

This guide provides step-by-step instructions for deploying the CRM (Customer Relationship Management) Spring Boot application to AWS ECS Fargate. The application is containerized using Docker and deployed to a fully managed container orchestration platform.

**Application Details:**
- **Technology**: Spring Boot 1.5.10 with Java 8
- **Framework**: Spring MVC with Thymeleaf templates
- **Database**: MySQL (external, not containerized)
- **Build Tool**: Maven
- **Container Platform**: AWS ECS Fargate
- **Application Port**: 8080
- **Management Endpoints**: /appinfo/health, /appinfo/info

---

## Prerequisites

### Required Software

1. **Docker** (version 20.10 or higher)
   - Download: https://www.docker.com/get-started
   - Verify installation: `docker --version`

2. **AWS CLI** (version 2.x or higher)
   - Download: https://aws.amazon.com/cli/
   - Verify installation: `aws --version`

3. **Git** (for cloning the repository)
   - Download: https://git-scm.com/downloads
   - Verify installation: `git --version`

4. **Maven** (version 3.6 or higher) - for local builds
   - Download: https://maven.apache.org/download.cgi
   - Verify installation: `mvn --version`

### AWS Account Requirements

1. Active AWS account with appropriate permissions
2. AWS CLI configured with credentials:
   ```bash
   aws configure
   ```
   Provide:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region (e.g., us-east-1)
   - Default output format (json)

3. IAM permissions for:
   - ECS (Full access or appropriate policies)
   - EC2 (for networking - VPC, subnets, security groups)
   - ECR (Elastic Container Registry)
   - CloudWatch Logs
   - IAM (for creating/managing roles)
   - Elastic Load Balancing (if using ALB)

---

## Local Development Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd "CRM DB check comp"
```

### 2. Build Application Locally (Optional)

```bash
mvn clean package -DskipTests
```

The JAR file will be created in `target/crm-0.0.1-SNAPSHOT.jar`

### 3. Run Application Locally with Docker Compose

```bash
docker-compose up --build
```

Access the application:
- Application: http://localhost:8080
- Health Check: http://localhost:8080/appinfo/health

**Note**: Ensure MySQL is configured and accessible. Update environment variables in `docker-compose.yml` with your MySQL connection details:
- `DB_URL`: JDBC connection string
- `DB_USERNAME`: Database username
- `DB_PASSWORD`: Database password

### 4. Stop Local Environment

```bash
docker-compose down
```

---

## Building and Pushing Docker Image

### Option 1: Using AWS ECR (Recommended for ECS)

#### Linux/macOS:

```bash
cd scripts
chmod +x build-push.sh
./build-push.sh
```

#### Windows:

```cmd
cd scripts
build-push.bat
```

**Follow the prompts:**
1. Select registry type: `1` (AWS ECR)
2. Enter AWS Region (e.g., `us-east-1`)
3. Enter AWS Account ID (12-digit number)
4. Enter ECR Repository Name (default: `crm-db-check-comp`)
5. Enter image tag (default: `latest`)

The script will:
- Authenticate to AWS ECR
- Create ECR repository if it doesn't exist
- Build the Docker image
- Push the image to ECR
- Display the full image URI (save this for deployment)

**Example Output:**
```
Image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/crm-db-check-comp:latest
```

### Option 2: Using Docker Hub

Follow the same steps but select option `2` for Docker Hub and provide your Docker Hub credentials.

---

## AWS ECS Fargate Prerequisites

### 1. VPC and Networking Setup

**Create or identify existing VPC resources:**

```bash
# List existing VPCs
aws ec2 describe-vpcs --region us-east-1

# List subnets in a VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxxx" --region us-east-1
```

**Required network resources:**
- VPC with internet gateway (for public access)
- At least 2 subnets in different availability zones (for high availability)
- Security group allowing inbound traffic on port 8080 (application port)

### 2. Create Security Group

```bash
# Create security group
aws ec2 create-security-group \
    --group-name crm-ecs-sg \
    --description "Security group for CRM ECS tasks" \
    --vpc-id vpc-xxxxxx \
    --region us-east-1

# Allow inbound traffic on port 8080
aws ec2 authorize-security-group-ingress \
    --group-id sg-xxxxxx \
    --protocol tcp \
    --port 8080 \
    --cidr 0.0.0.0/0 \
    --region us-east-1

# If using ALB, allow traffic from ALB security group
aws ec2 authorize-security-group-ingress \
    --group-id sg-xxxxxx \
    --protocol tcp \
    --port 8080 \
    --source-group sg-alb-xxxxxx \
    --region us-east-1
```

### 3. IAM Roles

**ECS Task Execution Role** (required):

This role allows ECS to pull container images from ECR and send logs to CloudWatch.

```bash
# Create trust policy file
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

**ECS Task Role** (optional, for application permissions):

Create this if your application needs to access other AWS services (S3, RDS, etc.).

```bash
# Create role
aws iam create-role \
    --role-name ecsTaskRole \
    --assume-role-policy-document file://ecs-task-execution-trust-policy.json

# Attach custom policies as needed
```

### 4. CloudWatch Log Group

The deployment script will automatically create the log group, but you can create it manually:

```bash
aws logs create-log-group \
    --log-group-name /ecs/crm-db-check-comp \
    --region us-east-1

# Set retention period (optional, e.g., 7 days)
aws logs put-retention-policy \
    --log-group-name /ecs/crm-db-check-comp \
    --retention-in-days 7 \
    --region us-east-1
```

---

## ECS Task Definition Explained

### Key Components

**Task Definition File**: `ecs/task-definition.json`

```json
{
  "family": "crm-db-check-comp-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::{{ACCOUNT_ID}}:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::{{ACCOUNT_ID}}:role/ecsTaskRole",
  "containerDefinitions": [...]
}
```

### Fargate CPU and Memory Combinations

**Valid combinations** (CPU units : Memory MB):

| CPU | Valid Memory Values (MB) |
|-----|-------------------------|
| 256 | 512, 1024, 2048 |
| 512 | 1024, 2048, 3072, 4096 |
| 1024 | 2048, 3072, 4096, 5120, 6144, 7168, 8192 |
| 2048 | 4096 to 16384 (increments of 1024) |
| 4096 | 8192 to 30720 (increments of 1024) |

**Default configuration**: 
- CPU: 512 (.5 vCPU)
- Memory: 1024 MB (1 GB)

### Container Definition

```json
{
  "name": "crm-db-check-comp",
  "image": "{{IMAGE_URI}}",
  "essential": true,
  "portMappings": [{
    "containerPort": 8080,
    "protocol": "tcp"
  }],
  "environment": [
    {"name": "SPRING_PROFILES_ACTIVE", "value": "docker"},
    {"name": "JAVA_OPTS", "value": "-Xmx768m -Xms384m ..."},
    {"name": "DB_URL", "value": "jdbc:mysql://..."},
    ...
  ],
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/crm-db-check-comp",
      "awslogs-region": "{{AWS_REGION}}",
      "awslogs-stream-prefix": "ecs"
    }
  }
}
```

### Environment Variables

**Update these values in `ecs/task-definition.json` before deployment:**

- `DB_URL`: MySQL connection string (update host, port, database name)
- `DB_USERNAME`: Database username
- `DB_PASSWORD`: Database password (consider using AWS Secrets Manager)
- `JAVA_OPTS`: JVM options (adjust heap size based on memory allocation)

---

## ECS Service Configuration

### Service Definition File

**File**: `ecs/service-definition.json`

```json
{
  "serviceName": "crm-db-check-comp-service",
  "cluster": "{{CLUSTER_NAME}}",
  "taskDefinition": "crm-db-check-comp-task",
  "desiredCount": 2,
  "launchType": "FARGATE",
  "networkConfiguration": {
    "awsvpcConfiguration": {
      "subnets": ["{{SUBNET_1}}", "{{SUBNET_2}}"],
      "securityGroups": ["{{SECURITY_GROUP}}"],
      "assignPublicIp": "ENABLED"
    }
  },
  "loadBalancers": [...],
  "deploymentConfiguration": {
    "maximumPercent": 200,
    "minimumHealthyPercent": 50
  }
}
```

### Key Configuration Parameters

- **desiredCount**: Number of task instances to run (default: 2 for HA)
- **assignPublicIp**: Set to "ENABLED" for public subnets, "DISABLED" for private with NAT
- **maximumPercent**: Maximum percentage of tasks during deployment (200 = double capacity)
- **minimumHealthyPercent**: Minimum healthy tasks during deployment (50 = half capacity)

### Load Balancer Configuration

The deployment script offers to create an Application Load Balancer:
- Creates ALB in specified subnets
- Creates Target Group with `target-type: ip` (required for Fargate)
- Configures health checks on `/appinfo/health`
- Creates HTTP listener on port 80

---

## Deployment to AWS ECS Fargate

### Step-by-Step Deployment

#### Linux/macOS:

```bash
cd scripts
chmod +x deploy-image.sh
./deploy-image.sh
```

#### Windows:

```cmd
cd scripts
deploy-image.bat
```

### Deployment Prompts

The script will prompt for:

1. **AWS Region**: e.g., `us-east-1`
2. **ECS Cluster Name**: e.g., `crm-cluster` (will be created if doesn't exist)
3. **VPC ID**: e.g., `vpc-0123456789abcdef0`
4. **Subnet IDs**: e.g., `subnet-111,subnet-222` (comma-separated, 2+ subnets)
5. **Security Group ID**: e.g., `sg-0123456789abcdef0`
6. **Docker Image URI**: Full ECR image URI from build step
7. **Load Balancer**: `y` or `n` (yes to create ALB, no for direct task access)

### Deployment Process

The script will:

1. Check/create ECS cluster
2. (Optional) Create Application Load Balancer and Target Group
3. Retrieve AWS Account ID
4. Update task definition with provided values
5. Register task definition with ECS
6. Update service definition with network configuration
7. Create or update ECS service
8. Wait for service to reach stable state
9. Display deployment summary and URLs

### Verify Deployment

```bash
# Check service status
aws ecs describe-services \
    --cluster crm-cluster \
    --services crm-db-check-comp-service \
    --region us-east-1

# List running tasks
aws ecs list-tasks \
    --cluster crm-cluster \
    --service-name crm-db-check-comp-service \
    --region us-east-1

# Get task details
aws ecs describe-tasks \
    --cluster crm-cluster \
    --tasks <task-arn> \
    --region us-east-1
```

### Access the Application

**With Load Balancer:**
```
http://<ALB-DNS-NAME>
```

**Without Load Balancer:**

Get task public IP:
```bash
aws ecs describe-tasks \
    --cluster crm-cluster \
    --tasks <task-arn> \
    --region us-east-1 \
    --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
    --output text

aws ec2 describe-network-interfaces \
    --network-interface-ids <eni-id> \
    --query 'NetworkInterfaces[0].Association.PublicIp' \
    --output text
```

Access: `http://<TASK-PUBLIC-IP>:8080`

---

## Configuration Management

### Environment Variables

Environment variables are configured in the task definition. To update:

1. Edit `ecs/task-definition.json`
2. Update environment values in `containerDefinitions[0].environment`
3. Re-run deployment script

### Using AWS Secrets Manager (Recommended)

For sensitive data (database passwords, API keys):

1. **Store secret in AWS Secrets Manager:**

```bash
aws secretsmanager create-secret \
    --name crm/db-password \
    --secret-string "your-secure-password" \
    --region us-east-1
```

2. **Update task definition to use secrets:**

```json
"secrets": [
  {
    "name": "DB_PASSWORD",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:crm/db-password"
  }
]
```

3. **Grant task execution role access:**

```bash
aws iam attach-role-policy \
    --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
```

### Spring Profiles

The application uses Spring profiles for environment-specific configuration:

- `docker`: Default profile for containerized deployment
- Configure additional profiles by adding `application-{profile}.properties` files
- Set `SPRING_PROFILES_ACTIVE` environment variable to activate profiles

---

## Monitoring and Logging

### CloudWatch Logs

**View logs:**

```bash
# Using AWS CLI
aws logs tail /ecs/crm-db-check-comp --follow --region us-east-1

# Filter logs
aws logs filter-log-events \
    --log-group-name /ecs/crm-db-check-comp \
    --filter-pattern "ERROR" \
    --region us-east-1
```

**AWS Console:**
1. Navigate to CloudWatch > Log groups
2. Find `/ecs/crm-db-check-comp`
3. Browse log streams (one per task)

### CloudWatch Metrics

ECS automatically sends metrics to CloudWatch:

- **Service-level**: CPUUtilization, MemoryUtilization
- **Cluster-level**: Task counts, service counts

**View metrics:**

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name CPUUtilization \
    --dimensions Name=ServiceName,Value=crm-db-check-comp-service Name=ClusterName,Value=crm-cluster \
    --start-time 2026-01-14T00:00:00Z \
    --end-time 2026-01-14T23:59:59Z \
    --period 3600 \
    --statistics Average \
    --region us-east-1
```

### Application Health Checks

Spring Boot Actuator endpoints:
- **Health**: `http://<app-url>/appinfo/health`
- **Info**: `http://<app-url>/appinfo/info`
- **Metrics**: `http://<app-url>/appinfo/metrics` (if enabled)

### Setting Up Alarms

```bash
# CPU utilization alarm
aws cloudwatch put-metric-alarm \
    --alarm-name crm-high-cpu \
    --alarm-description "Alert when CPU exceeds 80%" \
    --metric-name CPUUtilization \
    --namespace AWS/ECS \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --dimensions Name=ServiceName,Value=crm-db-check-comp-service Name=ClusterName,Value=crm-cluster \
    --region us-east-1
```

---

## Troubleshooting

### Common Issues

#### 1. Task fails to start

**Symptoms**: Tasks transition from PENDING to STOPPED without running

**Possible causes**:
- Image not found or not accessible
- Invalid CPU/memory combination
- Insufficient permissions (execution role)
- Network configuration issues

**Resolution**:
```bash
# Check stopped task reason
aws ecs describe-tasks \
    --cluster crm-cluster \
    --tasks <task-arn> \
    --region us-east-1 \
    --query 'tasks[0].stoppedReason'

# Verify image exists in ECR
aws ecr describe-images \
    --repository-name crm-db-check-comp \
    --region us-east-1

# Check execution role permissions
aws iam get-role --role-name ecsTaskExecutionRole
aws iam list-attached-role-policies --role-name ecsTaskExecutionRole
```

#### 2. Cannot pull image from ECR

**Error**: "CannotPullContainerError: Error response from daemon: pull access denied"

**Resolution**:
- Verify executionRoleArn has ECR permissions
- Ensure image URI is correct
- Check ECR repository policy

```bash
# Grant ECR access to execution role
aws iam attach-role-policy \
    --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

#### 3. Network issues - tasks cannot reach internet

**Symptoms**: Database connection failures, image pull errors

**Resolution**:
- Verify subnets have route to internet gateway (public) or NAT gateway (private)
- Check security group allows outbound traffic
- Ensure `assignPublicIp` is ENABLED for public subnets

```bash
# Check route table
aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=<subnet-id>" \
    --region us-east-1

# Verify internet gateway or NAT gateway exists
```

#### 4. Health check failures

**Symptoms**: Tasks marked as unhealthy, ALB removes targets

**Resolution**:
- Verify application is running and accessible on port 8080
- Check health endpoint returns 200 OK
- Increase health check grace period
- Review application logs for errors

```bash
# Test health endpoint from within VPC
curl http://<task-ip>:8080/appinfo/health

# Update health check grace period
aws ecs update-service \
    --cluster crm-cluster \
    --service crm-db-check-comp-service \
    --health-check-grace-period-seconds 300 \
    --region us-east-1
```

#### 5. Database connection errors

**Symptoms**: Application logs show "Cannot connect to database"

**Resolution**:
- Verify DB_URL, DB_USERNAME, DB_PASSWORD are correct
- Ensure database security group allows inbound from ECS security group
- Check database is accessible from VPC
- Verify MySQL is running and accepting connections

```bash
# Test database connectivity from ECS task
aws ecs execute-command \
    --cluster crm-cluster \
    --task <task-id> \
    --container crm-db-check-comp \
    --interactive \
    --command "/bin/sh"

# Inside container:
# apt-get update && apt-get install -y telnet
# telnet <mysql-host> 3306
```

#### 6. Out of Memory errors

**Symptoms**: Tasks restart frequently, OOM errors in logs

**Resolution**:
- Increase task memory allocation
- Adjust JVM heap size in JAVA_OPTS
- Monitor memory usage and adjust accordingly

```bash
# Update task definition with more memory
# Edit ecs/task-definition.json:
"memory": "2048",
"environment": [
  {"name": "JAVA_OPTS", "value": "-Xmx1536m -Xms768m ..."}
]

# Re-deploy
./deploy-image.sh
```

### Debugging Commands

```bash
# Get service events (recent activity)
aws ecs describe-services \
    --cluster crm-cluster \
    --services crm-db-check-comp-service \
    --region us-east-1 \
    --query 'services[0].events[:10]'

# Get task stopped reason
aws ecs describe-tasks \
    --cluster crm-cluster \
    --tasks <task-arn> \
    --region us-east-1 \
    --query 'tasks[0].{Reason:stoppedReason,Exit:containers[0].exitCode}'

# View CloudWatch logs
aws logs tail /ecs/crm-db-check-comp --follow --region us-east-1

# Check target health (if using ALB)
aws elbv2 describe-target-health \
    --target-group-arn <target-group-arn> \
    --region us-east-1
```

---

## Scaling and Management

### Manual Scaling

```bash
# Scale up to 5 tasks
aws ecs update-service \
    --cluster crm-cluster \
    --service crm-db-check-comp-service \
    --desired-count 5 \
    --region us-east-1

# Scale down to 1 task
aws ecs update-service \
    --cluster crm-cluster \
    --service crm-db-check-comp-service \
    --desired-count 1 \
    --region us-east-1
```

### Auto Scaling

**Set up Application Auto Scaling:**

```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --resource-id service/crm-cluster/crm-db-check-comp-service \
    --scalable-dimension ecs:service:DesiredCount \
    --min-capacity 2 \
    --max-capacity 10 \
    --region us-east-1

# Create target tracking policy (CPU-based)
aws application-autoscaling put-scaling-policy \
    --service-namespace ecs \
    --resource-id service/crm-cluster/crm-db-check-comp-service \
    --scalable-dimension ecs:service:DesiredCount \
    --policy-name crm-cpu-scaling \
    --policy-type TargetTrackingScaling \
    --target-tracking-scaling-policy-configuration file://scaling-policy.json \
    --region us-east-1
```

**scaling-policy.json:**
```json
{
  "TargetValue": 70.0,
  "PredefinedMetricSpecification": {
    "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
  },
  "ScaleOutCooldown": 60,
  "ScaleInCooldown": 300
}
```

### Blue/Green Deployments

**Using AWS CodeDeploy:**

1. Create CodeDeploy application and deployment group
2. Configure target groups (blue and green)
3. Update service to use CODE_DEPLOY deployment controller
4. Deploy new task definitions via CodeDeploy

### Rolling Updates

ECS performs rolling updates automatically when you update the service:

```bash
# Deploy new task definition
aws ecs update-service \
    --cluster crm-cluster \
    --service crm-db-check-comp-service \
    --task-definition crm-db-check-comp-task:2 \
    --force-new-deployment \
    --region us-east-1
```

Deployment respects `deploymentConfiguration`:
- **maximumPercent: 200** - allows up to double capacity during deployment
- **minimumHealthyPercent: 50** - ensures at least half capacity is maintained

---

## Security Considerations

### 1. Use Non-Root User in Container

The Dockerfile creates and uses a non-root user (`appuser`) for running the application.

### 2. Secrets Management

- **Never hardcode credentials** in Docker images or task definitions
- Use AWS Secrets Manager or AWS Systems Manager Parameter Store
- Grant least-privilege IAM permissions

### 3. Network Security

- Use private subnets with NAT gateway when possible
- Restrict security group rules to minimum required
- Use ALB to avoid direct task exposure
- Enable VPC Flow Logs for network monitoring

### 4. IAM Best Practices

- Use separate task execution role and task role
- Apply least-privilege permissions
- Regularly audit and rotate credentials
- Enable CloudTrail for API audit logging

### 5. Container Image Security

- Scan images for vulnerabilities (AWS ECR has built-in scanning)
- Use specific image tags (not `latest` in production)
- Regularly update base images and dependencies
- Sign images for verification

```bash
# Enable ECR image scanning
aws ecr put-image-scanning-configuration \
    --repository-name crm-db-check-comp \
    --image-scanning-configuration scanOnPush=true \
    --region us-east-1

# View scan results
aws ecr describe-image-scan-findings \
    --repository-name crm-db-check-comp \
    --image-id imageTag=latest \
    --region us-east-1
```

### 6. Application Security

- Keep Spring Boot and dependencies updated
- Enable Spring Security (already included in project)
- Use HTTPS/TLS for ALB listeners
- Implement proper authentication and authorization
- Validate and sanitize user inputs

### 7. Compliance and Auditing

- Enable AWS Config for resource compliance
- Use AWS Security Hub for centralized security findings
- Implement logging and monitoring
- Regular security assessments and penetration testing

---

## Technology-Specific Notes

### Spring Boot 1.5.x Considerations

1. **Actuator Endpoints**: Management endpoints are at `/appinfo/*` (custom context path)
2. **Graceful Shutdown**: Spring Boot 1.5 doesn't support graceful shutdown natively
3. **Security**: Spring Security 4.x is used; ensure proper configuration
4. **Java 8**: Use compatible libraries and dependencies

### JVM Tuning for Containers

**Current settings in Dockerfile:**
```
JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"
```

**Recommendations:**
- `-Xmx` and `-Xms`: Set to 75% of container memory
- `-XX:+UseContainerSupport`: Enables container-aware JVM (Java 8u191+)
- `-XX:MaxRAMPercentage=75.0`: Limits heap to 75% of available memory
- `-Djava.security.egd`: Use non-blocking entropy for faster startup

**For larger memory allocations:**
```bash
# Task memory: 2048 MB
# Recommended JAVA_OPTS:
JAVA_OPTS="-Xmx1536m -Xms768m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
```

### Database Connection Pooling

Configure HikariCP (default in Spring Boot) for optimal performance:

```properties
# application.properties
spring.datasource.hikari.maximum-pool-size=10
spring.datasource.hikari.minimum-idle=5
spring.datasource.hikari.connection-timeout=30000
spring.datasource.hikari.idle-timeout=600000
spring.datasource.hikari.max-lifetime=1800000
```

### Logging Configuration

For structured JSON logging (better for CloudWatch):

```xml
<!-- logback-spring.xml -->
<configuration>
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder"/>
    </appender>
    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
    </root>
</configuration>
```

---

## Additional Resources

- **AWS ECS Documentation**: https://docs.aws.amazon.com/ecs/
- **AWS Fargate Documentation**: https://docs.aws.amazon.com/AmazonECS/latest/userguide/what-is-fargate.html
- **Spring Boot Documentation**: https://docs.spring.io/spring-boot/docs/1.5.x/reference/html/
- **Docker Best Practices**: https://docs.docker.com/develop/dev-best-practices/
- **AWS Well-Architected Framework**: https://aws.amazon.com/architecture/well-architected/

---

## Support and Contact

For issues or questions:
1. Check CloudWatch logs for application errors
2. Review ECS service events for deployment issues
3. Consult AWS support for platform-specific problems
4. Refer to Spring Boot community for framework questions

---

**Last Updated**: 2026-01-14
