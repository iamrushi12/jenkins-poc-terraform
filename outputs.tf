output "jenkins_url" {
  value       = "http://${aws_lb.jenkins.dns_name}"
  description = "Jenkins ALB URL"
}

output "alb_dns" {
  value = aws_lb.jenkins.dns_name
}

output "jenkins_instance_id" {
  value = aws_instance.jenkins.id
}

output "vpc_id" {
  value = aws_vpc.jenkins.id
}
