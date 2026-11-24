data "aws_caller_identity" "me" {}
data "aws_partition" "p" {}

locals {
  account = data.aws_caller_identity.me.account_id
  arn     = "arn:${data.aws_partition.p.partition}"
  buckets = {
    kb      = "sentinel-kb-${local.account}"
    finance = "sentinel-finance-${local.account}"
    trail   = "sentinel-trail-${local.account}"
    access  = "sentinel-access-logs-${local.account}"
  }
}

# One key for the buckets, the trail and the log groups. CloudTrail and CloudWatch Logs use
# it through their service principals; everything else uses it through IAM.
resource "aws_kms_key" "data" {
  description             = "sentinel-agent data: buckets, trail, logs"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "${local.arn}:iam::${local.account}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudTrailEncrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceArn" = "${local.arn}:cloudtrail:${var.region}:${local.account}:trail/sentinel-trail" }
          StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = "${local.arn}:cloudtrail:*:${local.account}:trail/*" }
        }
      },
      {
        Sid       = "CloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "${local.arn}:logs:${var.region}:${local.account}:log-group:/sentinel/*" }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "data" {
  name          = "alias/sentinel-data"
  target_key_id = aws_kms_key.data.key_id
}

# --- Buckets ----------------------------------------------------------------------------

resource "aws_s3_bucket" "b" {
  # checkov:skip=CKV_AWS_18:aws_s3_bucket_logging.b sends kb, finance and trail access logs to the access bucket; Checkov does not follow the for_each link, and the access bucket cannot log to itself
  # checkov:skip=CKV_AWS_144:One-region lab; replication would double storage cost for training data
  # checkov:skip=CKV2_AWS_62:CloudTrail data events record every object read and write in the data buckets
  # checkov:skip=CKV_AWS_145:The access-log bucket must use SSE-S3, because S3 server access logging cannot write to a KMS-encrypted bucket; the other buckets use the data key
  for_each      = local.buckets
  bucket        = each.value
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "b" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.b[each.key].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "b" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.b[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      # S3 server access logging cannot write to a bucket encrypted with a customer key.
      sse_algorithm     = each.key == "access" ? "AES256" : "aws:kms"
      kms_master_key_id = each.key == "access" ? null : aws_kms_key.data.arn
    }
    bucket_key_enabled = each.key != "access"
  }
}

resource "aws_s3_bucket_public_access_block" "b" {
  for_each                = local.buckets
  bucket                  = aws_s3_bucket.b[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "b" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.b[each.key].id
  rule {
    id     = "expire-old"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_logging" "b" {
  for_each      = { for k, v in local.buckets : k => v if k != "access" }
  bucket        = aws_s3_bucket.b[each.key].id
  target_bucket = aws_s3_bucket.b["access"].id
  target_prefix = "${each.key}/"
}

data "aws_iam_policy_document" "bucket" {
  for_each = local.buckets
  statement {
    sid     = "TLSOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.b[each.key].arn, "${aws_s3_bucket.b[each.key].arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
  dynamic "statement" {
    for_each = each.key == "trail" ? ["acl", "write"] : []
    content {
      sid     = "CloudTrail-${statement.value}"
      actions = statement.value == "acl" ? ["s3:GetBucketAcl"] : ["s3:PutObject"]
      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }
      resources = statement.value == "acl" ? [aws_s3_bucket.b["trail"].arn] : ["${aws_s3_bucket.b["trail"].arn}/AWSLogs/${local.account}/*"]
      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = ["${local.arn}:cloudtrail:${var.region}:${local.account}:trail/sentinel-trail"]
      }
    }
  }
  dynamic "statement" {
    for_each = each.key == "access" ? [1] : []
    content {
      sid     = "ServerAccessLogs"
      actions = ["s3:PutObject"]
      principals {
        type        = "Service"
        identifiers = ["logging.s3.amazonaws.com"]
      }
      resources = ["${aws_s3_bucket.b["access"].arn}/*"]
      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "b" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.b[each.key].id
  policy   = data.aws_iam_policy_document.bucket[each.key].json
}

# --- Seed data --------------------------------------------------------------------------

resource "aws_s3_object" "kb" {
  for_each     = fileset("${path.module}/../../kb", "*.md")
  bucket       = aws_s3_bucket.b["kb"].id
  key          = "kb/${each.value}"
  source       = "${path.module}/../../kb/${each.value}"
  etag         = filemd5("${path.module}/../../kb/${each.value}")
  content_type = "text/markdown"
}

resource "aws_s3_object" "finance" {
  for_each = fileset("${path.module}/../../finance", "*")
  bucket   = aws_s3_bucket.b["finance"].id
  key      = "records/${each.value}"
  source   = "${path.module}/../../finance/${each.value}"
  etag     = filemd5("${path.module}/../../finance/${each.value}")
}

# --- CloudTrail ---------------------------------------------------------------------------

resource "aws_cloudtrail" "trail" {
  # checkov:skip=CKV2_AWS_10:The SIEM reads the trail from S3 with its own role; a CloudWatch copy would duplicate it
  # checkov:skip=CKV_AWS_252:No SNS consumer; the SIEM polls the bucket every five minutes
  name                          = "sentinel-trail"
  s3_bucket_name                = aws_s3_bucket.b["trail"].id
  kms_key_id                    = aws_kms_key.data.arn
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # Management events, plus every object read and write in the two data buckets.
  advanced_event_selector {
    name = "management"
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }
  advanced_event_selector {
    name = "data buckets"
    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }
    field_selector {
      field       = "resources.ARN"
      starts_with = ["${aws_s3_bucket.b["kb"].arn}/", "${aws_s3_bucket.b["finance"].arn}/"]
    }
  }
  depends_on = [aws_s3_bucket_policy.b]
}
