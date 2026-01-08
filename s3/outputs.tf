output "bucket_name" {
  value = aws_s3_bucket.backups.bucket
}

output "kms_key_arn" {
  value = aws_kms_key.s3_backups.arn
}

output "iam_access_key_id" {
  value = aws_iam_access_key.backup_user.id
}

output "iam_secret_access_key" {
  value     = aws_iam_access_key.backup_user.secret
  sensitive = true
}
