resource "aws_iam_role" "kms_admin" {
  name = var.kms_admin_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAssumeFromTrustedPrincipals"
        Effect = "Allow"
        Principal = {
          AWS = var.kms_admin_trusted_arns
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Minimal-but-sufficient IAM permissions for KMS key administration actions.
resource "aws_iam_policy" "kms_admin" {
  name        = "${var.kms_admin_role_name}-policy"
  description = "Administer the n8n backups KMS key (scoped to the key after creation via key policy)."

  # Note: This policy is broad for KMS admin actions. The *key policy* is the ultimate gatekeeper.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KmsAdminActions"
        Effect = "Allow"
        Action = [
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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kms_admin_attach" {
  role       = aws_iam_role.kms_admin.name
  policy_arn = aws_iam_policy.kms_admin.arn
}
