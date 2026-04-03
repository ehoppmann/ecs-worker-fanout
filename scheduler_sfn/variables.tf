variable "resource_prefix" {
  type = string
}

variable "scheduler_name" {
  type        = string
  description = "A name for the scheduler, to avoid resource name collisions"
  default     = "scheduler"
}

variable "schedule_expression" {
  type = string
}

variable "ecs_cluster_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "scheduler_ecs_task_definition_arn" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "sfn_max_retries" {
  type        = number
  default     = 2
  description = "How many times to retry the step function on failure. Note that this counts from zero (1 = will retry once for two total tries)"
}

variable "sfn_timeout_seconds" {
  type        = number
  default     = 3600
  description = "Step function timeout in seconds. This is an aggregate time including any retries."
}

variable "scheduler_command_override" {
  type        = list(string)
  default     = null
  description = "Optional override command for the scheduler docker container."
}

variable "environment_variables" {
  type        = list(map(string))
  default     = null
  description = "Optional environment variables to pass to the scheduler"
}

variable "sns_topic_arn" {
  type        = string
  default     = null
  description = "Optional SNS topic to pass in environment variables to publish to"
}

variable "failure_notification_sns_topic_arn" {
  type        = string
  default     = null
  description = "Optional SNS topic to send failure notifications to"
}

variable "assign_public_ip" {
  type        = bool
  description = "Whether to assign a public IP to the ECS task"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags to add to resources in this module"
  default     = null
}
