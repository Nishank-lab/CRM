@echo off
setlocal enabledelayedexpansion

echo =====================================
echo Docker Build and Push Script
echo =====================================
echo.

REM Get project name from current directory
for %%I in (.) do set PROJECT_NAME=%%~nxI
echo Project Name: !PROJECT_NAME!
echo.

REM Interactive registry selection
echo Select Docker Registry:
echo 1. AWS ECR (Elastic Container Registry)
echo 2. Docker Hub
set /p REGISTRY_CHOICE="Enter your choice (1 or 2): "
echo.

if "!REGISTRY_CHOICE!"=="1" (
    echo === AWS ECR Configuration ===
    set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
    set /p AWS_ACCOUNT_ID="Enter AWS Account ID: "
    set /p ECR_REPO="Enter ECR Repository Name (default: crm-app): "
    if "!ECR_REPO!"==" " set ECR_REPO=crm-app
    
    REM Sanitize repository name using PowerShell
    for /f "delims=" %%i in ('powershell -Command "'!ECR_REPO!' -replace '[^a-zA-Z0-9/_-]','-' -replace '^-+','' -replace '-+$',''"') do set ECR_REPO=%%i
    for /f "delims=" %%i in ('powershell -Command "'!ECR_REPO!'.ToLower()"') do set ECR_REPO=%%i
    
    set REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com
    set IMAGE_NAME=!ECR_REPO!
    
    echo.
    echo Authenticating with AWS ECR...
    aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: ECR authentication failed. Please check your AWS credentials and region.
        exit /b 1
    )
    
    echo ECR authentication successful.
    echo.
    
    REM Check if repository exists, create if not
    echo Checking if ECR repository exists...
    aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
    
    if !ERRORLEVEL! neq 0 (
        echo Repository does not exist. Creating ECR repository: !ECR_REPO!
        aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
        if !ERRORLEVEL! neq 0 (
            echo ERROR: Failed to create ECR repository.
            exit /b 1
        )
        echo ECR repository created successfully.
    ) else (
        echo ECR repository already exists: !ECR_REPO!
    )
    echo.
    
) else if "!REGISTRY_CHOICE!"=="2" (
    echo === Docker Hub Configuration ===
    set /p DOCKER_USERNAME="Enter Docker Hub Username: "
    set /p DOCKER_PASSWORD="Enter Docker Hub Password/Token: "
    
    set REGISTRY_URL=docker.io
    for /f "delims=" %%i in ('powershell -Command "('!DOCKER_USERNAME!/crm-app') -replace '[^a-zA-Z0-9/_-]','-' -replace '^-+','' -replace '-+$',''"') do set IMAGE_NAME=%%i
    for /f "delims=" %%i in ('powershell -Command "'!IMAGE_NAME!'.ToLower()"') do set IMAGE_NAME=%%i
    
    echo.
    echo Authenticating with Docker Hub...
    echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Docker Hub authentication failed. Please check your credentials.
        exit /b 1
    )
    
    echo Docker Hub authentication successful.
    echo.
) else (
    echo ERROR: Invalid choice. Please run the script again and select 1 or 2.
    exit /b 1
)

REM Prompt for image tag
set /p IMAGE_TAG="Enter image tag (default: latest): "
if "!IMAGE_TAG!"==" " set IMAGE_TAG=latest

REM Sanitize tag using PowerShell
for /f "delims=" %%i in ('powershell -Command "'!IMAGE_TAG!' -replace '[^a-zA-Z0-9._-]','-' -replace '^-+','' -replace '-+$',''"') do set IMAGE_TAG=%%i
for /f "delims=" %%i in ('powershell -Command "'!IMAGE_TAG!'.ToLower()"') do set IMAGE_TAG=%%i

if "!IMAGE_TAG!"==" " set IMAGE_TAG=latest

echo.
echo Building Docker image...
set FULL_IMAGE_NAME=!REGISTRY_URL!/!IMAGE_NAME!:!IMAGE_TAG!
echo Image: !FULL_IMAGE_NAME!
echo.

REM Build Docker image
docker build -t "!FULL_IMAGE_NAME!" .

if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)

echo.
echo Docker build successful.
echo.

REM Push image to registry
echo Pushing image to registry...
docker push "!FULL_IMAGE_NAME!"

if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker push failed.
    exit /b 1
)

echo.
echo =====================================
echo Docker image pushed successfully!
echo Image: !FULL_IMAGE_NAME!
echo =====================================

endlocal