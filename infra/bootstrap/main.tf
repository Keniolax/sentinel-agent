data "aws_caller_identity" "me" {}
data "aws_partition" "p" {}

locals {
  account = data.aws_caller_identity.me.account_id
  arn     = "arn:${data.aws_partition.p.partition}"
  # Every role, policy, instance profile and bucket that CI may manage starts with this.
  scope = "sentinel-"
}

# --- Terraform state for the main stack -------------------------------------------------

resource "aws_kms_key" "state" {
  description             = "sentinel-agent Terraform state"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AccountAdmin"
      Effect    = "Allow"
      Principal = { AWS = "${local.arn}:iam::${local.account}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

# trivy:ignore:AVD-AWS-0089 State bucket; every write comes from Terraform, and the bucket is versioned
resource "aws_s3_bucket" "state" {
  # checkov:skip=CKV_AWS_18:State bucket; every write comes from Terraform, and the bucket is versioned
  # checkov:skip=CKV_AWS_144:One-region lab; versioning covers a bad write, replication would double the cost
  # checkov:skip=CKV2_AWS_62:No consumer for object events on the state bucket
  bucket        = "sentinel-tfstate-${local.account}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-old-state"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 90 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "TLSOnly"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# --- Image registry ---------------------------------------------------------------------

resource "aws_kms_key" "ecr" {
  description             = "sentinel-agent image registry"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AccountAdmin"
      Effect    = "Allow"
      Principal = { AWS = "${local.arn}:iam::${local.account}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

resource "aws_ecr_repository" "agent" {
  name                 = "sentinel-agent"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }
}

resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the ten newest images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

# --- GitHub OIDC and the deploy role ----------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# The most any role that CI creates may ever do. CI must attach it to every role it makes,
# so a deploy cannot hand a new role more than the app and the SIEM need.
resource "aws_iam_policy" "boundary" {
  # checkov:skip=CKV_AWS_290:A permissions boundary is a ceiling, not a grant; each role's own policy scopes the resources
  # checkov:skip=CKV_AWS_355:Same reason: the boundary lists actions any sentinel role may hold, and the Deny keeps S3 to sentinel-* buckets
  name        = "gha-sentinel-boundary"
  description = "Permissions boundary for every sentinel-* role"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AppAndSiem"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketAcl", "s3:PutObject",
          "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey",
          "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:DescribeLogGroups",
          "logs:GetLogEvents", "logs:FilterLogEvents",
          "ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ssm:UpdateInstanceInformation", "ssm:ListInstanceAssociations", "ssm:DescribeInstanceProperties",
          "ssm:GetDocument", "ssm:DescribeDocument", "ssm:ListAssociations", "ssm:GetManifest",
          "ssm:PutInventory", "ssm:PutComplianceItems", "ssm:UpdateInstanceAssociationStatus",
          "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage", "ec2messages:DeleteMessage", "ec2messages:FailMessage",
          "ec2messages:GetEndpoint", "ec2messages:GetMessages", "ec2messages:SendReply",
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
      {
        Sid         = "OnlyLabBuckets"
        Effect      = "Deny"
        Action      = ["s3:GetObject", "s3:ListBucket", "s3:PutObject"]
        NotResource = ["${local.arn}:s3:::${local.scope}*", "${local.arn}:s3:::${local.scope}*/*"]
      },
    ]
  })
}

data "aws_iam_policy_document" "deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only a workflow on main may deploy. Pull requests and other branches get no AWS access.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "gha-sentinel-deploy"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "State"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }
  statement {
    sid       = "StateKey"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.state.arn]
  }
  statement {
    sid = "PushImage"
    actions = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:DescribeImages",
    "ecr:DescribeRepositories", "ecr:GetDownloadUrlForLayer"]
    resources = [aws_ecr_repository.agent.arn]
  }
  statement {
    sid       = "PushImageKey"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.ecr.arn]
  }
  statement {
    sid       = "RegistryLogin"
    actions   = ["ecr:GetAuthorizationToken", "sts:GetCallerIdentity"]
    resources = ["*"]
  }
  # The main stack's services, in this one region.
  statement {
    sid = "Services"
    actions = ["ec2:*", "ecs:*", "cloudtrail:*", "logs:*", "kms:*", "ssm:GetParameter", "ssm:GetParameters",
    "elasticloadbalancing:Describe*", "application-autoscaling:Describe*", "cloudwatch:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }
  statement {
    sid       = "LabBuckets"
    actions   = ["s3:CreateBucket", "s3:Get*", "s3:List*", "s3:Put*", "s3:Delete*"]
    resources = ["${local.arn}:s3:::${local.scope}*", "${local.arn}:s3:::${local.scope}*/*"]
  }
  statement {
    sid       = "ListBuckets"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }
  # Roles: only sentinel-* roles, and only with the boundary attached.
  statement {
    sid = "CreateBoundedRoles"
    actions = ["iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:AttachRolePolicy",
    "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy"]
    resources = ["${local.arn}:iam::${local.account}:role/${local.scope}*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.boundary.arn]
    }
  }
  statement {
    sid = "ManageScopedIam"
    actions = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy", "iam:UpdateRole", "iam:UpdateRoleDescription",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
      "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:ListPolicyVersions", "iam:TagPolicy",
    "iam:ListEntitiesForPolicy"]
    resources = ["${local.arn}:iam::${local.account}:role/${local.scope}*",
      "${local.arn}:iam::${local.account}:instance-profile/${local.scope}*",
    "${local.arn}:iam::${local.account}:policy/${local.scope}*"]
  }
  statement {
    sid       = "ReadBoundary"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = [aws_iam_policy.boundary.arn, "${local.arn}:iam::aws:policy/*"]
  }
  statement {
    sid       = "PassScopedRoles"
    actions   = ["iam:PassRole"]
    resources = ["${local.arn}:iam::${local.account}:role/${local.scope}*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "ec2.amazonaws.com", "cloudtrail.amazonaws.com"]
    }
  }
  statement {
    sid       = "EcsServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["ecs.amazonaws.com"]
    }
  }
  statement {
    sid    = "NeverTouchTheBoundary"
    effect = "Deny"
    actions = ["iam:DeleteRolePermissionsBoundary", "iam:CreatePolicyVersion", "iam:DeletePolicy",
    "iam:SetDefaultPolicyVersion"]
    resources = [aws_iam_policy.boundary.arn, "${local.arn}:iam::${local.account}:role/gha-*",
    "${local.arn}:iam::${local.account}:policy/gha-*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "gha-sentinel-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
