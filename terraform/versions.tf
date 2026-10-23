terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial configuration: bucket, key and region are passed at init time, e.g.
  #   terraform init \
  #     -backend-config="bucket=<tf_state_bucket from bootstrap>" \
  #     -backend-config="key=event-service/dev.tfstate" \
  #     -backend-config="region=eu-central-1"
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Application = var.app_name
      Environment = var.env
      ManagedBy   = "terraform"
    }
  }
}
