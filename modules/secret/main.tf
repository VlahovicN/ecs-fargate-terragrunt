resource "aws_secretsmanager_secret" "this" {
  name                    = var.name
  description             = var.description
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = var.tags
}

# Seed value so the very first deploy can start the task. The REAL value is set
# out-of-band (console / CLI / rotation Lambda) and Terraform never overwrites
# it thanks to ignore_changes, so it also never lands in a PR diff.
resource "aws_secretsmanager_secret_version" "initial" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = jsonencode(var.initial_value)

  lifecycle {
    ignore_changes = [secret_string]
  }
}
