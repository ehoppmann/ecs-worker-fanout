output "ecs_task_definition_arn" {
  value       = aws_ecs_task_definition.ecs_task.arn
  description = "The ARN of the task definition"
}

output "ecs_task_definition_family_name" {
  value       = aws_ecs_task_definition.ecs_task.family
  description = "The family of the task definition"
}

output "ecs_task_definition_revision" {
  value       = aws_ecs_task_definition.ecs_task.revision
  description = "The revision of the task definition revision"
}

output "ecs_task_role_arn" {
  value       = aws_iam_role.task_role.arn
  description = "The ARN of the task role"
}

output "ecs_execution_role_arn" {
  value       = aws_iam_role.execution_role.arn
  description = "The ARN of the execution role"
}

output "output_sns_topic_arn" {
  value       = var.output_sns_topic_name != null ? aws_sns_topic.output_sns_topic[0].arn : null
  description = "The ARN of the output SNS topic, if output_sns_topic_name was defined, otherwise null"
}

output "input_sqs_queue_url" {
  value = var.input_queue_subscription != null ? aws_sqs_queue.input_queue[0].id : null
}

output "input_sqs_queue_arn" {
  value = var.input_queue_subscription != null ? aws_sqs_queue.input_queue[0].arn : null
}
