output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "db_endpoint" {
  description = "The endpoint of the RDS database"
  value       = aws_db_instance.db.address
}

output "db_password_secret_arn" {
  description = "The ARN of the Secrets Manager secret for the DB password"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "cache_endpoint" {
  description = "The endpoint of the ElastiCache Redis cluster"
  value       = aws_elasticache_cluster.cache.cache_nodes[0].address
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.app.repository_url
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket for uploads"
  value       = aws_s3_bucket.uploads.id
}

output "grafana_workspace_endpoint" {
  description = "The URL for the Managed Grafana workspace"
  value       = aws_grafana_workspace.main.endpoint
}