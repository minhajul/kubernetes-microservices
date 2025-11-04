terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = var.region
}

# This provides a map of all resources with a consistent name
locals {
  project_name = var.project_name
  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# Get all Availability Zones in the region for high availability
data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------
# --- SECTION 2: NETWORKING (VPC)
# -----------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.3"

  name = local.project_name
  cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.available.names
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true

  tags = local.tags
}

# Security Group for the Application Load Balancer (ALB)
resource "aws_security_group" "alb" {
  name        = "${local.project_name}-alb-sg"
  description = "Allow HTTP/S traffic from the internet"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
}

# Security Group for the Laravel App (Fargate)
resource "aws_security_group" "app" {
  name        = "${local.project_name}-app-sg"
  description = "Allow traffic from ALB and to DB/Cache"
  vpc_id      = module.vpc.vpc_id

  # Allow traffic from the ALB on Nginx port
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
}

# Security Group for the RDS Database
resource "aws_security_group" "db" {
  name        = "${local.project_name}-db-sg"
  description = "Allow traffic from the App"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  tags = local.tags
}

# Security Group for the ElastiCache (Redis)
resource "aws_security_group" "cache" {
  name        = "${local.project_name}-cache-sg"
  description = "Allow traffic from the App"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  tags = local.tags
}

# Used to make the bucket name unique
resource "random_id" "bucket" {
  byte_length = 8
}

# S3 bucket for Laravel file uploads
resource "aws_s3_bucket" "uploads" {
  bucket = "${local.project_name}-uploads-${random_id.bucket.hex}"
  tags   = local.tags
}

# Block all public access to the bucket
resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ECR Repository for app image
resource "aws_ecr_repository" "app" {
  name = "${local.project_name}-app"
  tags = local.tags
}

# ECR Repository for nginx image
resource "aws_ecr_repository" "nginx" {
  name = "${local.project_name}-nginx"
  tags = local.tags
}

# Subnet group for RDS
resource "aws_db_subnet_group" "db" {
  name       = "${local.project_name}-db"
  subnet_ids = module.vpc.private_subnets
  tags       = local.tags
}

# Store the DB password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name = "${local.project_name}-db-password-${random_id.bucket.hex}"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({ password = var.db_password })
}

# Store APP_KEY in Secrets Manager
resource "aws_secretsmanager_secret" "app_key" {
  name = "${local.project_name}-app-key-${random_id.bucket.hex}"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "app_key" {
  secret_id     = aws_secretsmanager_secret.app_key.id
  secret_string = jsonencode({ key = var.app_key })
}

# The RDS Database Instance
resource "aws_db_instance" "db" {
  identifier             = "${local.project_name}-db"
  engine                 = "postgres"
  engine_version         = "15.3"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "laravel"
  username               = "laravel_admin"
  password               = jsondecode(aws_secretsmanager_secret_version.db_password.secret_string).password
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]

  skip_final_snapshot = true
  multi_az            = false

  tags = local.tags
}

# Subnet group for ElastiCache
resource "aws_elasticache_subnet_group" "cache" {
  name       = "${local.project_name}-cache"
  subnet_ids = module.vpc.private_subnets
  tags       = local.tags
}

# The ElastiCache (Redis) Cluster
resource "aws_elasticache_cluster" "cache" {
  cluster_id         = "${local.project_name}-cache"
  engine             = "redis"
  node_type          = "cache.t3.micro"
  num_cache_nodes    = 1
  subnet_group_name  = aws_elasticache_subnet_group.cache.name
  security_group_ids = [aws_security_group.cache.id]

  tags = local.tags
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${local.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  tags = local.tags
}

resource "aws_lb_target_group" "app" {
  name        = "${local.project_name}-app"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = local.tags
}

# HTTP listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.project_name}-cluster"
  tags = local.tags
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.project_name}-app"
  retention_in_days = 7
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/ecs/${local.project_name}-nginx"
  retention_in_days = 7
  tags              = local.tags
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${local.project_name}-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for reading secrets
resource "aws_iam_policy" "ecs_secrets" {
  name = "${local.project_name}-ecs-secrets-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.db_password.arn,
          aws_secretsmanager_secret.app_key.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_secrets" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_secrets.arn
}

# IAM Role for ECS Task
resource "aws_iam_role" "ecs_task_role" {
  name = "${local.project_name}-ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
  tags = local.tags
}

# Policy for S3 access
resource "aws_iam_policy" "task_policy" {
  name = "${local.project_name}-task-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.uploads.arn,
          "${aws_s3_bucket.uploads.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.task_policy.arn
}

# ECS Task Definition with both PHP-FPM and Nginx
resource "aws_ecs_task_definition" "app" {
  family                   = "${local.project_name}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${aws_ecr_repository.app.repository_url}:latest"
      essential = true

      environment = [
        { name = "APP_ENV", value = "production" },
        { name = "APP_DEBUG", value = "false" },
        { name = "APP_URL", value = "https://${aws_lb.main.dns_name}" },
        { name = "DB_CONNECTION", value = "pgsql" },
        { name = "DB_HOST", value = aws_db_instance.db.address },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_DATABASE", value = "laravel" },
        { name = "DB_USERNAME", value = "laravel_admin" },
        { name = "CACHE_DRIVER", value = "redis" },
        { name = "REDIS_HOST", value = aws_elasticache_cluster.cache.cache_nodes[0].address },
        { name = "REDIS_PORT", value = "6379" },
        { name = "SESSION_DRIVER", value = "redis" },
        { name = "FILESYSTEM_DISK", value = "s3" },
        { name = "AWS_BUCKET", value = aws_s3_bucket.uploads.id },
        { name = "AWS_DEFAULT_REGION", value = var.region },
        { name = "AWS_USE_PATH_STYLE_ENDPOINT", value = "false" }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.db_password.arn}:password::"
        },
        {
          name      = "APP_KEY"
          valueFrom = "${aws_secretsmanager_secret.app_key.arn}:key::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "app"
        }
      }

      # Health check for the container
      healthCheck = {
        command     = ["CMD-SHELL", "php-fpm-healthcheck || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    },
    {
      name      = "nginx"
      image     = "${aws_ecr_repository.nginx.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]

      dependsOn = [
        {
          containerName = "app"
          condition     = "HEALTHY"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.nginx.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "nginx"
        }
      }
    }
  ])

  tags = local.tags
}

# ECS Service
resource "aws_ecs_service" "app" {
  name            = "${local.project_name}-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"
  desired_count   = 2

  deployment_controller {
    type = "ECS"
  }

  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "nginx"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http]

  tags = local.tags
}

# AWS Managed Prometheus
resource "aws_prometheus_workspace" "main" {
  alias = "${local.project_name}-amp"
  tags  = local.tags
}

# IAM role for Grafana
resource "aws_iam_role" "grafana" {
  name = "${local.project_name}-grafana-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "grafana.amazonaws.com"
        }
      }
    ]
  })
  tags = local.tags
}

# Policy for Grafana to query Prometheus
resource "aws_iam_policy" "grafana_amp" {
  name = "${local.project_name}-grafana-amp-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:QueryMetrics",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = aws_prometheus_workspace.main.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_amp" {
  role       = aws_iam_role.grafana.name
  policy_arn = aws_iam_policy.grafana_amp.arn
}

# AWS Managed Grafana
resource "aws_grafana_workspace" "main" {
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  data_sources             = ["PROMETHEUS"]
  role_arn                 = aws_iam_role.grafana.arn
  name                     = "${local.project_name}-grafana"

  tags = local.tags
}