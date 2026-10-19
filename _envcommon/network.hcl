# Shared unit definition: identical for dev and prod. All differences come from live/<env>/env.hcl.
locals {
  env  = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  name = "${local.env.project}-${local.env.environment}"
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules/network"
}

inputs = {
  name               = local.name
  vpc_cidr           = local.env.network.vpc_cidr
  az_count           = local.env.network.az_count
  single_nat_gateway = local.env.network.single_nat_gateway
}
