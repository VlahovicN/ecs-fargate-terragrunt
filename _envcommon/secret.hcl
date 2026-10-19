# Shared unit definition: identical for dev and prod. All differences come from live/<env>/env.hcl.
locals {
  env  = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  name = "${local.env.project}-${local.env.environment}"
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules/secret"
}

inputs = {
  # The name the app's secret has in Secrets Manager: tg-demo-dev/web
  name                    = "${local.name}/web"
  recovery_window_in_days = local.env.secret.recovery_window_in_days
}
