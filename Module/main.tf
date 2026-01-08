data "aws_ssm_parameter" "al2_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

locals {
  agent_ami = coalesce(var.ami_id, data.aws_ssm_parameter.al2_ami.value)
}

resource "aws_security_group" "agent" {
  name        = "${var.name}-sg"
  description = "Jenkins agent SG (no inbound; outbound only)"
  vpc_id      = var.vpc_id

  # No inbound rules (agent initiates outbound to controller)
  # Egress: DNS + HTTPS + (optional HTTP for yum)
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # If your AMI needs HTTP for updates/repos, keep this; otherwise remove it.
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-sg"
  })
}

resource "aws_iam_role" "agent" {
  name = "${var.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow the agent to read ONLY its secret from SSM
resource "aws_iam_role_policy" "read_agent_secret" {
  name = "${var.name}-read-agent-secret"
  role = aws_iam_role.agent.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "ReadAgentSecretParam",
        Effect   = "Allow",
        Action   = ["ssm:GetParameter"],
        Resource = "arn:aws:ssm:*:*:parameter${replace(var.ssm_secret_param_name, "/^\\//", "/")}"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "agent" {
  name = "${var.name}-instance-profile"
  role = aws_iam_role.agent.name
}

resource "aws_instance" "agent" {
  ami                    = local.agent_ami
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.agent.id]
  iam_instance_profile   = aws_iam_instance_profile.agent.name

  associate_public_ip_address = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 required
  }

  root_block_device {
    encrypted  = true
    kms_key_id = var.kms_key_id
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    yum update -y

    # Tools
    yum install -y java-17-amazon-corretto-headless curl jq amazon-ssm-agent awscli

    # Optional: Docker for builds
    amazon-linux-extras install docker -y || yum install -y docker
    systemctl enable docker
    systemctl start docker

    # Create agent working dir
    mkdir -p /opt/jenkins-agent
    chown ec2-user:ec2-user /opt/jenkins-agent

    # Download agent.jar from controller (will retry)
    for i in {1..30}; do
      if curl -fsSL "${var.controller_url}/jnlpJars/agent.jar" -o /opt/jenkins-agent/agent.jar; then
        break
      fi
      sleep 10
    done

    # Fetch secret from SSM (must exist)
    SECRET="$(aws ssm get-parameter --name "${var.ssm_secret_param_name}" --with-decryption --query 'Parameter.Value' --output text || true)"

    # Create systemd service (WebSocket over 443)
    cat >/etc/systemd/system/jenkins-agent.service <<'UNIT'
    [Unit]
    Description=Jenkins Inbound Agent (WebSocket)
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=simple
    User=ec2-user
    WorkingDirectory=/opt/jenkins-agent
    Restart=always
    RestartSec=10
    Environment=JENKINS_URL=${var.controller_url}
    Environment=AGENT_NAME=${var.name}
    ExecStart=/usr/bin/java -jar /opt/jenkins-agent/agent.jar -url ${var.controller_url} -secret ${SECRET} -name ${var.name} -workDir /opt/jenkins-agent -webSocket

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable jenkins-agent.service
    systemctl start jenkins-agent.service || true
  EOF

  tags = merge(var.tags, {
    Name = var.name
    Role = "jenkins-agent"
  })
}
