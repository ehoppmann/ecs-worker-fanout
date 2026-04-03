# ECS Worker Fanout Pattern - Terraform Modules

## Overview

This collection of Terraform modules implements the scheduler --> worker (--> additional workers…) fanout
design pattern, enabling reproducible creation of asynchronous queue-based workflows on AWS ECS Fargate.

Common use cases include:
- Periodic batch processing of data
- Scheduled cleanup or archival jobs
- Report generation
- Processing of payloads from an arbitrary SQS queue from another infrastructure component, autoscaled to achieve target delay
- Any workload where a scheduler publishes work items for parallel processing

This project implements a *scheduler* module, which is intended to run periodically and
publish work items to a SNS topic, and a *worker* module, which can subscribe an SQS queue
to the SNS topic to process the scheduled work. All of these run on ECS clusters using Fargate.

Worker scaling can be static or autoscaling based on queue depth.
An arbitrary number of workers can be chained or subscribed to a single topic.

## Design Pattern

This collection helps implement scheduled fanout workflows where:

1.  **Scheduled Jobs:** Initiate tasks on a schedule (i.e. using Step Functions via `scheduler_sfn`)
2.  **Queue:** Tasks are placed onto a SQS message queue via SNS.
3.  **Worker Services:** ECS services consume messages from the queue.

The design of this project was largely informed by the equivalent design pattern implementation in AWS Copilot:

- [AWS Copilot Scheduled Jobs](https://aws.github.io/copilot-cli/docs/concepts/jobs/)
- [AWS Copilot Worker Services](https://aws.github.io/copilot-cli/docs/concepts/services/)

## Modules

* `ecr`: Manages creation of the ECR image repositories needed to hold images for the scheduler and worker ECS tasks. One ECR repository and image can be shared across all of these in a single project most cases.
* `ecs_cluster`: Creates the ECS Cluster needed to run scheduler and worker tasks (one per project).
* `ecs_service_autoscale_on_backlog`: Defines an ECS Service that scales based on SQS queue depth.
* `ecs_service_static_count`: Defines an ECS Service with a fixed task count.
* `scheduler_sfn`: Implements scheduled pipeline initiation (e.g., Step Functions + EventBridge).
* `ecs_task`: Defines ECS Task Definitions (container image, resources, roles). A task definition is needed for every scheduler and worker service.

## AI Usage Statement
AI / LLM tools were used to sanitize this work of proprietary information, and update terraform as needed
for consistency with the sanitized version. Beyond sanitization and associated updating, no AI tools were
used to produce this work (the source files are entirely AI-free).
Note that this was a v1 POC implementation, further refinements are not included in this demo / portfolio repository.

## Usage Example
Below is a complete example implementing this design pattern.


`main.tf`
```terraform
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket  = "my-terraform-state-bucket"
    key     = "terraform/ecs-worker-fanout/main"
    region  = "us-east-1"
    profile = "my-aws-profile"
  }
}

provider "aws" { # needed to auto-set the environment default tag based on account ID
  alias  = "bootstrap_accountid"
  region = var.aws_region
}

data "aws_caller_identity" "current" {
  provider = aws.bootstrap_accountid
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.default_tags
  }
}

locals {
  aws_account_id = data.aws_caller_identity.current.account_id
  default_tags = {
    application = local.resource_prefix
    Name        = var.name
    environment = local.environment
    CostCenter  = var.cost_center
    Owner       = var.owner
  }
  environment     = lookup(var.accountid_to_environment, local.aws_account_id)
  resource_prefix = var.name
  custom_scheduler_iam_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:ListAllMyBucket"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  }
}

data "aws_subnets" "private_subnets" {
  filter {
    name   = "tag:Name"
    values = [lookup(var.private_subnets, local.environment)]
  }
}

data "aws_security_group" "default_security_group" {
  id = lookup(var.accountid_to_default_securitygroup, local.aws_account_id)
}

module "ecr" {
  source              = "./ecr"
  ecr_repository_name = "my_project/${local.resource_prefix}"
}

module "ecs_cluster" {
  source          = "./ecs_cluster"
  resource_prefix = local.resource_prefix
}

module "ecs_scheduler_task" {
  source                = "./ecs_task"
  task_name             = "scheduler"
  resource_prefix       = local.resource_prefix
  environment           = local.environment
  ecr_url               = module.ecr.ecr_repository_url
  ecr_image_hash        = var.ecr_image_sha_hash
  container_cpu_units   = 256
  container_memory      = 512
  output_sns_topic_name = "tasks"
  environment_variables = [{
    name  = "TEST_KEY"
    value = "TEST_VALUE"
  }]
  secrets = [{
    name       = "MY_API_KEY"
    secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:my-project/api-key-AbCdEf"
  }]
  user_iam_role_policy = jsonencode(local.custom_scheduler_iam_policy)
}

module "scheduler_sfn" {
  source                            = "./scheduler_sfn"
  resource_prefix                   = local.resource_prefix
  schedule_expression               = "cron(0/10 * * * ? *)"
  subnet_ids                        = data.aws_subnets.private_subnets.ids
  security_group_ids                = [data.aws_security_group.default_security_group.id]
  ecs_cluster_arn                   = module.ecs_cluster.ecs_cluster_arn
  task_role_arn                     = module.ecs_scheduler_task.ecs_task_role_arn
  execution_role_arn                = module.ecs_scheduler_task.ecs_execution_role_arn
  scheduler_ecs_task_definition_arn = module.ecs_scheduler_task.ecs_task_definition_arn
  sns_topic_arn                     = module.ecs_scheduler_task.output_sns_topic_arn
  failure_notification_sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:ops-alerts"
}

module "ecs_primary_worker_task" {
  source          = "./ecs_task"
  depends_on      = [module.scheduler_sfn]
  task_name       = "primary_worker"
  resource_prefix = local.resource_prefix
  environment     = local.environment
  secrets = [
    {
      name       = "MY_API_KEY"
      secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:my-project/api-key-AbCdEf"
    }
  ]
  ecr_url               = module.ecr.ecr_repository_url
  ecr_image_hash        = var.ecr_image_sha_hash
  container_cpu_units   = 256
  container_memory      = 512
  output_sns_topic_name = "secondary_tasks"
  entrypoint            = ["/usr/bin/env", "python3", "/app/worker.py"]
  input_queue_subscription = {
    topic_arn         = module.ecs_scheduler_task.output_sns_topic_arn
    timeout_seconds   = 1800
    retention_seconds = 86400
    delay_seconds     = 0
    retries           = 3
  }
}

module "ecs_primary_worker_service" {
  source                          = "./ecs_service_autoscale_on_backlog"
  environment                     = local.environment
  depends_on                      = [module.ecs_primary_worker_task]
  ecs_task_definition_arn         = module.ecs_primary_worker_task.ecs_task_definition_arn
  ecs_task_definition_family_name = module.ecs_primary_worker_task.ecs_task_definition_family_name
  ecs_cluster_arn                 = module.ecs_cluster.ecs_cluster_arn
  subnet_ids                      = data.aws_subnets.private_subnets.ids
  security_group_ids              = [data.aws_security_group.default_security_group.id]
  capacity_provider               = "FARGATE_SPOT"
  ecs_cluster_name                = module.ecs_cluster.ecs_cluster_name
  autoscaling_min                 = 1
  autoscaling_max                 = 10
  backlog_per_task_target         = 10
  backlog_per_task_queue_arn      = module.ecs_primary_worker_task.input_sqs_queue_arn
  backlog_per_task_queue_url      = module.ecs_primary_worker_task.input_sqs_queue_url
}
```

`variables.tf`
```terraform
variable "name" {
  type = string
}

variable "cost_center" {
  type = string
}

variable "owner" {
  type        = string
  description = "The email address of the person with primary responsibility for this infrastructure."
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "private_subnets" {
  type        = map(string)
  description = "Map of environment name to private subnet tag name"
}

variable "accountid_to_environment" {
  type        = map(string)
  description = "Map of AWS account ID to environment name"
}

variable "accountid_to_default_securitygroup" {
  type        = map(string)
  description = "Map of AWS account ID to default security group ID"
}

variable "ecr_image_sha_hash" {
  type = string
}
```

`example.tfvars`
```terraform
name               = "my-ecs-pipeline"
owner              = "user@example.com"
cost_center        = "Engineering"
ecr_image_sha_hash = "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
```
