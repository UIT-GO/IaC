# UIT-GO EC2 Deployment with Terraform

This Terraform configuration deploys UIT-GO microservices to AWS EC2 using Docker Compose.

## Architecture

- **3 ECR Repositories**: auth-service, driver-service, trip-service
- **1 EC2 Instance**: t3.medium with Docker and Docker Compose
- **IAM Role**: EC2 instance role with ECR read permissions
- **Security Group**: Allow ports 3030-3032 for services
- **Auto Deployment**: user_data.sh script automatically deploys services

## Prerequisites

1. **AWS CLI configured** with appropriate credentials
2. **Terraform installed** (>= 1.3.0)
3. **VPC and Subnet** already created
4. **EC2 Key Pair** created
5. **Docker images** built and pushed to ECR repositories

## Quick Start

### 1. Configure Variables

Copy and customize the variables file:
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your actual values
```

### 2. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

### 3. Access Services

After deployment (5-10 minutes), services will be available at:
- Auth Service: `http://<EC2_PUBLIC_IP>:3030`
- Driver Service: `http://<EC2_PUBLIC_IP>:3031`
- Trip Service: `http://<EC2_PUBLIC_IP>:3032`

## What user_data.sh Does

The script automatically:
1. **Installs Docker & Docker Compose** on EC2
2. **Creates docker-compose.yml** with ECR image URLs
3. **Logs into ECR** repositories
4. **Starts all services** including databases (PostgreSQL, MongoDB, Redis, Kafka)
5. **Creates management scripts** for health check, restart, and updates

## Management Scripts

After deployment, these scripts are available in `/home/ec2-user/uitgo-app/`:

```bash
# Check service health
./health-check.sh

# Restart all services
./restart-services.sh

# Update services with latest images
./update-services.sh
```

## Manual Commands

SSH into the EC2 instance:
```bash
ssh -i <your-key>.pem ec2-user@<EC2_PUBLIC_IP>
```

Check running containers:
```bash
cd /home/ec2-user/uitgo-app
docker-compose ps
```

View logs:
```bash
docker-compose logs -f auth-service
docker-compose logs -f driver-service
docker-compose logs -f trip-service
```

## Required ECR Images

Before deployment, ensure these images are available in ECR:
- `<AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/auth-service:latest`
- `<AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/driver-service:latest`
- `<AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/trip-service:latest`

## Building and Pushing Images

Example for auth-service:
```bash
cd ../auth-service

# Build Docker image
docker build -t auth-service .

# Tag for ECR
docker tag auth-service:latest <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/auth-service:latest

# Login to ECR
aws ecr get-login-password --region <REGION> | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com

# Push image
docker push <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/auth-service:latest
```

Repeat for driver-service and trip-service.

## Troubleshooting

1. **Check user_data execution**: `sudo cat /var/log/user_data.log`
2. **Check Docker status**: `sudo systemctl status docker`
3. **Check container health**: `docker ps -a`
4. **Check application logs**: `docker-compose logs <service-name>`

## Clean Up

To destroy all resources:
```bash
terraform destroy
```

## Security Notes

- Security group allows public access to service ports (3030-3032)
- For production, consider using Application Load Balancer
- Database credentials are hardcoded (change for production)
- Consider using AWS Secrets Manager for sensitive data