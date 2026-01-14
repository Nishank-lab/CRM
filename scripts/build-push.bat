@echo off
setlocal enabledelayedexpansion

echo ================================================
echo    Docker Build and Push Script (CRM App)
echo ================================================
echo.

set PROJECT_NAME=crm-db-check-comp

REM Sanitize project name using PowerShell
for /f "delims=" %%i in ('powershell -Command "'%PROJECT_NAME%'.ToLower() -replace '[^a-z0-9]+','-' -replace '^-+','' -replace '-+$',''"') do set IMAGE_NAME=%%i

echo Project: %PROJECT_NAME%
echo Sanitized Image Name: %IMAGE_NAME%
echo.

set /p IMAGE_TAG="Enter image tag (default: latest): "
if "!IMAGE_TAG!"==" " set IMAGE_TAG=latest
if "!IMAGE_TAG!"=="" set IMAGE_TAG=latest

for /f "delims=" %%i in ('powershell -Command "'!IMAGE_TAG!'.ToLower() -replace '[^a-z0-9.-]+','-' -replace '^-+','' -replace '-+$',''"') do set IMAGE_TAG=%%i

if "!IMAGE_TAG!"=="" set IMAGE_TAG=latest

echo Using tag: !IMAGE_TAG!
echo.

echo Select Docker Registry:
echo 1. AWS ECR (Elastic Container Registry)
echo 2. Docker Hub
set /p REGISTRY_CHOICE="Enter choice (1 or 2): "

if "!REGISTRY_CHOICE!"=="1" (
    echo.
    echo --- AWS ECR Configuration ---
    set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
    set /p AWS_ACCOUNT_ID="Enter AWS Account ID: "
    set /p ECR_REPO="Enter ECR Repository Name (default: !IMAGE_NAME!): "
    if "!ECR_REPO!"=="" set ECR_REPO=!IMAGE_NAME!
    
    set REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com
    set FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!
    
    echo.
    echo Logging in to AWS ECR...
    aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: ECR login failed
        exit /b 1
    )
    
    echo Checking if ECR repository exists...
    aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        echo Repository does not exist. Creating ECR repository: !ECR_REPO!
        aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
    )
    
) else if "!REGISTRY_CHOICE!"=="2" (
    echo.
    echo --- Docker Hub Configuration ---
    set /p DOCKER_USERNAME="Enter Docker Hub username: "
    set /p DOCKER_PASSWORD="Enter Docker Hub password: "
    
    set FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!
    
    echo.
    echo Logging in to Docker Hub...
    echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Docker Hub login failed
        exit /b 1
    )
) else (
    echo Invalid choice. Exiting.
    exit /b 1
)

echo.
echo Building Docker image: !FULL_IMAGE_NAME!
echo ================================================

docker build -t "!FULL_IMAGE_NAME!" .

if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed
    exit /b 1
)

echo.
echo Pushing Docker image to registry...
echo ================================================

docker push "!FULL_IMAGE_NAME!"

if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker push failed
    exit /b 1
)

echo.
echo ================================================
echo    Build and Push Completed Successfully!
echo ================================================
echo Image: !FULL_IMAGE_NAME!
echo.

endlocal
