provider "aws" {
  region = "ap-southeast-1"
}

# 1. Create a VPC for your Cluster
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "scalable-app-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-southeast-1a", "ap-southeast-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"] # Nodes go here
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"] # Load Balancers go here

  enable_nat_gateway = true
  single_nat_gateway = true # Save money in dev/staging
  enable_dns_hostnames = true

  public_subnet_tags = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}

# 2. Create the EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.0"

  cluster_name    = "scalable-app-cluster"
  cluster_version = "1.27"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true # Allow you to run kubectl from laptop

  # Create the OIDC Provider (Critical for Service Accounts)
  enable_irsa = true

  eks_managed_node_groups = {
    general = {
      desired_size = 2
      min_size     = 1
      max_size     = 3
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
    }
  }
}

# 3. Create S3 Bucket for Loki Logs
resource "aws_s3_bucket" "loki_logs" {
  bucket = "scalable-app-loki-logs-12345" # Must be unique
}

# Output the Command to Connect
output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region us-east-1 --name scalable-app-cluster"
}