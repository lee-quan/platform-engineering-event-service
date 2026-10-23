variable "aws_region" {
  description = "Region for the state bucket (and the default deploy region)."
  type        = string
  default     = "eu-central-1"
}

variable "app_name" {
  description = "Base name for bootstrap resources. Must match app_name in the main configuration."
  type        = string
  default     = "event-service"
}

variable "github_repo" {
  description = "GitHub repository allowed to deploy, as owner/name."
  type        = string
  default     = "z3r0-m4n/platform-engineering-event-service"
}

variable "github_environments" {
  description = "GitHub environments whose workflow jobs may assume the deploy role."
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set to false if the account already has one."
  type        = bool
  default     = true
}
