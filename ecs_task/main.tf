data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  env_vars          = var.environment_variables != null ? var.environment_variables : []
  env_var_sns_topic = var.output_sns_topic_name != null ? [{ Name = "SNS_TOPIC_ARN", Value = aws_sns_topic.output_sns_topic[0].arn }] : []
  env_var_sqs_queue = var.input_queue_subscription != null ? [{ Name = "SQS_QUEUE_URL", Value = aws_sqs_queue.input_queue[0].url }] : []
  env_vars_merged   = concat(local.env_vars, local.env_var_sns_topic, local.env_var_sqs_queue)
}

resource "aws_ecs_task_definition" "ecs_task" {
  family                   = "${var.resource_prefix}_${var.task_name}"
  tags                     = var.tags
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu_units
  memory                   = var.container_memory
  network_mode             = "awsvpc"
  runtime_platform {
    cpu_architecture = var.cpu_architecture
  }
  execution_role_arn = aws_iam_role.execution_role.arn
  task_role_arn      = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name        = var.task_name
      image       = "${var.ecr_url}@${var.ecr_image_hash}"
      entrypoint  = var.entrypoint
      essential   = true
      environment = local.env_vars_merged
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-region        = data.aws_region.current.name,
          awslogs-stream-prefix = "ecs"
          awslogs-group         = aws_cloudwatch_log_group.ecs_task_log_group.name
        }
      }
      secrets = [
        for s in var.secrets : {
          name      = s.name
          valueFrom = s.secret_arn
        }
      ]
    }
  ])
}

resource "aws_cloudwatch_log_group" "ecs_task_log_group" {
  name              = "/ecs/${var.resource_prefix}_${var.task_name}"
  tags              = var.tags
  retention_in_days = var.environment == "production" ? 365 : 90
}

resource "aws_iam_role" "execution_role" {
  name = "${var.resource_prefix}_${var.task_name}_execution_role"
  tags = var.tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  max_session_duration = 3600
}

resource "aws_sns_topic" "output_sns_topic" {
  count = var.output_sns_topic_name != null ? 1 : 0
  tags  = var.tags
  name  = "${var.resource_prefix}_${var.output_sns_topic_name}"
}

resource "aws_iam_role_policy" "task_role_publish_sns" {
  count = var.output_sns_topic_name != null ? 1 : 0
  name  = "${var.resource_prefix}_${var.task_name}_SNS"
  role  = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["sns:Publish"],
        Resource = aws_sns_topic.output_sns_topic[0].arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "execution_role_ecs_managed_policy" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_role_inline_policy" { # Policy to give access to application's secrets, using tags for access control, if any exist
  name = "${var.resource_prefix}_${var.task_name}_SecretsPolicy"
  role = aws_iam_role.execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = ["arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:*"],
        Condition = {
          StringEquals = {
            "secretsmanager:ResourceTag/application" = var.resource_prefix,
            "secretsmanager:ResourceTag/environment" = var.environment
          }
        }
      },
    ]
  })
}

resource "aws_iam_role" "task_role" {
  name = "${var.resource_prefix}_${var.task_name}_task_role"
  tags = var.tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  max_session_duration = 3600
}

resource "aws_iam_role_policy" "deny_iam" { # Explicitly deny - safety measure copied from copilot
  name = "${var.resource_prefix}_${var.task_name}_DenyIAM"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Deny",
        Action   = "iam:*",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "task_role-execute_command" { # basic logging and SSM perms
  name = "${var.resource_prefix}_${var.task_name}_ExecuteCommand"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenDataChannel"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ],
        Resource = "${aws_cloudwatch_log_group.ecs_task_log_group.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudwatch_put_metric" { # always allow our tasks to put metric data
  name = "${var.resource_prefix}_${var.task_name}_CloudWatchPutMetric"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "CloudWatchPutMetric",
        Effect   = "Allow",
        Action   = ["cloudwatch:PutMetricData"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "sqs_actions" {
  count = var.input_queue_subscription != null ? 1 : 0
  name  = "${var.resource_prefix}_${var.task_name}_SQSActions"
  role  = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "SQSActions",
        Effect = "Allow",
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage"
        ],
        Resource = [
          aws_sqs_queue.input_queue[0].arn,
          aws_sqs_queue.dead_letter_queue[0].arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "user_policy" {
  count = var.user_iam_role_policy != null ? 1 : 0
  name  = "${var.resource_prefix}_${var.task_name}_CustomPolicy"
  role  = aws_iam_role.task_role.id

  policy = var.user_iam_role_policy
}

resource "aws_sqs_queue" "input_queue" {
  count = var.input_queue_subscription != null ? 1 : 0
  tags  = var.tags
  name  = "${var.resource_prefix}_${var.task_name}_input_queue"

  delay_seconds              = var.input_queue_subscription.delay_seconds
  message_retention_seconds  = var.input_queue_subscription.retention_seconds
  visibility_timeout_seconds = var.input_queue_subscription.timeout_seconds
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter_queue[0].arn
    maxReceiveCount     = var.input_queue_subscription.retries + 1
  })
  sqs_managed_sse_enabled = true
}

resource "aws_sqs_queue_policy" "input_queue_policy" {
  count = var.input_queue_subscription != null ? 1 : 0

  depends_on = [aws_sqs_queue.input_queue]
  queue_url  = aws_sqs_queue.input_queue[0].id
  policy     = data.aws_iam_policy_document.sqs_queue_policy_input[0].json
}

resource "aws_sqs_queue" "dead_letter_queue" {
  count = var.input_queue_subscription != null ? 1 : 0
  tags  = var.tags
  name  = "${var.resource_prefix}_${var.task_name}_DeadLetterQueue"

  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue_policy" "dead_letter_queue_policy" {
  count = var.input_queue_subscription != null ? 1 : 0

  depends_on = [aws_sqs_queue.dead_letter_queue]
  queue_url  = aws_sqs_queue.dead_letter_queue[0].id
  policy     = data.aws_iam_policy_document.sqs_queue_policy_dlq[0].json
}

resource "aws_sns_topic_subscription" "input_queue_topic_subscription" {
  count = var.input_queue_subscription != null ? 1 : 0

  topic_arn = var.input_queue_subscription.topic_arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.input_queue[0].arn
}

data "aws_iam_policy_document" "sqs_queue_policy_input" {
  count = var.input_queue_subscription != null ? 1 : 0
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.task_role.arn]
    }

    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage"
    ]
    resources = [
      aws_sqs_queue.input_queue[0].arn
    ]
  }

  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    actions = ["sqs:SendMessage"]

    resources = [
      aws_sqs_queue.input_queue[0].arn
    ]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.input_queue_subscription.topic_arn]
    }
  }
}

data "aws_iam_policy_document" "sqs_queue_policy_dlq" {
  count = var.input_queue_subscription != null ? 1 : 0
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.task_role.arn]
    }

    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage"
    ]
    resources = [
      aws_sqs_queue.dead_letter_queue[0].arn
    ]
  }
}
