variable "name" {
  description = "Name prefix for the VPC and its resources."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR. Must be a /16 (subnets are carved out as /24)."
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "Use 2 or 3 AZs."
  }
}

variable "single_nat_gateway" {
  description = "true = one shared NAT gateway (cheap, not HA). false = one NAT per AZ."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
