# =============================================================================
# terraform/main.tf
#
# WHAT THIS IS:
#   The root Terraform configuration. It calls every module in the right order
#   and passes outputs from one module as inputs to the next.
#
# BUILD ORDER (Terraform resolves this automatically from dependencies):
#   1. VPC          — networking foundation; everything else goes inside it
#   2. ECR          — image registry; needed before you can push Docker images
#   3. RDS          — MySQL database; placed in private subnets from VPC
#   4. ElastiCache  — Redis session store; placed in private subnets from VPC
#   5. S3           — file storage for PDF reports
#   6. EKS          — Kubernetes cluster; nodes go in private subnets from VPC
#   7. Bastion      — EC2 jump host; in public subnet, SSH tunnel to RDS/Redis
#
# DEPENDENCY GRAPH:
#   ECR  ─────────────────────────────────────────────┐
#   VPC → RDS                                          ├→ EKS → (K8s manifests)
#       → ElastiCache                                  │
#       → EKS → Bastion                                │
#   S3  ──────────────────────────────────────────────┘
#
# =============================================================================

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"   # Pin major version — avoid breaking changes
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# =============================================================================
# MODULE 1 — VPC (Virtual Private Cloud)
# Networking foundation. All other modules receive subnet IDs from here.
# =============================================================================

module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# =============================================================================
# MODULE 2 — ECR (Elastic Container Registry)
# Private Docker registry on AWS. Your CI pipeline pushes images here.
# EKS pulls images from here when deploying pods.
# =============================================================================

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
}

# =============================================================================
# MODULE 3 — RDS (Relational Database Service — MySQL)
# Managed MySQL in a private subnet. Replaces the mysql container from Docker.
# Only reachable from within the VPC — not from the internet.
# =============================================================================

module "rds" {
  source = "./modules/rds"

  project_name    = var.project_name
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids   # private — not internet-facing
  db_name         = var.db_name
  db_username     = var.db_username
  db_password     = var.db_password
  instance_class  = var.db_instance_class

  # EKS nodes need to reach RDS — allow their security group
  eks_node_sg_id  = module.eks.node_security_group_id
}

# =============================================================================
# MODULE 4 — ELASTICACHE (Redis)
# Managed Redis in a private subnet. Replaces the redis container from Docker.
# Stores PHP sessions — the fix that makes the app work across multiple pods.
# =============================================================================

module "elasticache" {
  source = "./modules/redis"

  project_name   = var.project_name
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids
  eks_node_sg_id = module.eks.node_security_group_id
}

# =============================================================================
# MODULE 5 — S3 (Simple Storage Service)
# Object storage for PDF medical reports. Replaces the shared_uploads Docker
# volume. Durable, versioned, accessible from any pod without a shared filesystem.
# =============================================================================

module "s3" {
  source = "./modules/s3"

  project_name       = var.project_name
  eks_node_role_arn  = module.eks.node_role_arn
  eks_node_role_name = module.eks.node_role_name
}

# =============================================================================
# MODULE 6 — EKS (Elastic Kubernetes Service)
# Managed Kubernetes cluster. Runs the frontend, backend, and nginx pods.
# =============================================================================

module "eks" {
  source = "./modules/eks"

  project_name       = var.project_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  cluster_version    = var.eks_cluster_version
  node_instance_type = var.eks_node_instance_type
  node_desired_count = var.eks_node_desired_count
  node_min_count     = var.eks_node_min_count
  node_max_count     = var.eks_node_max_count
}

# =============================================================================
# MODULE 7 — BASTION HOST
# EC2 instance in the public subnet. Jump box for accessing RDS and Redis
# which are in private subnets and not reachable directly from your laptop.
# Also used by Ansible for configuration management.
# =============================================================================

module "bastion" {
  source = "./modules/bastion"

  project_name      = var.project_name
  vpc_id            = module.vpc.vpc_id
  public_subnet_id  = module.vpc.public_subnet_ids[0]
  my_ip_cidr        = var.my_ip_cidr
  instance_type     = var.bastion_instance_type
}
