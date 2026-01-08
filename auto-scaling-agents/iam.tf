############################################
# IAM ROLE + INSTANCE PROFILE FOR AGENTS
############################################

resource "aws_iam_role" "jenkins_agent_role" {
  name = "jenkins-ec2-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "agent_ec2_read" {
  role       = aws_iam_role.jenkins_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "agent_ssm" {
  role       = aws_iam_role.jenkins_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "agent_cw" {
  role       = aws_iam_role.jenkins_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "agent_profile" {
  name = "jenkins-ec2-agent-instance-profile"
  role = aws_iam_role.jenkins_agent_role.name
}
