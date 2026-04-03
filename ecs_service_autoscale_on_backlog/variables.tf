variable "ecs_task_definition_arn" {
  type = string
}

variable "ecs_task_definition_family_name" {
  type = string
}

variable "ecs_cluster_arn" {
  type = string
}

variable "capacity_provider" {
  type    = string
  default = "FARGATE"
}

variable "backlog_per_task_queue_url" {
  type        = string
  description = "The URL of the SQS queue to use to compute the backlog per task to scale against"
}

variable "backlog_per_task_queue_arn" {
  type        = string
  description = "The ARN of the SQS queue to use to compute the backlog per task to scale against"
}

variable "backlog_per_task_target" {
  type        = number
  description = "The target number of backlogged work items in SQS per task worker"
}

variable "autoscaling_min" {
  type    = number
  default = 0
}

variable "autoscaling_max" {
  type = number
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "ecs_cluster_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "assign_public_ip" {
  type        = bool
  description = "Whether to assign a public IP to the ECS tasks"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags to add to resources in this module"
  default     = null
}
