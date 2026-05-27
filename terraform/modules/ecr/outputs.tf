# terraform/modules/ecr/outputs.tf

output "frontend_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
  # Example: 123456789012.dkr.ecr.us-east-1.amazonaws.com/hospital-devops-frontend
}

output "backend_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "registry_id" {
  value = aws_ecr_repository.frontend.registry_id
  # This is your AWS account ID — needed for docker login command
}
