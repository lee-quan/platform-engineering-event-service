output "service_url" {
  description = "Public URL of the service (dashboard at /)."
  value       = "http://${aws_lb.this.dns_name}"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.this.dns_name
}

output "ecr_repository_url" {
  description = "Push the container image here."
  value       = aws_ecr_repository.this.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  value = aws_ecs_service.this.name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.this.name
}
