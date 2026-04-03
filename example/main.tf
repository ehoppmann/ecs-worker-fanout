terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      application = var.name
      ManagedBy   = "terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# Networking: use default VPC
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.name}-ecs-"
  vpc_id      = data.aws_vpc.default.id
  description = "Security group for ECS tasks"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------

module "ecr" {
  source              = "../ecr"
  ecr_repository_name = var.name
}

# ---------------------------------------------------------------------------
# Build and push Docker image
# ---------------------------------------------------------------------------

locals {
  app_hash = substr(sha1(join("", [
    filesha1("${path.module}/app/Dockerfile"),
    filesha1("${path.module}/app/scheduler.py"),
    filesha1("${path.module}/app/worker.py"),
  ])), 0, 12)
}

resource "null_resource" "docker_build_push" {
  depends_on = [module.ecr]

  triggers = {
    app_hash = local.app_hash
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ecr get-login-password --region ${var.aws_region} | \
        docker login --username AWS --password-stdin ${module.ecr.ecr_repository_url}
      docker build --platform linux/amd64 -t ${module.ecr.ecr_repository_url}:${local.app_hash} ${path.module}/app
      docker push ${module.ecr.ecr_repository_url}:${local.app_hash}
    EOT
  }
}

data "aws_ecr_image" "app" {
  depends_on      = [null_resource.docker_build_push]
  repository_name = var.name
  image_tag       = local.app_hash
}

# ---------------------------------------------------------------------------
# ECS Cluster
# ---------------------------------------------------------------------------

module "ecs_cluster" {
  source             = "../ecs_cluster"
  resource_prefix    = var.name
  container_insights = false
}

# ---------------------------------------------------------------------------
# Scheduler: ECS task that publishes messages 1-10 to SNS
# ---------------------------------------------------------------------------

module "scheduler_task" {
  source                = "../ecs_task"
  task_name             = "scheduler"
  resource_prefix       = var.name
  environment           = "sandbox"
  ecr_url               = module.ecr.ecr_repository_url
  ecr_image_hash        = data.aws_ecr_image.app.image_digest
  container_cpu_units   = 256
  container_memory      = 512
  entrypoint            = ["python3", "/app/scheduler.py"]
  output_sns_topic_name = "tasks"
}

# ---------------------------------------------------------------------------
# Scheduler Step Function: runs every 10 minutes
# ---------------------------------------------------------------------------

module "scheduler_sfn" {
  source                            = "../scheduler_sfn"
  resource_prefix                   = var.name
  schedule_expression               = "rate(1 day)"
  ecs_cluster_arn                   = module.ecs_cluster.ecs_cluster_arn
  task_role_arn                     = module.scheduler_task.ecs_task_role_arn
  execution_role_arn                = module.scheduler_task.ecs_execution_role_arn
  scheduler_ecs_task_definition_arn = module.scheduler_task.ecs_task_definition_arn
  sns_topic_arn                     = module.scheduler_task.output_sns_topic_arn
  subnet_ids                        = data.aws_subnets.default.ids
  security_group_ids                = [aws_security_group.ecs_tasks.id]
  assign_public_ip                  = true
}

# ---------------------------------------------------------------------------
# Worker: reads SQS messages, sleeps for N seconds, logs the number
# ---------------------------------------------------------------------------

module "worker_task" {
  source              = "../ecs_task"
  task_name           = "worker"
  resource_prefix     = var.name
  environment         = "sandbox"
  ecr_url             = module.ecr.ecr_repository_url
  ecr_image_hash      = data.aws_ecr_image.app.image_digest
  container_cpu_units = 256
  container_memory    = 512
  entrypoint          = ["python3", "/app/worker.py"]
  input_queue_subscription = {
    topic_arn         = module.scheduler_task.output_sns_topic_arn
    timeout_seconds   = 60
    retention_seconds = 3600
    delay_seconds     = 0
    retries           = 2
  }
}

module "worker_service" {
  source                          = "../ecs_service_autoscale_on_backlog"
  ecs_task_definition_arn         = module.worker_task.ecs_task_definition_arn
  ecs_task_definition_family_name = module.worker_task.ecs_task_definition_family_name
  ecs_cluster_arn                 = module.ecs_cluster.ecs_cluster_arn
  ecs_cluster_name                = module.ecs_cluster.ecs_cluster_name
  subnet_ids                      = data.aws_subnets.default.ids
  security_group_ids              = [aws_security_group.ecs_tasks.id]
  assign_public_ip                = true
  environment                     = "sandbox"
  autoscaling_min                 = 0
  autoscaling_max                 = 5
  backlog_per_task_target         = 2
  backlog_per_task_queue_arn      = module.worker_task.input_sqs_queue_arn
  backlog_per_task_queue_url      = module.worker_task.input_sqs_queue_url
}
