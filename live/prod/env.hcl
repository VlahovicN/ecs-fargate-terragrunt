# PROD: highly available, over-provisioned on purpose, careful deployments.
# Compare with ../dev/env.hcl - that diff IS the difference between the two environments.
locals {
  project     = "tg-demo"
  environment = "prod"
  aws_region  = "eu-central-1"
  log_level   = "error"

  network = {
    vpc_cidr           = "10.20.0.0/16"
    az_count           = 3
    single_nat_gateway = false # one NAT per AZ: losing an AZ does not break egress elsewhere
  }

  alb = {
    deletion_protection = true
  }

  cluster = {
    container_insights = true
  }

  secret = {
    recovery_window_in_days = 30
  }

  redis = {
    node_type               = "cache.r7g.large"
    num_cache_clusters      = 3 # 1 primary + 2 replicas, one per AZ, automatic failover + Multi-AZ
    snapshot_retention_days = 7
    apply_immediately       = false # changes wait for the maintenance window
  }

  app = {
    image            = "public.ecr.aws/docker/library/nginx:1.27-alpine" # prod: pin a digest / immutable tag
    container_port   = 80
    cpu              = 512
    memory           = 1024
    cpu_architecture = "X86_64"

    # The first 3 tasks (one per AZ) are always on-demand; everything above that is
    # 75% Spot / 25% on-demand. A Spot reclaim during a spike never takes the baseline away.
    capacity_provider_strategy = [
      { capacity_provider = "FARGATE", weight = 1, base = 3 },
      { capacity_provider = "FARGATE_SPOT", weight = 3, base = 0 },
    ]

    log_retention_days = 90

    # Never drop below 100% healthy during a deploy: roll new tasks first, then retire old ones.
    deployment_minimum_healthy_percent = 100
    deployment_maximum_percent         = 200
    deregistration_delay               = 30

    autoscaling = {
      min_capacity        = 3 # one task per AZ
      max_capacity        = 30
      cpu_target          = 55 # lower than dev: leave headroom, Fargate takes ~1-2 min to add capacity
      memory_target       = 75
      requests_per_target = 500
      scale_in_cooldown   = 600 # scale in slowly
      scale_out_cooldown  = 30  # scale out fast
    }
  }
}
