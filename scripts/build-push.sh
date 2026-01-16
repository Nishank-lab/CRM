#!/bin/bash

# Enable strict error handling
set -e
set -o pipefail

echo "====================================="
echo "Docker Build and Push Script"
echo "====================================="
echo ""

# Get project name from current directory
PROJECT_NAME=$(basename "$(pwd)")
echo "Project Name: $PROJECT_NAME"
echo ""

# Interactive registry selection
echo "Select Docker Registry:"
echo "1. AWS ECR (Elastic Container Registry)"
echo "2. Docker Hub"
read -p "Enter your choice (1 or 2): " REGISTRY_CHOICE
echo ""

if [ "$REGISTRY_CHOICE" = "1" ]; then
    echo "=== AWS ECR Configuration ==="
    read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
    read -p "Enter AWS Account ID: " AWS_ACCOUNT_ID
    read -p "Enter ECR Repository Name (default: crm-app): " ECR_REPO
    ECR_REPO=${ECR_REPO:-crm-app}
    
    # Sanitize repository name
    ECR_REPO=$(echo "$ECR_REPO" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9/_-' '-' | sed 's/^-*//;s/-*$//')
    
    REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    IMAGE_NAME=$(echo "$ECR_REPO" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9/_-' '-' | sed 's/^-*//;s/-*$//')
    
    echo ""
    echo "Authenticating with AWS ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"
    
    if [ $? -ne 0 ]; then
        echo "ERROR: ECR authentication failed. Please check your AWS credentials and region."
        exit 1
    fi
    
    echo "ECR authentication successful."
    echo ""
    
    # Check if repository exists, create if not
    echo "Checking if ECR repository exists..."
    if ! aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1; then
        echo "Repository does not exist. Creating ECR repository: $ECR_REPO"
        aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
        echo "ECR repository created successfully."
    else
        echo "ECR repository already exists: $ECR_REPO"
    fi
    echo ""
    
elif [ "$REGISTRY_CHOICE" = "2" ]; then
    echo "=== Docker Hub Configuration ==="
    read -p "Enter Docker Hub Username: " DOCKER_USERNAME
    read -sp "Enter Docker Hub Password/Token: " DOCKER_PASSWORD
    echo ""
    
    REGISTRY_URL="docker.io"
    IMAGE_NAME=$(echo "$DOCKER_USERNAME/crm-app" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9/_-' '-' | sed 's/^-*//;s/-*$//')
    
    echo ""
    echo "Authenticating with Docker Hub..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Docker Hub authentication failed. Please check your credentials."
        exit 1
    fi
    
    echo "Docker Hub authentication successful."
    echo ""
else
    echo "ERROR: Invalid choice. Please run the script again and select 1 or 2."
    exit 1
fi

# Prompt for image tag
read -p "Enter image tag (default: latest): " IMAGE_TAG
IMAGE_TAG=${IMAGE_TAG:-latest}

# Sanitize tag
IMAGE_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')

if [ -z "$IMAGE_TAG" ]; then
    IMAGE_TAG="latest"
fi

echo ""
echo "Building Docker image..."
echo "Image: $REGISTRY_URL/$IMAGE_NAME:$IMAGE_TAG"
echo ""

# Build Docker image
FULL_IMAGE_NAME="$REGISTRY_URL/$IMAGE_NAME:$IMAGE_TAG"
docker build -t "$FULL_IMAGE_NAME" .

if [ $? -ne 0 ]; then
    echo "ERROR: Docker build failed."
    exit 1
fi

echo ""
echo "Docker build successful."
echo ""

# Push image to registry
echo "Pushing image to registry..."
docker push "$FULL_IMAGE_NAME"

if [ $? -ne 0 ]; then
    echo "ERROR: Docker push failed."
    exit 1
fi

echo ""
echo "====================================="
echo "Docker image pushed successfully!"
echo "Image: $FULL_IMAGE_NAME"
echo "====================================="