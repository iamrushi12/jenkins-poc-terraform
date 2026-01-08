############################################
# AUTO SCALING GROUP FOR DYNAMIC AGENTS
############################################

resource "aws_autoscaling_group" "jenkins_agents" {
  name                = "jenkins-agents-asg"
  max_size            = var.max_agents
  min_size            = var.min_agents
  desired_capacity    = var.desired_agents
  vpc_zone_identifier = var.private_subnets
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.jenkins_agents.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "jenkins-agent"
    propagate_at_launch = true
  }
}
