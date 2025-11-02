terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_ecr_repository" "auth_service" {
  name = "auth-service"
}

resource "aws_ecr_repository" "driver_service" {
  name = "driver-service"
}

resource "aws_ecr_repository" "trip_service" {
  name = "trip-service"
}

resource "aws_iam_role" "ec2_instance_role" {
  name = "uitgo-ec2-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_access" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "uitgo-ec2-instance-profile"
  role = aws_iam_role.ec2_instance_role.name
}

resource "aws_security_group" "ec2_sg" {
  name        = "uitgo-ec2-sg"
  description = "Allow app ports"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 3030
    to_port     = 3032
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app_server" {
  ami           = var.ami_id
  instance_type = "t3.micro"
  key_name      = var.key_name
  subnet_id     = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name

  tags = {
    Name = "UIT-GO-App-Server"
  }

  user_data = file("${path.module}/user_data.sh")
}

