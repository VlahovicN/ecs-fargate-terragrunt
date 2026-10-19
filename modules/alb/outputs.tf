output "arn" {
  value = aws_lb.this.arn
}

output "arn_suffix" {
  description = "Needed for the ALBRequestCountPerTarget autoscaling metric."
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  value = aws_lb.this.dns_name
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "listener_arn" {
  description = "Listener that services attach their rules to."
  value       = aws_lb_listener.main.arn
}
