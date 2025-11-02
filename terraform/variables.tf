variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to launch EC2"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for EC2"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for EC2 instance"
  type        = string
  default = "ami-0df7a207adb9748c7"
}

variable "key_name" {
  description = "EC2 Key Pair name"
  type        = string
  default = "UIT-GO"
}
