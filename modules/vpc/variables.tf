variable "name" {
  type        = string
  description = "Name prefix for all resources"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block of the VPC, e.g. 10.10.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones to spread subnets across"
}

variable "single_nat_gateway" {
  type        = bool
  default     = true
  description = "true = one shared NAT gateway (cheap, dev). false = one per AZ (highly available, prod)"
}
