resource "aws_s3_bucket" "configs" {
  bucket = "discordia-env-configs-${data.aws_caller_identity.current.account_id}"
}

# Bloquear todo acceso público por seguridad
resource "aws_s3_bucket_public_access_block" "configs_block" {
  bucket                  = aws_s3_bucket.configs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
