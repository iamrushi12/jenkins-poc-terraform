module "jenkins_agent_1" {
  source = "./modules/jenkins_agent"

  name                  = "agent-1"
  vpc_id                = aws_vpc.jenkins.id
  subnet_id             = aws_subnet.private[0].id
  controller_url         = "https://jenkins-poc.mercuryfinancialcloudpoc.com"
  ssm_secret_param_name = "/jenkins/agents/agent-1/secret"

  instance_type = "t3.medium"
  kms_key_id    = aws_kms_key.jenkins.arn

  tags = {
    Environment = "poc"
    App         = "jenkins"
  }
}

# IMPORTANT:
# Your ALB SG is locked to corporate IP.
# Agents in VPC will be blocked unless you allow ALB:443 from agent SG.
resource "aws_security_group_rule" "alb_https_from_agent" {
  type                     = "ingress"
  security_group_id        = aws_security_group.alb.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = module.jenkins_agent_1.agent_sg_id
  description              = "Allow Jenkins agent to reach controller via ALB over HTTPS"
}
