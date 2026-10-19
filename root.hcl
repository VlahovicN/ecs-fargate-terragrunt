# Root Terragrunt config. Every unit pulls this in with:
#   include "root" { path = find_in_parent_folders("root.hcl") }
#
# It does the two things plain Terraform makes you copy-paste per stack:
#   1. generates backend.tf  (S3 state, one key per unit, derived from its folder path)
#   2. generates provider.tf (region + default tags)

locals {
  # env.hcl lives in live/<env>/ and holds EVERYTHING that differs between dev and prod.
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  project     = local.env_vars.locals.project
  environment = local.env_vars.locals.environment
  aws_region  = local.env_vars.locals.aws_region
  account_id  = get_aws_account_id()

  default_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    # Bucket names are global, so account id + region make it unique per account.
    bucket = "${local.project}-tfstate-${local.account_id}-${local.aws_region}"
    # live/dev/network -> live/dev/network/terraform.tfstate
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.aws_region
    encrypt      = true
    use_lockfile = true # native S3 locking (Terraform >= 1.10), no DynamoDB table needed
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"

      default_tags {
        tags = ${jsonencode(local.default_tags)}
      }
    }
  EOF
}
