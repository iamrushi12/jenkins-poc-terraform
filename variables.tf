variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Public subnet CIDRs (for ALB + NAT)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "Private subnet CIDRs (for Fargate tasks)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "zscaler_outbound_cidr" {
  description = "Corporate/Zscaler egress IP CIDR allowed to hit ALB"
  type        = string
}

variable "ecs_cpu" {
  description = "CPU units for Fargate task"
  type        = string
  default     = "1024" # 1 vCPU
}

variable "ecs_memory" {
  description = "Memory (MB) for Fargate task"
  type        = string
  default     = "2048"
}

variable "desired_count" {
  description = "Number of Jenkins tasks"
  type        = number
  default     = 1
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget for this stack"
  type        = number
  default     = 500
}

variable "budget_email" {
  description = "E-mail address to receive budget alerts"
  type        = string
}

variable "custom_jenkins_image" {
  type        = string
  description = "Custom Jenkins Docker image from ECR"
}

# variable "agent_ami" {
#   description = "AMI ID for Jenkins agents"
#   type        = string
# }
