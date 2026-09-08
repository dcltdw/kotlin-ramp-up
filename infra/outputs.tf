output "instance_id" {
  description = "For `aws ssm start-session --target <id>`."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Changes if the instance is stopped and started. Redeploys keep it."
  value       = aws_instance.app.public_ip
}

output "app_url" {
  description = "The Day 1 acceptance check: this should answer."
  value       = "http://${aws_instance.app.public_ip}:${var.app_port}/api/ping"
}

output "health_url" {
  value = "http://${aws_instance.app.public_ip}:${var.app_port}/actuator/health"
}

output "ecr_repository_url" {
  description = "Push target. scripts/deploy.sh reads this rather than hardcoding an account id."
  value       = aws_ecr_repository.app.repository_url
}

output "image_uri" {
  description = "Exactly what the instance pulls."
  value       = local.image_uri
}

output "aws_region" {
  value = var.aws_region
}

output "project" {
  description = "Read by scripts/teardown.sh to verify nothing is left carrying this Project tag."
  value       = var.project
}
