resource "aws_ecs_service" "service" {
  name                   = var.ecs_task_definition_family_name
  tags                   = var.tags
  cluster                = var.ecs_cluster_arn
  task_definition        = var.ecs_task_definition_arn
  desired_count          = var.desired_count
  enable_execute_command = true

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
  }

  network_configuration {
    subnets          = var.subnet_ids
    assign_public_ip = var.assign_public_ip
    security_groups  = var.security_group_ids
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}
