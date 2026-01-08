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
  description = "S3 prefix for backups"
  default     = "backups/n8n/db_backups"
}

variable "enable_versioning" {
  type    = bool
  default = true
}

variable "iam_user_name" {
  type    = string
  default = "n8n-backup"
}

variable "kms_alias_name" {
  type    = string
  default = "n8n-backups"
}

variable "kms_admin_role_name" {
  type    = string
  default = "kms-admin-n8n-backups"
}

variable "kms_admin_trusted_arns" {
  type        = list(string)
  description = <<EOT
ARNs allowed to assume the KMS admin role. Use your Terraform execution role, SSO admin role, or your IAM user ARN.
Example:
[
  "arn:aws:iam::123456789012:role/TerraformAdmin",
  "arn:aws:iam::123456789012:user/clarence"
]
EOT
}
