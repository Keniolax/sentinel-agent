output "state_bucket" { value = aws_s3_bucket.state.bucket }
output "state_kms_key" { value = aws_kms_key.state.arn }
output "ecr_repository_url" { value = aws_ecr_repository.agent.repository_url }
output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
output "boundary_policy_arn" { value = aws_iam_policy.boundary.arn }
