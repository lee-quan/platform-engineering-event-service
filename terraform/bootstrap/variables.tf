variable "aws_region" {
  description = "Region for the state bucket and the only region the deploy user may use."
  type        = string
  default     = "ap-southeast-2"
}

variable "app_name" {
  description = "Base name for bootstrap resources. Must match app_name in the main configuration."
  type        = string
  default     = "event-service"
}
