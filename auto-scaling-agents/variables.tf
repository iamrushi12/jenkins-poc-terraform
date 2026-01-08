variable "vpc_id" {
  description = "VPC where agents run"
  type        = string
}

variable "private_subnets" {
  description = "Private subnet IDs for agents"
  type        = list(string)
}

variable "master_sg_id" {
  description = "Security group of Jenkins controller (ECS tasks SG)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for agents"
  type        = string
  default     = "t3.medium"
}

variable "max_agents" {
  description = "Maximum number of Jenkins agents"
  type        = number
  default     = 5
}

variable "min_agents" {
  description = "Minimum number of Jenkins agents"
  type        = number
  default     = 0
}

variable "desired_agents" {
  description = "Initial desired number of agents"
  type        = number
  default     = 0
}

variable "agent_ami" {
  description = "AMI ID for Jenkins agents"
  type        = string
}