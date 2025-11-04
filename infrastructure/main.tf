terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1. Create an SSH key pair to access the EC2 instance
# (Run 'ssh-keygen -t rsa -f ~/.ssh/tf-key' on your *local* machine first)
resource "aws_key_pair" "deployer" {
  key_name   = "tf-deployer-key"
  public_key = file("~/.ssh/tf-key.pub") # Path to your public key
}

# 2. Create the Container Registry to store your app image
resource "aws_ecr_repository" "app" {
  name = "laravel-app"
}

# 3. Define Security Rules
resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  description = "Allow all necessary traffic"

  # Allow SSH (for GitHub Actions deploy)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 👈 For production, lock this to GitHub's IP
  }

  # Allow HTTP (for Nginx)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 👈 Lock this to your IP
  }

  # Allow Prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 👈 Lock this to your IP
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 4. Create the EC2 Instance
resource "aws_instance" "app_server" {
  ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 (us-east-1)
  instance_type = "t3.small" # t3.micro may be too small for all this
  key_name      = aws_key_pair.deployer.key_name
  security_groups = [aws_security_group.app_sg.name]

  # This script runs on boot to install Docker
  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo amazon-linux-extras install docker -y
              sudo service docker start
              sudo usermod -a -G docker ec2-user

              # Install Docker Compose
              sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              sudo chmod +x /usr/local/bin/docker-compose

              # Install AWS CLI (for ECR login)
              sudo yum install aws-cli -y
              EOF

  tags = {
    Name = "Laravel-Server"
  }
}