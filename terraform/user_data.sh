#!/bin/bash

# UIT-GO Services Deployment Script for EC2
# This script installs Docker, Docker Compose and deploys services using docker-compose.yml

set -e

LOG_FILE="/var/log/user_data.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "=========================================="
echo "UIT-GO Deployment Started: $(date)"
echo "=========================================="

# Update system
echo "Updating system packages..."
sudo yum update -y

# Install Docker
echo "Installing Docker..."
sudo amazon-linux-extras install docker -y
sudo service docker start
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# Install Docker Compose
echo "Installing Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install AWS CLI v2 (if not already installed)
echo "Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws

# Get AWS region and account ID
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "AWS Region: $AWS_REGION"
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Create application directory
APP_DIR="/home/ec2-user/uitgo-app"
sudo mkdir -p $APP_DIR
sudo chown ec2-user:ec2-user $APP_DIR

# Download docker-compose.yml from S3 or fallback to GitHub
echo "Setting up docker-compose.yml..."

# Option 1: Download from S3 bucket (recommended)
if aws s3 cp s3://uitgo-deployment-artifacts/docker-compose.yml $APP_DIR/docker-compose.yml 2>/dev/null; then
    echo "✅ Downloaded docker-compose.yml from S3"
# Option 2: Download from GitHub repository
elif curl -o $APP_DIR/docker-compose.yml https://raw.githubusercontent.com/UIT-GO/IaC/docker-compose.yml 2>/dev/null; then
    echo "✅ Downloaded docker-compose.yml from GitHub"
# Option 3: Create docker-compose.yml as fallback
else
    echo "⚠️ Creating fallback docker-compose.yml..."
cat > $APP_DIR/docker-compose.yml << 'EOF'

version: '3.9'

services:
  # ==========================
  #  Microservices (Spring Boot / Node)
  # ==========================

  auth-service:
    image: your-ecr-repo-url/auth-service:latest
    container_name: auth-service
    restart: always
    ports:
      - "3030:3030"
    environment:
      - SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/auth_service_db
      - SPRING_DATASOURCE_USERNAME=admin
      - SPRING_DATASOURCE_PASSWORD=password
      - SPRING_REDIS_HOST=redis
      - SPRING_REDIS_PORT=6379
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - app-network

  driver-service:
    image: your-ecr-repo-url/driver-service:latest
    container_name: driver-service
    restart: always
    ports:
      - "3031:3031"
    environment:
      - SPRING_DATA_MONGODB_URI=mongodb://mongodb:27017/driver-db
      - SPRING_KAFKA_BOOTSTRAP_SERVERS=kafka:9092
    depends_on:
      mongodb:
        condition: service_started
      kafka:
        condition: service_healthy
    networks:
      - app-network

  trip-service:
    image: your-ecr-repo-url/trip-service:latest
    container_name: trip-service
    restart: always
    ports:
      - "3032:3032"
    environment:
      - SPRING_DATA_MONGODB_URI=mongodb://mongodb:27017/trip-db
      - SPRING_KAFKA_BOOTSTRAP_SERVERS=kafka:9092
    depends_on:
      mongodb:
        condition: service_started
      kafka:
        condition: service_healthy
    networks:
      - app-network

  # ==========================
  #  Databases & Cache
  # ==========================

  postgres:
    image: postgres:16.0
    container_name: postgres_container
    restart: always
    environment:
      POSTGRES_DB: auth_service_db
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin -d auth_service_db"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

  mongodb:
    image: mongo:6.0
    container_name: mongodb
    restart: always
    ports:
      - "27017:27017"
    volumes:
      - mongo_data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

  redis:
    image: redis:alpine
    container_name: redis
    restart: always
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    networks:
      - app-network

  redisinsight:
    image: redislabs/redisinsight:latest
    container_name: redisinsight
    restart: always
    ports:
      - "8001:5540"
    depends_on:
      - redis
    volumes:
      - redisinsight_data:/db
    networks:
      - app-network

  # ==========================
  #  Kafka & Zookeeper
  # ==========================
  zookeeper:
    image: confluentinc/cp-zookeeper:7.5.0
    container_name: zookeeper
    restart: always
    ports:
      - "2181:2181"
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    healthcheck:
      test: ["CMD-SHELL", "echo stat | nc localhost 2181"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network
    volumes:
      - zookeeper_data:/var/lib/zookeeper/data
      - zookeeper_log:/var/lib/zookeeper/log

  kafka:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka
    restart: always
    ports:
      - "9092:9092"
      - "9093:9093"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092,PLAINTEXT_HOST://localhost:9093
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: 'true'
      KAFKA_LOG_RETENTION_HOURS: 168
    depends_on:
      zookeeper:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "kafka-broker-api-versions --bootstrap-server localhost:9092 || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 30s
    networks:
      - app-network
    volumes:
      - kafka_data:/var/lib/kafka/data

# ==========================
#  Networks
# ==========================
networks:
  app-network:
    driver: bridge
    name: microservices-network

# ==========================
#  Volumes
# ==========================
volumes:
  postgres_data:
  mongo_data:
  redis_data:
  redisinsight_data:
  zookeeper_data:
  zookeeper_log:
  kafka_data:
EOF

# Update docker-compose.yml with actual ECR URLs
sed -i "s/your-ecr-repo-url/$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/g" $APP_DIR/docker-compose.yml
sed -i "s/microservices/auth_service_db/g" $APP_DIR/docker-compose.yml

# Login to ECR
echo "Logging into ECR repositories..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Change to application directory
cd $APP_DIR

# Pull images (optional, docker-compose will pull automatically)
echo "Pulling Docker images..."
docker-compose pull || echo "Some images may not exist yet, continuing..."

# Start services with docker-compose
echo "Starting services with Docker Compose..."
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 30

# Check service status
echo "Checking service status..."
docker-compose ps

# Create health check script
cat > $APP_DIR/health-check.sh << 'EOF'
#!/bin/bash
echo "=== Health Check $(date) ==="
echo "Docker containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo -e "\nService endpoints:"
for port in 3030 3031 3032; do
    if curl -f -s http://localhost:$port/actuator/health > /dev/null 2>&1; then
        echo "Port $port: ✅ Healthy"
    else
        echo "Port $port: ❌ Not responding"
    fi
done

echo -e "\nDocker Compose services:"
cd /home/ec2-user/uitgo-app
docker-compose ps
EOF

chmod +x $APP_DIR/health-check.sh

# Create restart script
cat > $APP_DIR/restart-services.sh << 'EOF'
#!/bin/bash
echo "Restarting UIT-GO services..."
cd /home/ec2-user/uitgo-app
docker-compose down
docker-compose pull
docker-compose up -d
echo "Services restarted successfully!"
EOF

chmod +x $APP_DIR/restart-services.sh

# Create update script
cat > $APP_DIR/update-services.sh << 'EOF'
#!/bin/bash
echo "Updating UIT-GO services..."
cd /home/ec2-user/uitgo-app

# Get latest images
aws ecr get-login-password --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(curl -s http://169.254.169.254/latest/meta-data/placement/region).amazonaws.com

# Update and restart services
docker-compose pull
docker-compose up -d

echo "Services updated successfully!"
EOF

chmod +x $APP_DIR/update-services.sh

# Change ownership to ec2-user
sudo chown -R ec2-user:ec2-user $APP_DIR

# Run initial health check
echo "Running initial health check..."
sleep 10
$APP_DIR/health-check.sh

echo "=========================================="
echo "UIT-GO Deployment Completed: $(date)"
echo "=========================================="
echo "Application directory: $APP_DIR"
echo "Health check: $APP_DIR/health-check.sh"
echo "Restart services: $APP_DIR/restart-services.sh"
echo "Update services: $APP_DIR/update-services.sh"
echo "Logs: docker-compose logs -f"
echo "=========================================="