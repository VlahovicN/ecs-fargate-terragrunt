resource "aws_security_group" "this" {
  name_prefix = "${var.name}-redis-"
  description = "ElastiCache ${var.name}. Ingress rules are added by the clients (see ecs-service peer_security_groups)."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-redis" })

  lifecycle {
    create_before_destroy = true
  }
}

# Deliberately NO ingress rules here and no egress rules (Redis never initiates
# connections). Access is granted per client SG by the consumer, never by CIDR.

resource "aws_elasticache_subnet_group" "this" {
  name        = var.name
  description = "Isolated subnets for ${var.name}"
  subnet_ids  = var.subnet_ids

  tags = var.tags
}

resource "aws_elasticache_parameter_group" "this" {
  name   = var.name
  family = var.parameter_group_family

  tags = var.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.name
  description          = "Redis for ${var.name}"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = var.port

  # 1 = primary only (dev). >=2 = primary + replicas spread over AZs (prod).
  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = var.num_cache_clusters > 1
  multi_az_enabled           = var.num_cache_clusters > 1

  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.this.id]
  parameter_group_name = aws_elasticache_parameter_group.this.name

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true # clients MUST use TLS (rediss://)

  snapshot_retention_limit   = var.snapshot_retention_days
  snapshot_window            = "02:00-03:00"
  maintenance_window         = "sun:03:30-sun:04:30"
  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  tags = var.tags

  lifecycle {
    precondition {
      condition     = length(var.subnet_ids) >= min(var.num_cache_clusters, 2)
      error_message = "Provide subnets in at least 2 AZs when running replicas."
    }
  }
}
