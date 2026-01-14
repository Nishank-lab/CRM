# Cloud Deployment Guide - CRM Application

## Overview
This guide provides instructions for deploying the CRM application to AWS cloud environment.

## Cloud Readiness Fixes Applied

### 1. Configuration Management
- ✅ Replaced hardcoded database credentials with environment variables
- ✅ Externalized all configuration using `${ENV_VAR:default}` pattern
- ✅ Added HikariCP connection pooling for cloud database connections
- ✅ Enabled actuator security for production
- ✅ Updated DDL mode from `create-drop` to `validate` for production safety

### 2. File System Dependencies
- ✅ Replaced local file system writes with in-memory byte arrays
- ✅ Added AWS S3 integration for PDF storage
- ✅ Deprecated JFileChooser (incompatible with cloud) in favor of web uploads
- ✅ Implemented MultipartFile-based file handling

### 3. Framework Upgrades
- ✅ Upgraded Spring Boot from 1.5.10 to 2.7.18 (latest stable 2.x)
- ✅ Upgraded Java from 8 to 11
- ✅ Updated Thymeleaf security integration to Spring Security 5
- ✅ Replaced deprecated `WebSecurityConfigurerAdapter` with `SecurityFilterChain`

### 4. Logging and Monitoring
- ✅ Replaced `System.out.println` with SLF4J structured logging
- ✅ Added correlation IDs (MDC) for distributed tracing
- ✅ Implemented JSON structured logging for CloudWatch
- ✅ Added AWS X-Ray integration for distributed tracing
- ✅ Added CloudWatch metrics export

### 5. Session Management
- ✅ Added Spring Session with Redis for distributed sessions
- ✅ Externalized session configuration
- ✅ Made SecurityContext cloud-compatible

### 6. Security
- ✅ Enabled actuator security by default
- ✅ Updated security configuration to modern patterns
- ✅ Added health check endpoints for load balancers

### 7. Build and Deployment
- ✅ Created multi-stage Dockerfile for optimized container images
- ✅ Added health checks for container orchestration
- ✅ Created AWS ECS task definition
- ✅ Added auto-scaling configuration

## Environment Variables

### Required (Production)
```bash
DB_URL=jdbc:mysql://your-rds-endpoint:3306/crm?useSSL=true
DB_USERNAME=your-db-username
DB_PASSWORD=your-db-password
AWS_S3_BUCKET=your-s3-bucket-name
AWS_REGION=us-east-1
REDIS_HOST=your-redis-endpoint
REDIS_PASSWORD=your-redis-password
```

### Optional (with defaults)
```bash
PORT=8080
DDL_AUTO=validate
SESSION_STORE_TYPE=redis
THYMELEAF_CACHE=true
PDF_STORAGE_ENABLED=true
ACTUATOR_SECURITY_ENABLED=true
LOG_LEVEL_ROOT=INFO
LOG_LEVEL_APP=INFO
```

## Pre-Deployment Checklist

### 1. AWS Resources Setup
- [ ] Create RDS MySQL instance (Multi-AZ recommended)
- [ ] Create ElastiCache Redis cluster
- [ ] Create S3 bucket for PDF storage
- [ ] Create ECR repository for Docker images
- [ ] Create ECS cluster (Fargate)
- [ ] Create Application Load Balancer
- [ ] Configure AWS Secrets Manager for credentials
- [ ] Set up CloudWatch Logs group
- [ ] Configure X-Ray daemon (optional)

### 2. Database Migration
- [ ] Run database schema initialization (if needed)
- [ ] Update `DDL_AUTO` to `validate` or `none` in production
- [ ] Consider using Flyway or Liquibase for migrations

### 3. Security Configuration
- [ ] Configure security groups
- [ ] Set up VPC and subnets
- [ ] Configure SSL/TLS certificates
- [ ] Set up IAM roles and policies

## Deployment Steps

### 1. Build Docker Image
```bash
cd /path/to/crm-app
docker build -t crm-app:latest .
```

### 2. Push to ECR
```bash
# Authenticate to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Tag image
docker tag crm-app:latest ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/crm-app:latest

# Push image
docker push ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/crm-app:latest
```

### 3. Deploy to ECS
```bash
# Update task definition
aws ecs register-task-definition --cli-input-json file://aws-deployment.yml

# Update service
aws ecs update-service \
  --cluster crm-cluster \
  --service crm-service \
  --force-new-deployment
```

### 4. Verify Deployment
```bash
# Check service status
aws ecs describe-services --cluster crm-cluster --services crm-service

# Check logs
aws logs tail /ecs/crm-app --follow

# Test health endpoint
curl https://your-alb-endpoint.com/actuator/health
```

## Monitoring and Operations

### CloudWatch Logs
- Log group: `/ecs/crm-app`
- Logs are in JSON format for easy parsing
- Correlation IDs included for request tracing

### CloudWatch Metrics
- Namespace: `CRM-Application`
- Custom metrics exported via Micrometer
- ECS service metrics (CPU, Memory, etc.)

### X-Ray Tracing
- Distributed tracing enabled
- View traces in AWS X-Ray console
- Correlate with CloudWatch Logs using trace IDs

### Health Checks
- Endpoint: `/actuator/health`
- Used by ALB and ECS
- Returns: `{"status":"UP"}` when healthy

## Scaling

### Auto-Scaling Policies
- CPU-based: Target 70%
- Memory-based: Target 80%
- Min instances: 2
- Max instances: 10

### Manual Scaling
```bash
aws ecs update-service \
  --cluster crm-cluster \
  --service crm-service \
  --desired-count 5
```

## Rollback Procedure

### Using ECS Circuit Breaker
- Automatic rollback on deployment failures
- Monitors CloudWatch alarms

### Manual Rollback
```bash
# List previous task definitions
aws ecs list-task-definitions --family-prefix crm-app

# Update service to previous version
aws ecs update-service \
  --cluster crm-cluster \
  --service crm-service \
  --task-definition crm-app:PREVIOUS_VERSION
```

## Cost Optimization

1. **Use Fargate Spot** for non-production (70% cost savings)
2. **Right-size containers** based on actual usage
3. **Enable ECS Container Insights** selectively
4. **Use NAT Gateway efficiently** or use VPC endpoints
5. **Enable S3 lifecycle policies** for old PDFs

## Troubleshooting

### Application won't start
- Check CloudWatch Logs for errors
- Verify environment variables in task definition
- Check security group allows traffic
- Verify RDS and Redis are accessible

### High latency
- Check RDS connection pool settings
- Verify Redis session store connectivity
- Review CloudWatch metrics for bottlenecks
- Check ALB target health

### Database connection errors
- Verify security groups
- Check RDS endpoint and port
- Verify credentials in Secrets Manager
- Check connection pool settings

## Additional Resources

- [AWS ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [Spring Boot on AWS](https://spring.io/guides/gs/spring-boot-aws/)
- [Twelve-Factor App Methodology](https://12factor.net/)
