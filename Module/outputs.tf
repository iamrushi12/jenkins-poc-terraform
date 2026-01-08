output "agent_instance_id" {
  value = aws_instance.agent.id
}

output "agent_sg_id" {
  value = aws_security_group.agent.id
}
