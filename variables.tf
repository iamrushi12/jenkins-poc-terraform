variable "region" {
  description = "AWS region"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "zscaler_outbound_ip" {
  description = "Zscaler outbound IP CIDR block"
  type        = string
}

variable "budget_email" {
  description = "Email for budget alerts"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
}

variable "monthly_budget_usd" {
  description = "Monthly budget in USD"
  type        = number
}

variable "domain_name" {
  description = "Domain name"
  type        = string
}

variable "route53_zone" {
  description = "Route53 zone ID"
  type        = string
}