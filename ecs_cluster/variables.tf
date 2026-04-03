variable "resource_prefix" {
  type        = string
  description = "The prefix to prepend to all resource names"
}

variable "container_insights" {
  type        = bool
  description = "Whether or not container insights are enabled for the cluster"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to add to resources in this module"
  default     = null
}
