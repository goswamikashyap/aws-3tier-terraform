variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private app subnets"
}

variable "alb_sg_id" {
  type        = string
  description = "Only this security group may reach the instances on port 80"
}

variable "target_group_arn" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "desired_capacity" {
  type = number
}

variable "cpu_target" {
  type        = number
  default     = 50
  description = "Average CPU % the ASG tries to maintain by scaling out/in"
}
