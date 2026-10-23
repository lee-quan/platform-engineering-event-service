# One-time setup, applied locally with admin credentials:
#   - S3 bucket for the main configuration's Terraform state
#   - GitHub OIDC identity provider
#   - IAM role that GitHub Actions assumes to deploy
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
  oidc_url   = "https://token.actions.githubusercontent.com"
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

# --- GitHub OIDC provider -----------------------------------------------------

# Only one provider per URL can exist in an account. Set
# create_oidc_provider = false if another project already created it.
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = local.oidc_url
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = local.oidc_url
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# --- Deploy role assumed by GitHub Actions ------------------------------------

data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only workflow jobs running in one of these GitHub environments of this
    # repository can assume the role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for e in var.github_environments : "repo:${var.github_repo}:environment:${e}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.app_name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

# Broad service access (ECR, ECS, ELB, EC2 security groups, CloudWatch, S3).
# Simplified for a skeleton: replace with a least-privilege policy for production.
resource "aws_iam_role_policy_attachment" "power_user" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# PowerUserAccess excludes IAM, so allow managing only this app's roles.
data "aws_iam_policy_document" "iam_scoped" {
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
}

resource "aws_iam_role_policy" "iam_scoped" {
  name   = "manage-app-roles"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.iam_scoped.json
}
