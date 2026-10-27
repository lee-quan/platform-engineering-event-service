variable "env" {
  description = "Deployment environment. Also passed to the container as ENV."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be one of: dev, staging, prod."
  }
}

variable "cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB. Must be a valid pairing with cpu."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of running tasks. Note: the service keeps events in memory, so tasks do not share state."
  type        = number
  default     = 1
}

variable "container_port" {
  description = "Port the container listens on. Also passed to the container as PORT."
  type        = number
  default     = 8080
}

# --- Supporting variables -----------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-southeast-2"
}

variable "app_name" {
  description = "Base name for all resources."
  type        = string
  default     = "event-service"
}

variable "image_tag" {
  description = "Tag of the image in ECR to deploy."
  type        = string
  default     = "latest"
}

variable "cpu_architecture" {
  description = "Task CPU architecture. Must match the image: ARM64 for images built on Apple Silicon, X86_64 for --platform linux/amd64 builds."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "processing_delay_ms" {
  description = "Passed to the container as PROCESSING_DELAY_MS."
  type        = number
  default     = 1000
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 14
}
