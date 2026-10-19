# Shared unit definition: identical for dev and prod. All differences come from live/<env>/env.hcl.
locals {
  env  = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  name = "${local.env.project}-${local.env.environment}"
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules/redis"
}

dependency "network" {
  config_path = "../network"

  mock_outputs = {
    vpc_id                 = "vpc-00000000"
    elasticache_subnet_ids = ["subnet-cccccccc", "subnet-dddddddd"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name                    = local.name
  vpc_id                  = dependency.network.outputs.vpc_id
  subnet_ids              = dependency.network.outputs.elasticache_subnet_ids
  node_type               = local.env.redis.node_type
  num_cache_clusters      = local.env.redis.num_cache_clusters
  snapshot_retention_days = local.env.redis.snapshot_retention_days
  apply_immediately       = local.env.redis.apply_immediately
}
