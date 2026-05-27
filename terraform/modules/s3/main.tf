# =============================================================================
# terraform/modules/s3/main.tf
#
# WHAT THIS BUILDS:
#   - An S3 bucket for storing PDF medical reports
#   - Bucket policy allowing only EKS node IAM role to read/write
#   - Versioning enabled (you can recover deleted reports)
#   - Server-side encryption (AES-256 at rest)
#
# WHY S3 INSTEAD OF THE DOCKER SHARED VOLUME:
#   In Docker Compose, the backend and frontend containers share a volume
#   (shared_uploads). In Kubernetes, pods on different nodes can't share a
#   local volume — there's no single disk they all have access to.
#   Options:
#     1. EFS (Elastic File System) — expensive, complex, still a shared filesystem
#     2. S3 — cheap, durable, simple API, serverless, no single point of failure
#   S3 is the correct answer for file storage in containerized workloads.
#
# CODE CHANGE REQUIRED (app/Backend/report_upload.php):
#   Replace: move_uploaded_file($_FILES['reportfile']['tmp_name'], "reportfile/filename")
#   With:    $s3->putObject(['Bucket' => getenv('S3_BUCKET'), 'Key' => $filename, ...])
#   This is the only application code change in all of Phase 2.
#
# =============================================================================

resource "aws_s3_bucket" "reports" {
  # Bucket names must be globally unique across all AWS accounts.
  # Use project name + random suffix to avoid conflicts.
  bucket = "${var.project_name}-reports-${random_id.bucket_suffix.hex}"

  tags = {
    Name    = "${var.project_name}-reports"
    Purpose = "Medical report PDF storage"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Block all public access — medical reports must never be publicly accessible
resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning — recover accidentally deleted or overwritten reports
resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt all objects at rest with AES-256
resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# =============================================================================
# IAM POLICY — allow EKS nodes to read/write this bucket
#
# How it works:
#   EKS nodes have an IAM role. This policy is attached to that role.
#   PHP code running inside pods can then call S3 without any credentials
#   in the code — AWS automatically provides temporary credentials via
#   the Instance Metadata Service (IMDS). This is the "no credentials in code"
#   pattern that every AWS security guide requires.
# =============================================================================

resource "aws_iam_policy" "s3_reports" {
  name        = "${var.project_name}-s3-reports-policy"
  description = "Allow EKS nodes to read/write the reports S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReportsBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",      # upload report
          "s3:GetObject",      # download report
          "s3:DeleteObject",   # delete report
          "s3:ListBucket"      # list reports
        ]
        Resource = [
          aws_s3_bucket.reports.arn,
          "${aws_s3_bucket.reports.arn}/*"
        ]
      }
    ]
  })
}

# Attach the policy to the EKS node IAM role
resource "aws_iam_role_policy_attachment" "s3_reports" {
  role       = var.eks_node_role_name
  policy_arn = aws_iam_policy.s3_reports.arn
}
