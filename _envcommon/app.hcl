# Shared unit definition: identical for dev and prod. All differences come from live/<env>/env.hcl.
locals {
  env  = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  name = "${local.env.project}-${local.env.environment}"
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules/ecs-service"
}

dependency "network" {
  config_path = "../network"

  mock_outputs = {
    vpc_id             = "vpc-00000000"
    private_subnet_ids = ["subnet-eeeeeeee", "subnet-ffffffff"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "cluster" {
  config_path = "../ecs-cluster"

  mock_outputs = {
    arn  = "arn:aws:ecs:eu-central-1:111111111111:cluster/mock"
    name = "mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "alb" {
  config_path = "../alb"

  mock_outputs = {
    listener_arn      = "arn:aws:elasticloadbalancing:eu-central-1:111111111111:listener/app/mock/0000000000000000/0000000000000000"
    security_group_id = "sg-00000000"
    arn_suffix        = "app/mock/0000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "redis" {
  config_path = "../redis"

  mock_outputs = {
    primary_endpoint_address = "mock.xxxxxx.ng.0001.euc1.cache.amazonaws.com"
    port                     = 6379
    security_group_id        = "sg-11111111"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "secret" {
  config_path = "../secret"

  mock_outputs = {
    arn = "arn:aws:secretsmanager:eu-central-1:111111111111:secret:mock-AbCdEf"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name         = "${local.name}-web"
  cluster_arn  = dependency.cluster.outputs.arn
  cluster_name = dependency.cluster.outputs.name
  vpc_id       = dependency.network.outputs.vpc_id
  subnet_ids   = dependency.network.outputs.private_subnet_ids

  image            = local.env.app.image
  container_port   = local.env.app.container_port
  cpu              = local.env.app.cpu
  memory           = local.env.app.memory
  cpu_architecture = local.env.app.cpu_architecture

  # How the app finds Redis. The endpoint is a DNS name that resolves to private IPs inside the VPC.
  environment = {
    APP_ENV    = local.env.environment
    REDIS_HOST = dependency.redis.outputs.primary_endpoint_address
    REDIS_PORT = tostring(dependency.redis.outputs.port)
    REDIS_TLS  = "true" # in-transit encryption is on: use rediss://
    LOG_LEVEL  = local.env.log_level
  }

  # The ONE secret. ECS resolves "<arn>:API_KEY::" to the value of the JSON key API_KEY and
  # exposes it as the env var API_KEY. The value never appears in the task definition or in state.
  secrets     = { API_KEY = "${dependency.secret.outputs.arn}:API_KEY::" }
  secret_arns = [dependency.secret.outputs.arn]

  alb_listener_arn      = dependency.alb.outputs.listener_arn
  alb_security_group_id = dependency.alb.outputs.security_group_id
  alb_arn_suffix        = dependency.alb.outputs.arn_suffix

  # Network path to Redis: egress on the task SG + ingress on the Redis SG, both SG-to-SG.
  peer_security_groups = {
    redis = {
      security_group_id = dependency.redis.outputs.security_group_id
      port              = dependency.redis.outputs.port
    }
  }

  capacity_provider_strategy         = local.env.app.capacity_provider_strategy
  deployment_minimum_healthy_percent = local.env.app.deployment_minimum_healthy_percent
  deployment_maximum_percent         = local.env.app.deployment_maximum_percent
  deregistration_delay               = local.env.app.deregistration_delay
  log_retention_days                 = local.env.app.log_retention_days
  autoscaling                        = local.env.app.autoscaling
}
