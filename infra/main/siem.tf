# The SIEM: Wazuh manager and indexer from home-soc-lab on one EC2 instance. No SSH and no
# inbound port. An operator reaches it with SSM Session Manager.

data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  siem_root = "${path.module}/../../siem"
  wodle = templatefile("${local.siem_root}/aws-wodle.xml.tftpl", {
    trail_bucket = aws_s3_bucket.b["trail"].id
    account      = local.account
    region       = var.region
    log_group    = aws_cloudwatch_log_group.agent.name
  })
}

resource "aws_instance" "siem" {
  # checkov:skip=CKV_AWS_88:No NAT gateway (about $32 a month); the instance needs a public IP to reach SSM and download images, and its security group allows no inbound traffic
  # checkov:skip=CKV_AWS_46:User data holds base64 copies of siem/ files from this repository, which hold no secret; the Wazuh passwords are generated on the instance by init-env.sh
  ami                         = data.aws_ssm_parameter.ubuntu.value
  instance_type               = var.siem_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.siem.id]
  iam_instance_profile        = aws_iam_instance_profile.siem.name
  associate_public_ip_address = true
  monitoring                  = true
  ebs_optimized               = true
  user_data_replace_on_change = true

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # the manager container reaches the instance role through one bridge hop
    http_endpoint               = "enabled"
  }

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = aws_kms_key.data.arn
  }

  user_data = templatefile("${local.siem_root}/bootstrap.sh.tftpl", {
    compose_b64      = filebase64("${local.siem_root}/compose.sentinel.yaml")
    config_b64       = filebase64("${local.siem_root}/sentinel-config.sh")
    wodle_b64        = base64encode(local.wodle)
    rules_b64        = filebase64("${local.siem_root}/local_rules.xml")
    home_soc_lab_ref = var.home_soc_lab_ref
  })

  tags = { Name = "sentinel-siem" }

  lifecycle {
    # A new Ubuntu image every week must not replace the SIEM and lose its index.
    ignore_changes = [ami]
  }
}
