variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  description = "Used to restrict ALB egress to the VPC."
  type        = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "idle_timeout" {
  type    = number
  default = 60
}

variable "tags" {
  type    = map(string)
  default = {}
}
