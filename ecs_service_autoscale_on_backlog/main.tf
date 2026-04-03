data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_ecs_service" "service" {
  name                   = var.ecs_task_definition_family_name
  tags                   = var.tags
  cluster                = var.ecs_cluster_arn
  task_definition        = var.ecs_task_definition_arn
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

  lifecycle {
    ignore_changes = [desired_count]
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/autoscaler.py"
  output_path = "/tmp/autoscaler.zip"
}

resource "aws_lambda_function" "scale_ecs" {
  function_name = "${var.ecs_task_definition_family_name}-autoscaler"
  tags          = var.tags
  role          = aws_iam_role.lambda_autoscaler_role.arn
  handler       = "autoscaler.lambda_handler"
  runtime       = "python3.13"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = filebase64sha256("${path.module}/autoscaler.py")

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.ecs_task_log_group.name
  }

  environment {
    variables = {
      CLUSTER_NAME            = var.ecs_cluster_name
      SERVICE_NAME            = aws_ecs_service.service.name
      SQS_QUEUE_URL           = var.backlog_per_task_queue_url
      BACKLOG_PER_TASK_TARGET = var.backlog_per_task_target
      MINIMUM_TASKS           = var.autoscaling_min
      MAXIMUM_TASKS           = var.autoscaling_max
    }
  }
  timeout = 30
}

resource "aws_iam_role" "lambda_autoscaler_role" {
  name = "${var.ecs_task_definition_family_name}-autoscaler-role"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Effect = "Allow"
    }]
  })
}

resource "aws_cloudwatch_log_group" "ecs_task_log_group" {
  name              = "/aws/lambda/${var.ecs_task_definition_family_name}-autoscaler"
  retention_in_days = var.environment == "production" ? 365 : 90
  tags              = var.tags
}

resource "aws_iam_policy" "lambda_autoscaler_policy" {
  name = "${var.ecs_task_definition_family_name}-autoscaler-policy"
  tags = var.tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${var.ecs_cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes"
        ]
        Resource = var.backlog_per_task_queue_arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecs_task_log_group.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_autoscaler_attach" {
  role       = aws_iam_role.lambda_autoscaler_role.name
  policy_arn = aws_iam_policy.lambda_autoscaler_policy.arn
}

resource "aws_cloudwatch_event_rule" "every_minute" {
  name                = "${var.ecs_task_definition_family_name}-autoscaler-rule"
  tags                = var.tags
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "invoke_lambda" {
  rule      = aws_cloudwatch_event_rule.every_minute.name
  target_id = "${var.ecs_task_definition_family_name}-autoscaler-target"
  arn       = aws_lambda_function.scale_ecs.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scale_ecs.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_minute.arn
}
