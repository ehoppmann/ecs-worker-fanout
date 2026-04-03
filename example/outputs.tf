output "ecr_repository_url" {
  value = module.ecr.ecr_repository_url
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.ecs_cluster_name
}

output "state_machine_arn" {
  value = module.scheduler_sfn.state_machine_arn
}

output "worker_sqs_queue_url" {
  value = module.worker_task.input_sqs_queue_url
}
