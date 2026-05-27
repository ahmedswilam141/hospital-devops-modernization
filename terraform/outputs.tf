# =============================================================================
# terraform/outputs.tf
#
# WHAT THIS IS:
#   Values printed after `terraform apply` completes.
#   You will copy these values into your K8s manifests and CI/CD pipeline.
#
# USAGE:
#   terraform output                    # print all outputs
#   terraform output rds_endpoint       # print one specific value
#   terraform output -json              # machine-readable JSON
# =============================================================================

output "vpc_id" {
  description = "VPC ID — needed for security group rules and subnet lookups"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs — where EKS nodes, RDS, and Redis live"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs — where the ALB and Bastion live"
  value       = module.vpc.public_subnet_ids
}

output "ecr_frontend_url" {
  description = "ECR URL for the frontend image — use this in docker push and K8s manifests"
  value       = module.ecr.frontend_repository_url
}

output "ecr_backend_url" {
  description = "ECR URL for the backend image — use this in docker push and K8s manifests"
  value       = module.ecr.backend_repository_url
}

output "rds_endpoint" {
  description = "RDS MySQL hostname — set as DB_HOST in K8s ConfigMap"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS port (3306)"
  value       = module.rds.port
}

output "redis_endpoint" {
  description = "ElastiCache Redis hostname — set as REDIS_HOST in K8s ConfigMap"
  value       = module.elasticache.endpoint
}

output "redis_port" {
  description = "ElastiCache Redis port (6379)"
  value       = module.elasticache.port
}

output "s3_bucket_name" {
  description = "S3 bucket for report uploads — set as S3_BUCKET in K8s ConfigMap"
  value       = module.s3.bucket_name
}

output "eks_cluster_name" {
  description = "EKS cluster name — use in: aws eks update-kubeconfig --name <this>"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "bastion_public_ip" {
  description = "Bastion public IP — use for SSH tunnel to RDS and for Ansible inventory"
  value       = module.bastion.public_ip
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials — use in K8s ExternalSecret"
  value       = module.rds.secret_arn
}
