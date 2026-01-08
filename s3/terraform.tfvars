bucket_name    = "n8n_db_backup"
backup_prefix  = "backups/n8n/db_backups"

# Who can assume the KMS admin role (your Terraform execution role, SSO admin role, etc.)
kms_admin_trusted_arns = [
  "arn:aws:iam::123456789012:role/TerraformAdmin"
]
