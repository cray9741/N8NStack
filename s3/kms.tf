resource "aws_kms_key" "n8n_s3" {
  description             = "KMS key for n8n postgres backups in ${var.bucket_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  # IMPORTANT: No root principal. Admin is the role created above.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Key admin role has admin control of this key
      {
        Sid      = "AllowKeyAdmins"
        Effect   = "Allow"
        Principal = { AWS = aws_iam_role.kms_admin.arn }
        Action   = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
          "kms:EnableKeyRotation",
          "kms:RotateKeyOnDemand"
        ]
        Resource = "*"
      },

      # Backup IAM user can use the key, but only via S3 in this account/region
      {
        Sid      = "AllowN8NBackupUseViaS3"
        Effect   = "Allow"
        Principal = { AWS = aws_iam_user.n8n_backup.arn }
        Action   = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
            "kms:ViaService"    = "s3.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })

  # Ensure role/user exist before key policy evaluates them
  depends_on = [
    aws_iam_role_policy_attachment.kms_admin_attach
  ]
}

resource "aws_kms_alias" "n8n_s3" {
  name          = "alias/${var.kms_alias_name}"
  target_key_id = aws_kms_key.n8n_s3.key_id
}
