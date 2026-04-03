variable "ecr_repository_name" {
  type        = string
  description = "Name of ECR Repository"
}

variable "tags" {
  type        = map(string)
  description = "Tags to add to resources in this module"
  default     = null
}
