# DEV: cheap and disposable. Compare with ../prod/env.hcl - that diff IS the
# difference between the two environments.
locals {
  project     = "tg-demo"
  environment = "dev"
  aws_region  = "eu-central-1"
  log_level   = "info"

  network = {
    vpc_cidr           = "10.10.0.0/16"
    az_count           = 2
    single_nat_gateway = true # one NAT = cheap, but an AZ outage kills egress
  }

  alb = {
    deletion_protection = false
  }

  cluster = {
    container_insights = false
  }

  secret = {
    recovery_window_in_days = 0 # delete immediately on destroy
  }

  redis = {
    node_type               = "cache.t4g.micro"
    num_cache_clusters      = 1 # primary only: no replica, no failover
    snapshot_retention_days = 0
    apply_immediately       = true
  }

  app = {
    image            = "public.ecr.aws/docker/library/nginx:1.27-alpine"
    container_port   = 80
    cpu              = 256
    memory           = 512
    cpu_architecture = "X86_64"

    # All Spot: ~70% cheaper, tasks can be reclaimed with a 2 min warning. Fine for dev.
    capacity_provider_strategy = [
      { capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 },
    ]

    log_retention_days = 7

    # Fast, loose deployments.
    deployment_minimum_healthy_percent = 50
    deployment_maximum_percent         = 200
    deregistration_delay               = 10

    autoscaling = {
      min_capacity        = 1
      max_capacity        = 3
      cpu_target          = 70
      memory_target       = null
      requests_per_target = null
      scale_in_cooldown   = 120
      scale_out_cooldown  = 60
    }
  }
}
