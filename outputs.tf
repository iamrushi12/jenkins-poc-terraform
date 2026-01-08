output "alb_dns" {
  description = "ALB DNS name"
  value       = aws_lb.jenkins.dns_name
}

output "jenkins_url" {
  description = "URL to access Jenkins"
  value       = "http://${aws_lb.jenkins.dns_name}"
}

output "vpc_id" {
  value       = aws_vpc.jenkins.id
  description = "VPC ID"
}
