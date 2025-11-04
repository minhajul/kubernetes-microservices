variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "db_password" {
  description = "Database password (store in terraform.tfvars, not in git)"
  type        = string
  sensitive   = true
}

variable "app_key" {
  description = "Laravel APP_KEY (generate with: php artisan key:generate --show)"
  type        = string
  sensitive   = true
}

variable "grafana_api_key" {
  description = "Grafana API key (optional, for programmatic configuration)"
  type        = string
  sensitive   = true
  default     = ""
}