resource "aws_iam_user" "n8n_backup" {
  name = var.iam_user_name
}

resource "aws_iam_access_key" "n8n_backup" {
  user = aws_iam_user.n8n_backup.name
}

resource "aws_iam_policy" "n8n_backup" {
  name        = "${var.iam_user_name}-policy"
  description = "Least-privilege S3/KMS permissions for n8n postgres backups"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # List only within the prefix
      {
        Sid      = "ListBucketPrefix"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.backups.arn
        Condition = {
          StringLike = {
            "s3:prefix" = [local.prefix_slash, "${local.prefix_slash}*"]
          }
        }
      },

      # Read/write objects only under the prefix
      {
        Sid      = "ObjectRW"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.backups.arn}/${local.prefix_slash}*"
      },

      # KMS usage only via S3 in this region/account
      {
        Sid    = "KmsUseViaS3Only"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.n8n_s3.arn
        Condition = {
          StringEquals = {
            "kms:ViaService"    = "s3.${data.aws_region.current.name}.amazonaws.com"
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "n8n_backup_attach" {
  user       = aws_iam_user.n8n_backup.name
  policy_arn = aws_iam_policy.n8n_backup.arn
}
