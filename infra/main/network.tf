# Two public subnets and no NAT gateway: a NAT gateway costs about $32 a month, which is
# most of this lab's budget. Nothing here accepts inbound traffic. Each security group
# allows only outbound HTTPS (and HTTP for the SIEM's package mirror).


resource "aws_vpc" "lab" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "sentinel" }
}

resource "aws_default_security_group" "lab" {
  vpc_id = aws_vpc.lab.id
  # No rules: the default group allows nothing.
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(aws_vpc.lab.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags              = { Name = "sentinel-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# trivy:ignore:AVD-AWS-0104 Egress is HTTPS only; ECR, S3 and CloudWatch Logs are public endpoints, and VPC endpoints to narrow it cost about $7 a month each
resource "aws_security_group" "agent" {
  # checkov:skip=CKV2_AWS_5:ECS attaches this group at run-task time (scripts/ask.sh); no Terraform resource holds a running task
  name        = "sentinel-agent"
  description = "Agent task: no inbound, HTTPS out to ECR, S3 and CloudWatch Logs"
  vpc_id      = aws_vpc.lab.id
  egress {
    description = "HTTPS to AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# trivy:ignore:AVD-AWS-0104 Egress is HTTPS and HTTP only, to AWS endpoints, GitHub, the image registry and the Ubuntu mirror; no NAT or endpoints in this lab
resource "aws_security_group" "siem" {
  name        = "sentinel-siem"
  description = "SIEM host: no inbound; SSM, S3, CloudWatch Logs, image and package downloads out"
  vpc_id      = aws_vpc.lab.id
  egress {
    description = "HTTPS to AWS APIs, GitHub and the container registry"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "HTTP to the Ubuntu package mirror"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_flow_log" "lab" {
  vpc_id               = aws_vpc.lab.id
  traffic_type         = "REJECT"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow.arn
  iam_role_arn         = aws_iam_role.flow.arn
}
