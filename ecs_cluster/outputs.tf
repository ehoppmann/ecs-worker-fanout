output "ecs_cluster_arn" {
  value       = aws_ecs_cluster.ecs_cluster.arn
  description = "The ARN of the ECS cluster created by this module"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.ecs_cluster.name
}
