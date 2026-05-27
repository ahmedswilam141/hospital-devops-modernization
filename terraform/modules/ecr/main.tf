# =============================================================================
# terraform/modules/ecr/main.tf
#
# WHAT THIS BUILDS:
#   Two private Docker image repositories on AWS:
#   - hospital-frontend  (PHP patient/doctor portal image)
#   - hospital-backend   (PHP admin portal image)
#
# WHY ECR INSTEAD OF DOCKER HUB:
#   - ECR is private — your images are not publicly accessible
#   - EKS can pull from ECR using IAM roles — no registry credentials needed
#   - Images are in the same AWS region as EKS — faster pulls, no egress cost
#   - ECR integrates with Trivy scanning natively (used in the CI pipeline)
#
# HOW IT FITS INTO THE PIPELINE:
#   GitHub Actions / Jenkins builds image → pushes to ECR
#   EKS Deployment references ECR URL → kubelet pulls image on pod start
#
# =============================================================================

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.project_name}-frontend"
  image_tag_mutability = "MUTABLE"
  # MUTABLE means you can push :latest over and over.
  # IMMUTABLE would require a unique tag per push — better for production auditing
  # but more complex for a graduation project pipeline.

  image_scanning_configuration {
    scan_on_push = true
    # AWS scans every pushed image for CVEs using ECR's built-in scanner.
    # Results visible in the ECR console. Trivy in CI catches issues before push.
  }

  tags = {
    Name = "${var.project_name}-frontend"
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-backend"
  }
}

# =============================================================================
# LIFECYCLE POLICY
# Automatically deletes old untagged images to prevent storage costs from
# accumulating. Keeps the last 10 tagged images and deletes anything older.
# Without this, every CI push adds an image that sits in ECR forever.
# =============================================================================

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus   = "tagged"
          tagPrefixList = ["v", "sha-", "latest"]
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}
