output "primary_endpoint_address" {
  description = "Write endpoint. Follows the primary after a failover."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint_address" {
  value = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  value = var.port
}

output "security_group_id" {
  value = aws_security_group.this.id
}
