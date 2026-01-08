############################################
# LAUNCH TEMPLATE FOR AGENT INSTANCES
############################################

# Use latest Amazon Linux 2
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_launch_template" "jenkins_agents" {
  name_prefix   = "jenkins-agent-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.agent_profile.name
  }

  network_interfaces {
    security_groups = [aws_security_group.agents.id]
  }

  # User data: install Docker, Java, SSM; prep for Jenkins agent
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -eux

    yum update -y

    # Docker
    amazon-linux-extras install docker -y
    systemctl enable docker
    systemctl start docker

    # Java for JNLP agent
    yum install -y java-1.8.0-openjdk

    # SSM agent (usually preinstalled, but ensure)
    systemctl enable amazon-ssm-agent || true
    systemctl start amazon-ssm-agent || true

    # Allow ec2-user to use docker
    usermod -aG docker ec2-user
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "jenkins-agent"
    }
  }
}
