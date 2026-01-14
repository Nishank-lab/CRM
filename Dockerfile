# Multi-stage build for Spring Boot CRM application
# Stage 1: Build stage
FROM maven:3.9.4-eclipse-temurin-8 AS builder

WORKDIR /workspace

# Copy pom.xml first for dependency caching
COPY pom.xml .

# Download dependencies (this layer will be cached)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build the application
RUN mvn clean package -DskipTests

# Stage 2: Runtime stage
FROM eclipse-temurin:8-jre

WORKDIR /app

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Copy the JAR from builder stage
COPY --from=builder /workspace/target/*.jar app.jar

# Set timezone
ENV TZ=UTC

# Set JVM options for container environment
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"

# Spring Boot environment variables
ENV SPRING_PROFILES_ACTIVE=docker
ENV DDL_AUTO=validate
ENV DB_URL=jdbc:mysql://mysql:3306/crm?useSSL=false
ENV DB_USERNAME=root
ENV DB_PASSWORD=password
ENV MANAGEMENT_SECURITY_ENABLED=true

# Change ownership to non-root user
RUN chown -R appuser:appuser /app

USER appuser

# Expose application port
EXPOSE 8080

# Run the application
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
