########################################
# DATA
########################################

data "aws_availability_zones" "this" {
  state = "available"
}

########################################
# NETWORKING – VPC, SUBNETS, IGW, NAT
########################################

resource "aws_vpc" "jenkins" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "jenkins-vpc" }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.jenkins.id
  cidr_block              = var.public_subnets[count.index]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.this.names[count.index]

  tags = { Name = "jenkins-public-${count.index + 1}" }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.jenkins.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = data.aws_availability_zones.this.names[count.index]

  tags = { Name = "jenkins-private-${count.index + 1}" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.jenkins.id
  tags   = { Name = "jenkins-igw" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "jenkins-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  subnet_id     = aws_subnet.public[0].id
  allocation_id = aws_eip.nat.id
  tags          = { Name = "jenkins-nat" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.jenkins.id
  tags   = { Name = "jenkins-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.jenkins.id
  tags   = { Name = "jenkins-private-rt" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

########################################
# SECURITY GROUPS
########################################

# ALB SG – allow HTTP only from corporate/Zscaler IP
resource "aws_security_group" "alb" {
  name        = "jenkins-alb-sg"
  description = "ALB restricted to corp IP"
  vpc_id      = aws_vpc.jenkins.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.zscaler_outbound_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jenkins-alb-sg" }
}
module "jenkins_agents" {
  source = "./auto-scaling-agents"

  vpc_id          = aws_vpc.jenkins.id
  private_subnets = aws_subnet.private[*].id
  master_sg_id    = aws_security_group.jenkins_tasks.id
  agent_ami       = data.aws_ami.amazon_linux_2.id
}

# Jenkins tasks SG – allow 8080 from ALB, NFS to/from EFS
resource "aws_security_group" "jenkins_tasks" {
  name        = "jenkins-fargate-sg"
  description = "Jenkins Fargate task SG"
  vpc_id      = aws_vpc.jenkins.id

  #Allow agents to connect to master on JNLP port 50000
  ingress {
    from_port       = 50000
    to_port         = 50000
    protocol        = "tcp"
    security_groups = [module.jenkins_agents.agents_sg_id]
  }
  # ALB -> Jenkins on 8080
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # NFS from tasks to EFS
  egress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # generic outbound (for updates, plugins, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jenkins-tasks-sg" }
}

# EFS SG – allow NFS from Jenkins tasks
resource "aws_security_group" "efs" {
  name        = "jenkins-efs-sg"
  description = "EFS SG for Jenkins home"
  vpc_id      = aws_vpc.jenkins.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jenkins-efs-sg" }
}

########################################
# EFS – PERSISTENT JENKINS HOME
########################################

resource "aws_efs_file_system" "jenkins" {
  creation_token = "jenkins-efs"
  encrypted      = true

  tags = { Name = "jenkins-efs" }
}

resource "aws_efs_mount_target" "jenkins_mt_a" {
  file_system_id  = aws_efs_file_system.jenkins.id
  subnet_id       = aws_subnet.private[0].id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "jenkins_mt_b" {
  file_system_id  = aws_efs_file_system.jenkins.id
  subnet_id       = aws_subnet.private[1].id
  security_groups = [aws_security_group.efs.id]
}

########################################
# ECS CLUSTER + LOG GROUP
########################################

resource "aws_ecs_cluster" "jenkins" {
  name = "jenkins-poc-cluster"
}

resource "aws_cloudwatch_log_group" "jenkins" {
  name              = "/ecs/jenkins"
  retention_in_days = 30
}

########################################
# IAM ROLES FOR ECS
########################################

# Execution role: pull image, write logs, etc.
resource "aws_iam_role" "jenkins_task_execution" {
  name = "jenkins-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# ECS default execution policy (logs, task startup, secrets)
resource "aws_iam_role_policy_attachment" "jenkins_task_execution_policy" {
  role       = aws_iam_role.jenkins_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# REQUIRED to pull custom images from ECR
resource "aws_iam_role_policy_attachment" "jenkins_task_ecr_read" {
  role       = aws_iam_role.jenkins_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Task role: for Jenkins itself (hook to S3/SSM/etc later if needed)
resource "aws_iam_role" "jenkins_task" {
  name = "jenkins-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

########################################
# ECS TASK DEFINITION – JENKINS
########################################

resource "aws_ecs_task_definition" "jenkins" {
  family                   = "jenkins-poc-fargate"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory

  execution_role_arn = aws_iam_role.jenkins_task_execution.arn
  task_role_arn      = aws_iam_role.jenkins_task.arn

  volume {
    name = "jenkins-home"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.jenkins.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.jenkins.id
        iam             = "DISABLED"
      }
    }

  }

  container_definitions = jsonencode([
    {
      name      = "jenkins"
      image     = var.custom_jenkins_image
      essential = true

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "JENKINS_OPTS"
          value = "--httpListenAddress=0.0.0.0"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "jenkins-home"
          containerPath = "/var/jenkins_home"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.jenkins.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "jenkins"
        }
      }
    }
  ])
}

########################################
# ALB + TARGET GROUP + LISTENER
########################################

resource "aws_lb" "jenkins" {
  name               = "poc-jenkins-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]

  tags = { Name = "poc-jenkins-alb" }
}

# Target group for Fargate tasks – target_type=ip
resource "aws_lb_target_group" "jenkins" {
  name        = "jenkins-ecs-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.jenkins.id

  health_check {
    path    = "/login"
    matcher = "200-399"
  }

  tags = { Name = "jenkins-ecs-tg" }
}

resource "aws_efs_access_point" "jenkins" {
  file_system_id = aws_efs_file_system.jenkins.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/jenkins"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
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

########################################
# ECS SERVICE – JENKINS ON FARGATE
########################################

resource "aws_ecs_service" "jenkins" {
  name            = "jenkins-poc-service"
  cluster         = aws_ecs_cluster.jenkins.id
  task_definition = aws_ecs_task_definition.jenkins.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.jenkins_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.jenkins.arn
    container_name   = "jenkins"
    container_port   = 8080
  }

  depends_on = [
    aws_lb_listener.jenkins,
    aws_efs_mount_target.jenkins_mt_a,
    aws_efs_mount_target.jenkins_mt_b
  ]
}

########################################
# BUDGET
########################################

resource "aws_budgets_budget" "jenkins" {
  name         = "jenkins-poc-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 500
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 1000
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}



