variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Isolated (no internet route) subnets, one per AZ."
  type        = list(string)
}

variable "node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "num_cache_clusters" {
  description = "Total nodes (1 primary + N-1 replicas)."
  type        = number
  default     = 1
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "parameter_group_family" {
  type    = string
  default = "redis7"
}

variable "port" {
  type    = number
  default = 6379
}

variable "snapshot_retention_days" {
  type    = number
  default = 0
}

variable "apply_immediately" {
  description = "Apply modifications now instead of in the next maintenance window."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
