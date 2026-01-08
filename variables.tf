variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type        = string
  description = "S3 bucket name for backups"
}

variable "backup_prefix" {
  type        = string
  description = "Prefix inside the bucket to store backups (e.g. backups/n8n/db_backups)"
  default     = "backups/n8n/db_backups"
}

variable "kms_alias_name" {
  type        = string
  description = "KMS alias name (without 'alias/')"
  default     = "s3-backups"
}

variable "iam_user_name" {
  type        = string
  description = "IAM user name for backup/restore jobs"
  default     = "k8s-pg-backup"
}

variable "enable_versioning" {
  type        = bool
  description = "Enable S3 versioning (recommended)"
  default     = true
}
