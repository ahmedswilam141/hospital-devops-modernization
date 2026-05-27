# =============================================================================
# terraform/backend.tf
#
# WHAT THIS IS:
#   Terraform's "memory" — where it stores a record of everything it has built.
#   This file tells Terraform: "store your state in S3, use DynamoDB for locking."
#
# WHY REMOTE STATE INSTEAD OF LOCAL:
#   By default, Terraform writes terraform.tfstate to your local disk.
#   That file is the single source of truth for your infrastructure.
#   If you lose it, Terraform no longer knows what exists on AWS and will
#   try to recreate everything — causing conflicts or duplicates.
#   Remote state in S3 means:
#     - The file is safe even if your VM crashes
#     - You can destroy and recreate your VM without losing Terraform's memory
#     - In teams, everyone shares the same state
#
# WHY DYNAMODB LOCKING:
#   If two Terraform operations run simultaneously against the same state,
#   they corrupt it. DynamoDB provides a distributed lock — only one
#   Terraform process can write state at a time. AWS best practice.
#
# PREREQUISITE — run these commands BEFORE terraform init:
#
#   # Create the S3 bucket (replace YOUR_NAME with something unique)
#   aws s3api create-bucket \
#     --bucket hospital-devops-tfstate-YOUR_NAME \
#     --region us-east-1
#
#   # Enable versioning (recover from accidental state deletion)
#   aws s3api put-bucket-versioning \
#     --bucket hospital-devops-tfstate-YOUR_NAME \
#     --versioning-configuration Status=Enabled
#
#   # Enable AES-256 encryption at rest
#   aws s3api put-bucket-encryption \
#     --bucket hospital-devops-tfstate-YOUR_NAME \
#     --server-side-encryption-configuration \
#     '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#
#   # Create DynamoDB table for state locking
#   aws dynamodb create-table \
#     --table-name hospital-devops-tflock \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST \
#     --region us-east-1
#
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "hospital-devops-tfstate-092304626836"
    key            = "hospital/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "hospital-devops-tflock"
    encrypt        = true
  }
}
