# ---------------------------------------------------------------------------
# Environment root module. dev and prod contain the SAME wiring; only the
# values in terraform.tfvars differ -> identical architecture, different size.
# ---------------------------------------------------------------------------
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial backend config: bucket/key/table come from backend.hcl
  # (terraform init -backend-config=backend.hcl). Variables are not allowed here.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  # Every resource automatically gets these tags (useful for cost tracking).
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project}-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2) # use 2 AZs
}

# Network: VPC + public/app/db subnets + NAT
module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  azs                = local.azs
  single_nat_gateway = var.single_nat_gateway
}

# Tier 1: load balancer in the public subnets
module "alb" {
  source = "../../modules/alb"

  name              = local.name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
}

# Tier 2: autoscaling web servers in the private app subnets
module "asg" {
  source = "../../modules/asg"

  name             = local.name
  environment      = var.environment
  vpc_id           = module.vpc.vpc_id
  subnet_ids       = module.vpc.app_subnet_ids
  alb_sg_id        = module.alb.alb_sg_id
  target_group_arn = module.alb.target_group_arn
  instance_type    = var.instance_type
  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired
}

# Tier 3: private MySQL database (only the app SG can reach it)
module "rds" {
  source = "../../modules/rds"

  name                  = local.name
  vpc_id                = module.vpc.vpc_id
  db_subnet_ids         = module.vpc.db_subnet_ids
  app_sg_id             = module.asg.app_sg_id
  app_role_name         = module.asg.instance_role_name
  instance_class        = var.db_instance_class
  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention
  deletion_protection   = var.db_deletion_protection
  skip_final_snapshot   = var.db_skip_final_snapshot
}
