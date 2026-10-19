data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /16 -> /24 per subnet. Three tiers, each in its own CIDR range:
  #   public      10.x.0.0/24   ...  (ALB, NAT)
  #   private     10.x.10.0/24  ...  (ECS tasks)
  #   elasticache 10.x.20.0/24  ...  (Redis, no route to the internet at all)
  public_subnets      = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets     = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  elasticache_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 20)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets      = local.public_subnets
  private_subnets     = local.private_subnets
  elasticache_subnets = local.elasticache_subnets

  # One NAT for dev (cheap, single point of failure), one per AZ for prod (HA).
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # The elasticache subnets get their own route table WITHOUT a default route.
  # We create the subnet group ourselves in the redis module.
  create_elasticache_subnet_group       = false
  create_elasticache_subnet_route_table = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = var.tags
}

# Free gateway endpoint: ECR image layers are served from S3, so pulling images
# no longer goes through (and is no longer billed by) the NAT gateway.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = merge(var.tags, { Name = "${var.name}-s3" })
}

data "aws_region" "current" {}
