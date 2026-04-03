data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  env_vars          = var.environment_variables != null ? var.environment_variables : []
  env_var_sns_topic = var.sns_topic_arn != null ? [{ Name = "SNS_TOPIC_ARN", Value = var.sns_topic_arn }] : []
  env_vars_merged   = concat(local.env_vars, local.env_var_sns_topic)

  container_overrides = merge(
    { Name = var.scheduler_name },
    var.scheduler_command_override != null ? { Command = var.scheduler_command_override } : {},
    length(local.env_vars_merged) > 0 ? {
      Environment = [
        for env in local.env_vars_merged : {
          Name  = env.Name
          Value = env.Value
        }
      ]
    } : {}
  )

  base_ecs_task_state = {
    Type     = "Task"
    Resource = "arn:aws:states:::ecs:runTask.sync"
    Parameters = {
      LaunchType           = "FARGATE"
      Cluster              = var.ecs_cluster_arn
      TaskDefinition       = var.scheduler_ecs_task_definition_arn
      EnableExecuteCommand = true
      NetworkConfiguration = {
        AwsvpcConfiguration = {
          Subnets        = var.subnet_ids
          SecurityGroups = var.security_group_ids
          AssignPublicIp = var.assign_public_ip ? "ENABLED" : "DISABLED"
        }
      }
      Overrides = {
        ContainerOverrides = [local.container_overrides]
      }
    }
    TimeoutSeconds = var.sfn_timeout_seconds
    Retry = [
      {
        ErrorEquals = ["States.ALL"]
        MaxAttempts = var.sfn_max_retries
      }
    ]
    End = true
  }

  ecs_task_state_catch_block = var.failure_notification_sns_topic_arn != null ? {
    Catch = [
      {
        ErrorEquals = ["States.ALL"]
        Next        = "NotifyFailure"
        ResultPath  = "$.errorInfo"
      }
    ]
  } : {}

  ecs_task_state = merge(local.base_ecs_task_state, local.ecs_task_state_catch_block)

  sns_failure_notification_state = {
    Type     = "Task"
    Resource = "arn:aws:states:::sns:publish"
    Parameters = {
      TopicArn = var.failure_notification_sns_topic_arn
      Message = {
        "StateMachineArn.$" = "$$.StateMachine.Id",
        "ExecutionArn.$"    = "$$.Execution.Id",
        "StateName.$"       = "$$.State.Name",
        "EnteredTime.$"     = "$$.State.EnteredTime",
        "Error.$"           = "$.errorInfo.Error",
        "Cause.$"           = "$.errorInfo.Cause"
      }
    }
    Next = "MarkAsFailed"
  }

  mark_as_failed_state = {
    Type  = "Fail"
    Error = "ECSTaskFailed"
    Cause = "The ECS task execution failed"
  }

  base_states_map = {
    RunECSTask = local.ecs_task_state
  }

  conditional_states_map = merge(
    var.failure_notification_sns_topic_arn != null ? { NotifyFailure = local.sns_failure_notification_state } : {},
    var.failure_notification_sns_topic_arn != null ? { MarkAsFailed = local.mark_as_failed_state } : {}
  )

  final_states_map = merge(local.base_states_map, local.conditional_states_map)

  state_machine_definition = jsonencode({
    Comment = "Scheduled ECS Task Execution"
    StartAt = "RunECSTask"
    States  = local.final_states_map # Use the final merged map
  })
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.resource_prefix}_${var.scheduler_name}_schedule"
  tags                = var.tags
  description         = "Schedule for ${var.resource_prefix}"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "event_target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "${var.resource_prefix}_${var.scheduler_name}_sfnTarget"
  role_arn  = aws_iam_role.cw_events_role.arn
  arn       = aws_sfn_state_machine.run_scheduler.id
}

resource "aws_iam_role_policy" "cw_events_role_policy" {
  name = "${var.resource_prefix}_${var.scheduler_name}_CWEventsRolePolicy"
  role = aws_iam_role.cw_events_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "states:StartExecution"
        Resource = aws_sfn_state_machine.run_scheduler.id
      }
    ]
  })
}

resource "aws_iam_role" "cw_events_role" {
  name = "${var.resource_prefix}_${var.scheduler_name}_CWEventsRole"
  tags = var.tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "events.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_sfn_state_machine" "run_scheduler" {
  name       = "${var.resource_prefix}_${var.scheduler_name}_scheduler"
  tags       = var.tags
  role_arn   = aws_iam_role.sfn_exec_role.arn
  depends_on = [aws_iam_role_policy.sfn_exec_policy]
  definition = local.state_machine_definition
}

data "aws_iam_policy_document" "step_function_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn_exec_role" {
  name               = "${var.resource_prefix}_${var.scheduler_name}_sfn-exec-role"
  tags               = var.tags
  assume_role_policy = data.aws_iam_policy_document.step_function_assume_role.json
}

resource "aws_iam_role_policy" "sfn_exec_policy" {
  name   = "${var.resource_prefix}_${var.scheduler_name}_sfn-exec-policy"
  role   = aws_iam_role.sfn_exec_role.id
  policy = data.aws_iam_policy_document.sfn_exec_policy.json
}

data "aws_iam_policy_document" "sfn_exec_policy" {
  statement {
    effect = "Allow"
    actions = [
      "events:PutTargets",
      "events:PutRule",
      "events:DescribeRule"
    ]
    resources = [
      aws_cloudwatch_event_rule.schedule.arn,
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "iam:PassRole",
      "iam:GetRole"
    ]
    resources = [
      var.task_role_arn,
      var.execution_role_arn
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "ecs:RunTask",
      "ecs:DescribeTasks",
      "ecs:StopTask"
    ]
    resources = [var.scheduler_ecs_task_definition_arn]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.ecs_cluster_arn]
    }
  }
  statement {
    effect = "Allow"
    actions = [
      "ecs:StopTask",
      "ecs:DescribeTasks"
    ]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.ecs_cluster_arn]
    }
  }
  statement { # This block is needed for the automatically created sfn rules when using the `runTask.sync` integration
    effect = "Allow"
    actions = [
      "events:PutRule",
      "events:PutTargets",
      "events:DeleteRule",
      "events:DescribeRule",
      "events:TagResource"
    ]
    resources = [
      "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForECSTaskRule*"
    ]
  }
  dynamic "statement" {
    for_each = var.failure_notification_sns_topic_arn != null ? [var.failure_notification_sns_topic_arn] : []
    content {
      effect    = "Allow"
      actions   = ["sns:Publish"]
      resources = [statement.value]
    }
  }
}
