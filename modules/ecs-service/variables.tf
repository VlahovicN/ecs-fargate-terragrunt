# ---------- identity / placement ----------
variable "name" {
  description = "Service name, used as prefix for every resource."
  type        = string
}

variable "cluster_arn" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for the tasks (one per AZ)."
  type        = list(string)
}

# ---------- container ----------
variable "image" {
  type = string
}

variable "container_port" {
  type    = number
  default = 80
}

variable "cpu" {
  description = "Task CPU units (256/512/1024/2048/4096...)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MiB (must be a valid Fargate combination with cpu)."
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64 (the image must match)."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "environment" {
  description = "Plain environment variables."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "ENV_NAME => Secrets Manager valueFrom (arn, or arn:JSON_KEY::). Injected by ECS at task start."
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "Secret ARNs the task execution role may read (least privilege). Keep in sync with `secrets`."
  type        = list(string)
  default     = []
}

variable "task_role_policy_json" {
  description = "Optional IAM policy JSON for what the APPLICATION itself calls (S3, SQS, ...)."
  type        = string
  default     = null
}

variable "readonly_root_filesystem" {
  type    = bool
  default = false
}

variable "enable_execute_command" {
  description = "ECS Exec (shell into a running task via SSM). Handy to test Redis reachability."
  type        = bool
  default     = true
}

# ---------- networking / load balancer ----------
variable "alb_listener_arn" {
  type = string
}

variable "alb_security_group_id" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "listener_rule_priority" {
  type    = number
  default = 100
}

variable "listener_path_patterns" {
  type    = list(string)
  default = ["/*"]
}

variable "health_check_path" {
  type    = string
  default = "/"
}

variable "deregistration_delay" {
  description = "Seconds the ALB keeps draining a target. Lower = faster deploys."
  type        = number
  default     = 30
}

variable "peer_security_groups" {
  description = <<-EOT
    Other things the tasks must reach on a TCP port (e.g. Redis). For each entry the module
    adds an egress rule on the task SG AND an ingress rule on the peer SG, both SG-to-SG.
    The map key must be static (e.g. "redis"); the values may come from other units.
  EOT
  type = map(object({
    security_group_id = string
    port              = number
  }))
  default = {}
}

# ---------- deployment / capacity ----------
variable "capacity_provider_strategy" {
  description = "How tasks are split between FARGATE and FARGATE_SPOT."
  type = list(object({
    capacity_provider = string
    weight            = number
    base              = optional(number, 0)
  }))
  default = [{ capacity_provider = "FARGATE", weight = 1 }]
}

variable "deployment_minimum_healthy_percent" {
  type    = number
  default = 100
}

variable "deployment_maximum_percent" {
  type    = number
  default = 200
}

variable "health_check_grace_period_seconds" {
  type    = number
  default = 30
}

variable "log_retention_days" {
  type    = number
  default = 14
}

# ---------- autoscaling ----------
variable "autoscaling" {
  description = <<-EOT
    Target tracking autoscaling. Every non-null *_target adds one policy; the service scales OUT when
    ANY policy wants more tasks and scales IN only when ALL of them agree.
  EOT
  type = object({
    min_capacity        = number
    max_capacity        = number
    cpu_target          = optional(number)
    memory_target       = optional(number)
    requests_per_target = optional(number)
    scale_in_cooldown   = optional(number, 300)
    scale_out_cooldown  = optional(number, 60)
  })

  validation {
    condition     = var.autoscaling.min_capacity <= var.autoscaling.max_capacity
    error_message = "autoscaling.min_capacity must be <= max_capacity."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
