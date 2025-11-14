region              = "us-east-1"
instance_type       = "t2.micro"
zscaler_outbound_ip = "0.0.0.0/0"
budget_email        = "rushiyadav121200@email.com"

vpc_cidr        = "10.0.0.0/16"
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

root_volume_size = 16
monthly_budget_usd = 500

domain_name = ""
route53_zone = ""
