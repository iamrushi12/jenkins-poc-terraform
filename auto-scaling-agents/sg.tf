resource "aws_security_group" "agents" {
  name        = "jenkins-agents-sg"
  description = "Security group for Jenkins dynamic EC2 agents"
  vpc_id      = var.vpc_id

  # Agents DO NOT need inbound rules
  # They only initiate outbound connections to Jenkins Master

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins-agents-sg"
  }
}
