# Shared unit definition: identical for dev and prod. All differences come from live/<env>/env.hcl.
locals {
  env  = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  name = "${local.env.project}-${local.env.environment}"
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules/ecs-cluster"
}

inputs = {
  name               = local.name
  container_insights = local.env.cluster.container_insights
}
