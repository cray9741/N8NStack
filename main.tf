terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  backup_prefix = trim(var.backup_prefix, "/")
  prefix_with_slash = "${local.backup_prefix}/"
}

# ----------------------------
# KMS key for S3 bucket
# ----------------------------
resource "aws_kms_key" "s3_backups" {
  description             = "KMS key for S3 backups bucket ${var.bucket_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Account root full admin
      {
        Sid      = "AllowRootAdmin"
        Effect   = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },

      # Allow the backup principal(s) to use the key
      # (we set this to the IAM user created below, but you can also add roles)
      {
        Sid      = "AllowBackupPrincipalsUseKey"
        Effect   = "Allow"
        Principal = {
          AWS = [
            aws_iam_user.backup_user.arn
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "s3_backups" {
  name          = "alias/${var.kms_alias_name}"
  target_key_id = aws_kms_key.s3_backups.key_id
}

# ----------------------------
# S3 bucket
# ----------------------------
resource "aws_s3_bucket" "backups" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Default encryption: SSE-KMS with our key
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_backups.arn
    }
    bucket_key_enabled = true
  }
}

# Lifecycle: expire objects after 90 days under the prefix
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-backups-after-90-days"
    status = "Enabled"

    filter {
      prefix = local.prefix_with_slash
    }

    expiration {
      days = 90
    }

    # Optional: also expire noncurrent versions after 90 days if you enable versioning
    dynamic "noncurrent_version_expiration" {
      for_each = var.enable_versioning ? [1] : []
      content {
        noncurrent_days = 90
      }
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ----------------------------
# Bucket policy: enforce TLS + SSE-KMS using our key
# ----------------------------
resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Deny non-TLS
      {
        Sid      = "DenyInsecureTransport"
        Effect   = "Deny"
        Principal = "*"
        Action   = "s3:*"
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },

      # Deny PUT without SSE header (KMS)
      {
        Sid      = "DenyUnEncryptedObjectUploads"
        Effect   = "Deny"
        Principal = "*"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.backups.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },

      # Deny PUT if wrong KMS key is used
      {
        Sid      = "DenyWrongKmsKey"
        Effect   = "Deny"
        Principal = "*"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.backups.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption-aws-kms-key-id" = aws_kms_key.s3_backups.arn
          }
        }
      }
    ]
  })
}

# ----------------------------
# IAM: user + policy for backup/restore jobs
# ----------------------------
resource "aws_iam_user" "backup_user" {
  name = var.iam_user_name
}

resource "aws_iam_policy" "backup_policy" {
  name        = "${var.iam_user_name}-s3-backups"
  description = "Allow writing/reading backups in ${var.bucket_name}/${local.prefix_with_slash} using SSE-KMS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # List the bucket for the prefix
      {
        Sid    = "ListBucketPrefix"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = aws_s3_bucket.backups.arn
        Condition = {
          StringLike = {
            "s3:prefix" = [
              local.prefix_with_slash,
              "${local.prefix_with_slash}*"
            ]
          }
        }
      },

      # Read/write objects under the prefix
      {
        Sid    = "ObjectRW"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject" # optional; remove if you don't want deletes
        ]
        Resource = "${aws_s3_bucket.backups.arn}/${local.prefix_with_slash}*"
      },

      # KMS usage for SSE-KMS
      {
        Sid    = "KmsUse"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.s3_backups.arn
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "backup_attach" {
  user       = aws_iam_user.backup_user.name
  policy_arn = aws_iam_policy.backup_policy.arn
}

# Access keys (simple for k3s). Store these in a Kubernetes Secret.
resource "aws_iam_access_key" "backup_user" {
  user = aws_iam_user.backup_user.name
}
