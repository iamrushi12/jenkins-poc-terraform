#VPC and Subnets
resource "aws_vpc" "jenkins" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "jenkins-vpc" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.jenkins.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = { Name = "public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.jenkins.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[1]
  tags = { Name = "public-b" }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.jenkins.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = { Name = "private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.jenkins.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = { Name = "private-b" }
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.jenkins.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "gw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.jenkins.id
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.jenkins.id
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.gw.id
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

#KMS Key
resource "aws_kms_key" "jenkins" {
  description             = "CMK for Jenkins root volume"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

#IAM Role and Instance Profile
resource "aws_iam_role" "jenkins" {
  name = "jenkins-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "jenkins-instance-profile"
  role = aws_iam_role.jenkins.name
}

#Security Groups
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "ALB restricted to corporate IP"
  vpc_id      = aws_vpc.jenkins.id

  ingress {
    description = "Allow HTTP from Zscaler"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.zscaler_outbound_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "jenkins" {
  name        = "jenkins-sg"
  description = "Jenkins traffic via ALB only"
  vpc_id      = aws_vpc.jenkins.id

  ingress {
    description      = "Allow from ALB"
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    security_groups  = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#ALB target and Load Balancer
resource "aws_lb" "jenkins" {
  name               = "poc-jenkins-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

resource "aws_lb_target_group" "jenkins" {
  name     = "jenkins-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.jenkins.id
  health_check {
    path = "/login"
  }
}

resource "aws_lb_listener" "jenkins" {
  load_balancer_arn = aws_lb.jenkins.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
}

#EC2 Instance
data "aws_ssm_parameter" "linux2" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ssm_parameter.linux2.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_a.id
  iam_instance_profile   = aws_iam_instance_profile.jenkins.name
  vpc_security_group_ids = [aws_security_group.jenkins.id]

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = aws_kms_key.jenkins.id
  }

  user_data = <<-EOF
    #!/bin/bash -xe
    yum -y update
    amazon-linux-extras install docker -y
    systemctl enable docker && systemctl start docker
    systemctl enable amazon-ssm-agent && systemctl start amazon-ssm-agent
    usermod -aG docker ec2-user
    mkdir -p /var/jenkins_home && chown 1000:1000 /var/jenkins_home
    docker run -d --name jenkins -p 8080:8080 -v /var/jenkins_home:/var/jenkins_home jenkins/jenkins:lts
  EOF

  tags = {
    Name = "jenkins-ec2-instance"
  }
}

#Budget Alarm
resource "aws_budgets_budget" "jenkins" {
  name         = "jenkins-poc-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = 500
  limit_unit   = "USD"

  notification {
    comparison_operator = "GREATER_THAN"
    threshold            = 500
    threshold_type       = "ABSOLUTE_VALUE"
    notification_type    = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator = "GREATER_THAN"
    threshold            = 1000
    threshold_type       = "ABSOLUTE_VALUE"
    notification_type    = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}

