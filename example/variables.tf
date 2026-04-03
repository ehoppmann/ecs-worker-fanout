variable "name" {
  type        = string
  description = "Name prefix for all resources"
  default     = "ecs-fanout-demo"
}

variable "aws_region" {
  type        = string
  description = "AWS region to deploy into"
  default     = "us-east-1"
}
