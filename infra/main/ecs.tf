resource "aws_cloudwatch_log_group" "agent" {
  name              = "/sentinel/agent"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.data.arn
}

resource "aws_cloudwatch_log_group" "flow" {
  name              = "/sentinel/vpc-flow"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.data.arn
}

resource "aws_ecs_cluster" "lab" {
  name = "sentinel"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# One task answers one question and stops. Nothing runs between questions.
resource "aws_ecs_task_definition" "agent" {
  family                   = "sentinel-agent"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 2048
  memory                   = 8192
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = aws_iam_role.task.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  volume { name = "tmp" }
  volume { name = "orders-tmp" }

  container_definitions = jsonencode([
    {
      name                   = "orders-api"
      image                  = var.agent_image
      command                = ["orders-api"]
      essential              = false
      readonlyRootFilesystem = true
      user                   = "10001"
      mountPoints            = [{ sourceVolume = "orders-tmp", containerPath = "/tmp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.agent.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "orders-api"
        }
      }
    },
    {
      name                   = "agent"
      image                  = var.agent_image
      command                = ["ask"]
      essential              = true
      readonlyRootFilesystem = true
      user                   = "10001"
      dependsOn              = [{ containerName = "orders-api", condition = "START" }]
      mountPoints            = [{ sourceVolume = "tmp", containerPath = "/tmp" }]
      environment = [
        { name = "KB_BUCKET", value = aws_s3_bucket.b["kb"].id },
        { name = "ORDERS_URL", value = "http://127.0.0.1:8081" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.agent.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "agent"
        }
      }
    },
  ])
}
