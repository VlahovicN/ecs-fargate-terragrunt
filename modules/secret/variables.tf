variable "name" {
  description = "Secret name, e.g. tg-demo/dev/web."
  type        = string
}

variable "description" {
  type    = string
  default = "Application secret (value managed out-of-band)."
}

variable "initial_value" {
  description = "Placeholder JSON keys created on first apply. Real values are set outside Terraform."
  type        = map(string)
  default     = { API_KEY = "CHANGE_ME" }
}

variable "kms_key_id" {
  description = "Customer managed KMS key. null = AWS managed key aws/secretsmanager."
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "0 = delete immediately (dev convenience); 7-30 = recoverable (prod)."
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
