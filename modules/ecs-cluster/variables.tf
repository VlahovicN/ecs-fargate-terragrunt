variable "name" {
  type = string
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights (extra cost, per-task metrics)."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
