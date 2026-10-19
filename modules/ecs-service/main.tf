data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# ---------------------------------------------------------------------------
# IAM: two roles with very different jobs
#   execution role = used by the ECS AGENT (pull image, write logs, fetch secrets)
#   task role      = used by YOUR CODE inside the container (like an IRSA role on EKS)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "read_secrets" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.secret_arns
  }
}

resource "aws_iam_role_policy" "read_secrets" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  name   = "read-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.read_secrets[0].json
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = var.tags
}

data "aws_iam_policy_document" "exec" {
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "exec" {
  count = var.enable_execute_command ? 1 : 0

  name   = "ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.exec.json
}

resource "aws_iam_role_policy" "app" {
  count = var.task_role_policy_json != null ? 1 : 0

  name   = "app"
  role   = aws_iam_role.task.id
  policy = var.task_role_policy_json
}

# ---------------------------------------------------------------------------
# Task definition
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # every task gets its own ENI + security group
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = var.image
      essential = true

      portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]

      environment = [for k, v in var.environment : { name = k, value = v }]
      secrets     = [for k, v in var.secrets : { name = k, valueFrom = v }]

      readonlyRootFilesystem = var.readonly_root_filesystem
      linuxParameters        = { initProcessEnabled = true }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "app"
        }
      }
    }
  ])

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Networking: SG-to-SG rules only
# ---------------------------------------------------------------------------
resource "aws_security_group" "task" {
  name_prefix = "${var.name}-task-"
  description = "ECS tasks of ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-task" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.task.id
  description                  = "App port from the ALB only"
  referenced_security_group_id = var.alb_security_group_id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

# Needed to pull images, fetch secrets and ship logs (via NAT / S3 endpoint).
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.task.id
  description       = "HTTPS to AWS APIs (ECR, Secrets Manager, CloudWatch)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "peer" {
  for_each = var.peer_security_groups

  security_group_id            = aws_security_group.task.id
  description                  = "To ${each.key}"
  referenced_security_group_id = each.value.security_group_id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "peer" {
  for_each = var.peer_security_groups

  security_group_id            = each.value.security_group_id
  description                  = "From ${var.name} tasks"
  referenced_security_group_id = aws_security_group.task.id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
}

# ---------------------------------------------------------------------------
# Load balancer wiring
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "this" {
  name_prefix          = substr(replace(var.name, "-", ""), 0, 6)
  vpc_id               = var.vpc_id
  port                 = var.container_port
  protocol             = "HTTP"
  target_type          = "ip" # required for awsvpc / Fargate
  deregistration_delay = var.deregistration_delay

  health_check {
    path                = var.health_check_path
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "this" {
  listener_arn = var.alb_listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = var.listener_path_patterns
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.autoscaling.min_capacity

  enable_execute_command            = var.enable_execute_command
  health_check_grace_period_seconds = var.health_check_grace_period_seconds
  propagate_tags                    = "SERVICE"

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  # A deployment whose tasks keep failing is rolled back automatically.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy

    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.name
    container_port   = var.container_port
  }

  tags = var.tags

  # Application Auto Scaling owns desired_count after creation.
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener_rule.this]
}

# ---------------------------------------------------------------------------
# Autoscaling (Application Auto Scaling, target tracking)
# ---------------------------------------------------------------------------
resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this.name}"
  min_capacity       = var.autoscaling.min_capacity
  max_capacity       = var.autoscaling.max_capacity

  tags = var.tags
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.autoscaling.cpu_target != null ? 1 : 0

  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling.cpu_target
    scale_in_cooldown  = var.autoscaling.scale_in_cooldown
    scale_out_cooldown = var.autoscaling.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "memory" {
  count = var.autoscaling.memory_target != null ? 1 : 0

  name               = "${var.name}-memory"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling.memory_target
    scale_in_cooldown  = var.autoscaling.scale_in_cooldown
    scale_out_cooldown = var.autoscaling.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "requests" {
  count = var.autoscaling.requests_per_target != null ? 1 : 0

  name               = "${var.name}-requests"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling.requests_per_target
    scale_in_cooldown  = var.autoscaling.scale_in_cooldown
    scale_out_cooldown = var.autoscaling.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${var.alb_arn_suffix}/${aws_lb_target_group.this.arn_suffix}"
    }
  }
}
