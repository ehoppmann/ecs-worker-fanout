variable "task_name" {
  type        = string
  description = "The name of the task"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.task_name))
    error_message = "The task_name must contain only alphanumeric characters (a-z, A-Z, 0-9), dashes (-), or underscores (_), with no spaces or other special characters."
  }
}

variable "resource_prefix" {
  type        = string
  description = "The prefix to prepend to all resource names"
}

variable "environment" {
  type        = string
  description = "The deployment environment. Must be one of: staging, production, or sandbox."

  validation {
    condition     = contains(["staging", "production", "sandbox"], var.environment)
    error_message = "Environment must be one of: 'staging', 'production', or 'sandbox'."
  }
}

variable "secrets" {
  type = list(object({
    name       = string
    secret_arn = string
  }))
  default     = []
  description = "Map of secrets to add to environment variables."
}

variable "ecr_url" {
  type        = string
  description = "The ECR repository URL"
}

variable "ecr_image_hash" {
  type        = string
  description = "The ECR image sha256 hash"
}

variable "entrypoint" {
  type        = list(string)
  description = "Optional entrypoint override for container"
  default     = null
}

variable "container_cpu_units" {
  type = number
}

variable "container_memory" {
  type = number
}

variable "environment_variables" {
  type    = list(map(string))
  default = []
}

variable "cpu_architecture" {
  type    = string
  default = "X86_64"
}

variable "output_sns_topic_name" {
  type        = string
  default     = null
  description = "Optional: name of the SNS topic to create and make available to publish to, ARN exported as an environment variable"
}

variable "input_queue_subscription" {
  type = object({
    topic_arn         = string
    timeout_seconds   = number
    retention_seconds = number
    delay_seconds     = number
    retries           = number
  })
  default     = null
  description = "Optional: parameters of the SNS topic to subscribe an SQS queue to, ARN exported as an environment variable"
}

variable "user_iam_role_policy" {
  type        = string
  description = "Optional json encoded custom IAM policy to attach to the task role"
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags to add to resources in this module"
  default     = null
}
