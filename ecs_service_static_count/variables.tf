variable "ecs_task_definition_arn" {
  type = string
}

variable "ecs_task_definition_family_name" {
  type = string
}

variable "ecs_cluster_arn" {
  type = string
}

variable "desired_count" {
  type        = number
  description = "Desired task count - for a job _without_ autoscaling"
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "capacity_provider" {
  type    = string
  default = "FARGATE"
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
