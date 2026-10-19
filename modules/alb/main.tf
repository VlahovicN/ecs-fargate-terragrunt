resource "aws_security_group" "this" {
  name_prefix = "${var.name}-alb-"
  description = "ALB ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.this.id
  description       = "HTTP from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# The ALB may only talk to things inside the VPC (the ECS tasks). Each service
# opens its own task SG to this ALB SG, see modules/ecs-service.
resource "aws_vpc_security_group_egress_rule" "to_vpc" {
  security_group_id = aws_security_group.this.id
  description       = "To targets inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
}

resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.this.id]
  subnets            = var.public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
  idle_timeout               = var.idle_timeout

  tags = var.tags
}

# Main listener. Default action is a 404: traffic only reaches a service through
# an explicit listener rule that the service module adds (path/host based).
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "no route"
      status_code  = "404"
    }
  }

  tags = var.tags
}
