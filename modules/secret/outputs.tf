output "arn" {
  value = aws_secretsmanager_secret.this.arn
}

output "name" {
  value = aws_secretsmanager_secret.this.name
}
