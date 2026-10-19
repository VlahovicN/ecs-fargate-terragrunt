# Shared unit definition: identical for dev and prod. All differences come from live/<env>/env.hcl.
locals {
  env  = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  name = "${local.env.project}-${local.env.environment}"
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules/alb"
}

# "dependency" = this unit needs outputs of another unit, so Terragrunt applies network first.
dependency "network" {
  config_path = "../network"

  # Lets `plan` work on a brand new account where network has not been applied yet.
  mock_outputs = {
    vpc_id            = "vpc-00000000"
    vpc_cidr_block    = "10.0.0.0/16"
    public_subnet_ids = ["subnet-aaaaaaaa", "subnet-bbbbbbbb"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name                = local.name
  vpc_id              = dependency.network.outputs.vpc_id
  vpc_cidr            = dependency.network.outputs.vpc_cidr_block
  public_subnet_ids   = dependency.network.outputs.public_subnet_ids
  deletion_protection = local.env.alb.deletion_protection
}
