# =============================================================================
# terraform/variables.tf
#
# WHAT THIS IS:
#   All configurable values for the entire infrastructure in one place.
#   Nothing is hardcoded in the modules — everything is a variable.
#   This is the Terraform equivalent of your .env file.
#
# HOW TO USE:
#   Create terraform/terraform.tfvars (gitignored) with your real values:
#
#     project_name = "hospital-devops"
#     aws_region   = "us-east-1"
#     db_password  = "YourRealPassword123!"
#
#   Or pass on the command line:
#     terraform apply -var="db_password=YourPassword"
#
# =============================================================================

variable "project_name" {
  description = "Project name — used as a prefix on all AWS resource names and tags"
  type        = string
  default     = "hospital-devops"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name — used in tags and resource names"
  type        = string
  default     = "production"
}

# =============================================================================
# NETWORKING
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC. 10.0.0.0/16 gives 65,536 IP addresses."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy into. 2 AZs = high availability for RDS and EKS."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB, NAT Gateway, Bastion)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (EKS nodes, RDS, ElastiCache)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

# =============================================================================
# DATABASE (RDS)
# =============================================================================

variable "db_name" {
  description = "MySQL database name"
  type        = string
  default     = "hospital"
}

variable "db_username" {
  description = "MySQL admin username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "MySQL admin password — never hardcode this, use tfvars or env var"
  type        = string
  sensitive   = true   # Terraform will not print this value in logs
}

variable "db_instance_class" {
  description = "RDS instance type — db.t3.micro is free-tier eligible"
  type        = string
  default     = "db.t3.micro"
}

# =============================================================================
# KUBERNETES (EKS)
# =============================================================================

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.small"
}

variable "eks_node_desired_count" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "eks_node_min_count" {
  description = "Minimum nodes — EKS auto-scaler won't go below this"
  type        = number
  default     = 1
}

variable "eks_node_max_count" {
  description = "Maximum nodes — EKS auto-scaler won't exceed this"
  type        = number
  default     = 4
}

# =============================================================================
# BASTION HOST
# =============================================================================

variable "bastion_instance_type" {
  description = "EC2 type for bastion host — t3.micro is enough for a jump box"
  type        = string
  default     = "t3.micro"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR format — only this IP can SSH to bastion"
  type        = string
  # Find your IP: curl https://checkip.amazonaws.com
  # Then add /32: e.g. "41.67.138.100/32"
}
