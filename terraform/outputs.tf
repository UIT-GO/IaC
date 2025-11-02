output "ecr_repositories" {
  description = "ECR repository URLs"
  value = {
    auth_service   = aws_ecr_repository.auth_service.repository_url
    driver_service = aws_ecr_repository.driver_service.repository_url
    trip_service   = aws_ecr_repository.trip_service.repository_url
  }
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app_server.id
}

output "ec2_public_ip" {
  description = "EC2 instance public IP"
  value       = aws_instance.app_server.public_ip
}

output "ec2_private_ip" {
  description = "EC2 instance private IP"
  value       = aws_instance.app_server.private_ip
}

output "service_endpoints" {
  description = "Service endpoints"
  value = {
    auth_service   = "http://${aws_instance.app_server.public_ip}:3030"
    driver_service = "http://${aws_instance.app_server.public_ip}:3031"
    trip_service   = "http://${aws_instance.app_server.public_ip}:3032"
  }
}

output "ssh_connection" {
  description = "SSH connection command"
  value       = "ssh -i ${var.key_name}.pem ec2-user@${aws_instance.app_server.public_ip}"
}