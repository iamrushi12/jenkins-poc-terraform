region                = "us-east-1"
zscaler_outbound_cidr = "0.0.0.0/0" # replace with your corp egress IP
monthly_budget_usd    = 500
budget_email          = "rushiyadav121200@gmail.com"

# optionally override VPC/subnet CIDRs if you don’t like defaults
# vpc_cidr        = "10.1.0.0/16"
# public_subnets  = ["10.1.1.0/24", "10.1.2.0/24"]
# private_subnets = ["10.1.11.0/24", "10.1.12.0/24"]

custom_jenkins_image = "322284514643.dkr.ecr.us-east-1.amazonaws.com/custom-jenkins:latest"
