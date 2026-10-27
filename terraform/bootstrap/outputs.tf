output "deploy_user_name" {
  description = "Create an access key for this user and store it as GitHub secrets."
  value       = aws_iam_user.github_deploy.name
}

output "tf_state_bucket" {
  description = "Set as the GitHub variable TF_STATE_BUCKET."
  value       = aws_s3_bucket.tfstate.bucket
}

output "aws_region" {
  description = "Set as the GitHub variable AWS_REGION."
  value       = var.aws_region
}
