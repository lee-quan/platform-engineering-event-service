# One-time setup, applied locally with admin credentials:
#   - S3 bucket for the main configuration's Terraform state
#   - IAM user that GitHub Actions uses to deploy
#
# The organization's SCPs block GitHub OIDC providers in this account, so the
# workflow authenticates with an access key for this user. The key is created
# outside Terraform (console or CLI) so the secret never lands in state.
#
# This configuration keeps its own (small) state locally.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Application = var.app_name
      ManagedBy   = "terraform-bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# --- Terraform state bucket ---------------------------------------------------

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.app_name}-tfstate-${local.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Deploy user used by GitHub Actions ---------------------------------------

resource "aws_iam_user" "github_deploy" {
  name = "${var.app_name}-github-deploy"
}

# Broad service access (ECR, ECS, ELB, EC2 security groups, CloudWatch, S3).
# Simplified for a skeleton: replace with a least-privilege policy for production.
resource "aws_iam_user_policy_attachment" "power_user" {
  user       = aws_iam_user.github_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "deploy_extra" {
  # PowerUserAccess excludes IAM, so allow managing only this app's roles.
  statement {
    sid = "ManageAppRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.app_name}-*"]
  }

  # ECS and ELB create their service-linked roles on first use in an account.
  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
      ]
    }
  }

  # Long-lived keys: limit the blast radius to the deploy region.
  statement {
    sid         = "DenyOtherRegions"
    effect      = "Deny"
    not_actions = ["iam:*", "sts:*"]
    resources   = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

resource "aws_iam_user_policy" "deploy_extra" {
  name   = "deploy-extra"
  user   = aws_iam_user.github_deploy.name
  policy = data.aws_iam_policy_document.deploy_extra.json
}
