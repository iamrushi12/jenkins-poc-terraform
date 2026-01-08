variable "name" {
  description = "Agent name in Jenkins (must match the node name you create in Jenkins)"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  description = "Private subnet ID for the agent"
  type        = string
}

variable "controller_url" {
  description = "Jenkins controller URL (https://jenkins-poc....)"
  type        = string
}

variable "ssm_secret_param_name" {
  description = "SSM SecureString parameter name storing the Jenkins agent secret"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "kms_key_id" {
  description = "KMS key ID/ARN for EBS encryption (optional). If null, EBS default encryption is used."
  type        = string
  default     = null
}

variable "ami_id" {
  description = "AMI ID for agent. If null, uses latest Amazon Linux 2 via SSM public parameter."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
