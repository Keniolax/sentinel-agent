# Every role carries the bootstrap stack's permissions boundary, so none can exceed it.

data "aws_iam_policy_document" "ecs_tasks" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

# ECS uses this role to pull the image and write logs. The agent's code never holds it.
resource "aws_iam_role" "exec" {
  name                 = "sentinel-task-exec"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks.json
  permissions_boundary = var.boundary_policy_arn
}

data "aws_iam_policy_document" "exec" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    resources = ["${local.arn}:ecr:${var.region}:${local.account}:repository/sentinel-agent"]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ecr.${var.region}.amazonaws.com"]
    }
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.agent.arn}:*"]
  }
}

resource "aws_iam_role_policy" "exec" {
  name   = "sentinel-task-exec"
  role   = aws_iam_role.exec.id
  policy = data.aws_iam_policy_document.exec.json
}

# The agent's own identity: read the knowledge base prefix, nothing else.
resource "aws_iam_role" "task" {
  name                 = "sentinel-agent-task"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks.json
  permissions_boundary = var.boundary_policy_arn
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "ListKnowledgeBase"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.b["kb"].arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["kb/", "kb/*"]
    }
  }
  statement {
    sid       = "ReadKnowledgeBase"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.b["kb"].arn}/kb/*"]
  }
  statement {
    sid       = "DecryptKnowledgeBase"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.data.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "sentinel-agent-task"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

# The SIEM host: reached through SSM, reads the trail bucket and the agent's log group.
data "aws_iam_policy_document" "ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "siem" {
  name                 = "sentinel-siem"
  assume_role_policy   = data.aws_iam_policy_document.ec2.json
  permissions_boundary = var.boundary_policy_arn
}

resource "aws_iam_role_policy_attachment" "siem_ssm" {
  role       = aws_iam_role.siem.name
  policy_arn = "${local.arn}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "siem" {
  statement {
    sid       = "ReadTrail"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.b["trail"].arn, "${aws_s3_bucket.b["trail"].arn}/*"]
  }
  statement {
    sid       = "ReadAgentLogs"
    actions   = ["logs:DescribeLogStreams", "logs:GetLogEvents", "logs:FilterLogEvents"]
    resources = [aws_cloudwatch_log_group.agent.arn, "${aws_cloudwatch_log_group.agent.arn}:*"]
  }
  statement {
    sid       = "ListLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
  statement {
    sid       = "DecryptTrailAndLogs"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.data.arn]
  }
}

resource "aws_iam_role_policy" "siem" {
  name   = "sentinel-siem"
  role   = aws_iam_role.siem.id
  policy = data.aws_iam_policy_document.siem.json
}

resource "aws_iam_instance_profile" "siem" {
  name = "sentinel-siem"
  role = aws_iam_role.siem.name
}

# VPC flow logs write rejected connections to CloudWatch Logs.
data "aws_iam_policy_document" "flow_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

resource "aws_iam_role" "flow" {
  name                 = "sentinel-flow-logs"
  assume_role_policy   = data.aws_iam_policy_document.flow_trust.json
  permissions_boundary = var.boundary_policy_arn
}

data "aws_iam_policy_document" "flow" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:DescribeLogGroups"]
    resources = [aws_cloudwatch_log_group.flow.arn, "${aws_cloudwatch_log_group.flow.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow" {
  name   = "sentinel-flow-logs"
  role   = aws_iam_role.flow.id
  policy = data.aws_iam_policy_document.flow.json
}
