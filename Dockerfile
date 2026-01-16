# syntax=docker/dockerfile:1

# Build stage
FROM maven:3.9.4-eclipse-temurin-8 AS builder

WORKDIR /workspace

# Copy Maven files for dependency caching
COPY pom.xml .

# Download dependencies (cached layer)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build application
RUN mvn clean package -DskipTests -B

# Runtime stage
FROM eclipse-temurin:8-jre-alpine

# Add non-root user for security
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

WORKDIR /app

# Copy JAR from builder stage
COPY --from=builder /workspace/target/*.jar app.jar

# Set ownership
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Set Java options for container environment
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"

# Expose application port
EXPOSE 8080

# Run application
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]