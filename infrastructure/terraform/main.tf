# ============================================
# Main Terraform Configuration
# High Availability 3-Tier Architecture
# ============================================

terraform {
  required_version = ">= 1.3.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    kms_key_id     = "arn:aws:kms:us-east-1:ACCOUNT_ID:key/KEY_ID"
  }
}

# ====== Provider Configuration ======
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      CostCenter  = var.cost_center
      Owner       = var.owner_email
    }
  }
}

provider "aws" {
  alias  = "dr_region"
  region = var.dr_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      CostCenter  = var.cost_center
      Owner       = var.owner_email
      Purpose     = "DisasterRecovery"
    }
  }
}

# ====== Data Sources ======
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# ====== Local Variables ======
locals {
  account_id = data.aws_caller_identity.current.account_id
  azs        = slice(data.aws_availability_zones.available.names, 0, 3)
  
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    Terraform   = "true"
  }
}

# ====== VPC Module ======
module "vpc" {
  source = "./modules/vpc"

  vpc_name             = "${var.project_name}-${var.environment}-vpc"
  vpc_cidr             = var.vpc_cidr
  availability_zones   = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  
  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  enable_vpn_gateway   = var.enable_vpn_gateway
  enable_flow_logs     = true
  flow_logs_retention  = 30

  tags = local.common_tags
}

# ====== EKS Cluster Module ======
module "eks" {
  source = "./modules/eks"

  cluster_name    = "${var.project_name}-${var.environment}-cluster"
  cluster_version = var.eks_cluster_version
  
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
  cluster_endpoint_public_access_cidrs = var.allowed_cidr_blocks

  enable_irsa = true
  
  node_groups = {
    general = {
      desired_capacity = var.node_group_desired_capacity
      max_capacity     = var.node_group_max_capacity
      min_capacity     = var.node_group_min_capacity
      
      instance_types = ["t3.large", "t3a.large"]
      capacity_type  = "ON_DEMAND"
      
      labels = {
        role = "general"
      }
      
      taints = []
      
      update_config = {
        max_unavailable_percentage = 33
      }
    }
    
    spot = {
      desired_capacity = 2
      max_capacity     = 10
      min_capacity     = 0
      
      instance_types = ["t3.large", "t3a.large", "t3.xlarge"]
      capacity_type  = "SPOT"
      
      labels = {
        role = "spot"
        workload = "non-critical"
      }
      
      taints = [{
        key    = "spot"
        value  = "true"
        effect = "NoSchedule"
      }]
    }
  }

  tags = local.common_tags
}

# ====== RDS MySQL Module ======
module "rds_mysql" {
  source = "./modules/rds"

  identifier     = "${var.project_name}-${var.environment}-mysql"
  engine         = "mysql"
  engine_version = "8.0.35"
  instance_class = var.rds_instance_class
  
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_encrypted     = true
  kms_key_id           = module.kms.rds_key_arn
  
  db_name  = var.mysql_database_name
  username = var.mysql_master_username
  port     = 3306
  
  multi_az               = true
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.security_groups.rds_sg_id]
  
  backup_retention_period = 30
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"
  
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  
  deletion_protection = var.environment == "production" ? true : false
  skip_final_snapshot = var.environment == "production" ? false : true
  final_snapshot_identifier = "${var.project_name}-${var.environment}-mysql-final"
  
  performance_insights_enabled = true
  performance_insights_retention_period = 7
  
  parameters = [
    {
      name  = "character_set_server"
      value = "utf8mb4"
    },
    {
      name  = "max_connections"
      value = "1000"
    }
  ]

  tags = local.common_tags
}

# ====== DocumentDB (MongoDB) Module ======
module "documentdb" {
  source = "./modules/documentdb"

  cluster_identifier      = "${var.project_name}-${var.environment}-docdb"
  engine_version          = "5.0.0"
  master_username         = var.mongodb_master_username
  
  instance_class          = var.docdb_instance_class
  instance_count          = 3
  
  db_subnet_group_name    = module.vpc.database_subnet_group_name
  vpc_security_group_ids  = [module.security_groups.docdb_sg_id]
  
  backup_retention_period = 30
  preferred_backup_window = "02:00-03:00"
  preferred_maintenance_window = "mon:03:00-mon:04:00"
  
  enabled_cloudwatch_logs_exports = ["audit", "profiler"]
  
  storage_encrypted = true
  kms_key_id       = module.kms.docdb_key_arn
  
  deletion_protection = var.environment == "production" ? true : false
  skip_final_snapshot = var.environment == "production" ? false : true
  final_snapshot_identifier = "${var.project_name}-${var.environment}-docdb-final"

  tags = local.common_tags
}

# ====== ElastiCache Redis Module ======
module "elasticache_redis" {
  source = "./modules/elasticache"

  replication_group_id       = "${var.project_name}-${var.environment}-redis"
  replication_group_description = "Redis cluster for ${var.project_name}"
  
  engine_version            = "7.0"
  node_type                 = var.redis_node_type
  num_cache_clusters        = 3
  
  parameter_group_family    = "redis7"
  port                      = 6379
  
  subnet_group_name         = module.vpc.elasticache_subnet_group_name
  security_group_ids        = [module.security_groups.redis_sg_id]
  
  automatic_failover_enabled = true
  multi_az_enabled          = true
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token_enabled        = true
  kms_key_id               = module.kms.elasticache_key_arn
  
  snapshot_retention_limit  = 7
  snapshot_window          = "03:00-05:00"
  maintenance_window       = "mon:05:00-mon:07:00"
  
  notification_topic_arn   = module.sns.alerts_topic_arn

  tags = local.common_tags
}

# ====== Application Load Balancer Module ======
module "alb" {
  source = "./modules/alb"

  name               = "${var.project_name}-${var.environment}-alb"
  load_balancer_type = "application"
  
  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnet_ids
  security_groups = [module.security_groups.alb_sg_id]
  
  enable_deletion_protection = var.environment == "production" ? true : false
  enable_http2              = true
  enable_cross_zone_load_balancing = true
  
  access_logs = {
    bucket  = module.s3.alb_logs_bucket_id
    enabled = true
  }
  
  target_groups = {
    backend = {
      name                 = "${var.project_name}-${var.environment}-backend"
      port                 = 8000
      protocol             = "HTTP"
      target_type          = "ip"
      deregistration_delay = 30
      
      health_check = {
        enabled             = true
        interval            = 30
        path                = "/health"
        port                = "traffic-port"
        healthy_threshold   = 2
        unhealthy_threshold = 3
        timeout             = 5
        protocol            = "HTTP"
        matcher             = "200-299"
      }
      
      stickiness = {
        enabled         = true
        type            = "lb_cookie"
        cookie_duration = 86400
      }
    }
  }

  listeners = {
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = module.acm.certificate_arn
      ssl_policy      = "ELBSecurityPolicy-TLS-1-2-2017-01"
      
      default_action = {
        type             = "forward"
        target_group_key = "backend"
      }
    }
    
    http = {
      port     = 80
      protocol = "HTTP"
      
      default_action = {
        type = "redirect"
        redirect = {
          port        = "443"
          protocol    = "HTTPS"
          status_code = "HTTP_301"
        }
      }
    }
  }

  tags = local.common_tags
}

# ====== CloudFront Distribution Module ======
module "cloudfront" {
  source = "./modules/cloudfront"

  aliases = var.frontend_domain_names
  
  comment             = "${var.project_name} ${var.environment} distribution"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = var.cloudfront_price_class
  
  origin = {
    s3_frontend = {
      domain_name = module.s3.frontend_bucket_regional_domain_name
      origin_id   = "S3-${module.s3.frontend_bucket_id}"
      
      s3_origin_config = {
        origin_access_identity = module.cloudfront.origin_access_identity_path
      }
    }
  }
  
  default_cache_behavior = {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${module.s3.frontend_bucket_id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    
    forwarded_values = {
      query_string = false
      cookies = {
        forward = "none"
      }
    }
    
    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }
  
  custom_error_response = [
    {
      error_code         = 403
      response_code      = 200
      response_page_path = "/index.html"
    },
    {
      error_code         = 404
      response_code      = 200
      response_page_path = "/index.html"
    }
  ]
  
  viewer_certificate = {
    acm_certificate_arn      = module.acm.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
  
  web_acl_id = module.waf.web_acl_id

  tags = local.common_tags
}

# ====== S3 Buckets Module ======
module "s3" {
  source = "./modules/s3"

  buckets = {
    frontend = {
      bucket_name = "${var.project_name}-${var.environment}-frontend"
      versioning  = true
      
      lifecycle_rules = [
        {
          id      = "delete-old-versions"
          enabled = true
          noncurrent_version_expiration = {
            days = 90
          }
        }
      ]
    }
    
    assets = {
      bucket_name = "${var.project_name}-${var.environment}-assets"
      versioning  = true
    }
    
    backups = {
      bucket_name = "${var.project_name}-${var.environment}-backups"
      versioning  = true
      
      lifecycle_rules = [
        {
          id      = "transition-to-glacier"
          enabled = true
          transitions = [
            {
              days          = 30
              storage_class = "STANDARD_IA"
            },
            {
              days          = 90
              storage_class = "GLACIER"
            }
          ]
        }
      ]
    }
    
    alb_logs = {
      bucket_name = "${var.project_name}-${var.environment}-alb-logs"
      versioning  = false
      
      lifecycle_rules = [
        {
          id      = "expire-old-logs"
          enabled = true
          expiration = {
            days = 90
          }
        }
      ]
    }
  }

  enable_encryption = true
  kms_key_id       = module.kms.s3_key_arn

  tags = local.common_tags
}

# ====== WAF Module ======
module "waf" {
  source = "./modules/waf"

  name  = "${var.project_name}-${var.environment}-waf"
  scope = "CLOUDFRONT"
  
  rules = {
    rate_limit = {
      priority = 1
      action   = "block"
      
      rate_based_statement = {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    
    geo_blocking = {
      priority = 2
      action   = "block"
      
      geo_match_statement = {
        country_codes = var.blocked_countries
      }
    }
    
    aws_managed_rules = {
      priority = 3
      action   = "block"
      
      managed_rule_group_statement = {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    
    sql_injection = {
      priority = 4
      action   = "block"
      
      managed_rule_group_statement = {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }
  }

  tags = local.common_tags
}

# ====== KMS Keys Module ======
module "kms" {
  source = "./modules/kms"

  keys = {
    rds = {
      description             = "KMS key for RDS encryption"
      deletion_window_in_days = 30
      enable_key_rotation     = true
    }
    
    docdb = {
      description             = "KMS key for DocumentDB encryption"
      deletion_window_in_days = 30
      enable_key_rotation     = true
    }
    
    elasticache = {
      description             = "KMS key for ElastiCache encryption"
      deletion_window_in_days = 30
      enable_key_rotation     = true
    }
    
    s3 = {
      description             = "KMS key for S3 encryption"
      deletion_window_in_days = 30
      enable_key_rotation     = true
    }
    
    secrets = {
      description             = "KMS key for Secrets Manager"
      deletion_window_in_days = 30
      enable_key_rotation     = true
    }
  }

  tags = local.common_tags
}

# ====== Security Groups Module ======
module "security_groups" {
  source = "./modules/security-groups"

  vpc_id = module.vpc.vpc_id
  
  eks_cluster_security_group_id = module.eks.cluster_security_group_id
  
  alb_allowed_cidrs = var.allowed_cidr_blocks

  tags = local.common_tags
}

# ====== ACM Certificate Module ======
module "acm" {
  source = "./modules/acm"

  domain_name               = var.primary_domain
  subject_alternative_names = var.alternative_domains
  
  validation_method = "DNS"
  
  wait_for_validation = true

  tags = local.common_tags
}

# ====== Route53 Module ======
module "route53" {
  source = "./modules/route53"

  zone_name = var.primary_domain
  
  records = {
    alb = {
      name = "api"
      type = "A"
      
      alias = {
        name                   = module.alb.dns_name
        zone_id                = module.alb.zone_id
        evaluate_target_health = true
      }
    }
    
    cloudfront = {
      name = ""
      type = "A"
      
      alias = {
        name                   = module.cloudfront.domain_name
        zone_id                = module.cloudfront.hosted_zone_id
        evaluate_target_health = false
      }
    }
  }

  tags = local.common_tags
}

# ====== SNS Topics Module ======
module "sns" {
  source = "./modules/sns"

  topics = {
    alerts = {
      name         = "${var.project_name}-${var.environment}-alerts"
      display_name = "Production Alerts"
      
      subscriptions = [
        {
          protocol = "email"
          endpoint = var.alert_email
        }
      ]
    }
    
    deployments = {
      name         = "${var.project_name}-${var.environment}-deployments"
      display_name = "Deployment Notifications"
    }
  }

  tags = local.common_tags
}

# ====== CloudWatch Alarms Module ======
module "cloudwatch_alarms" {
  source = "./modules/cloudwatch-alarms"

  alarms = {
    eks_cpu_high = {
      alarm_name          = "${var.project_name}-${var.environment}-eks-cpu-high"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 2
      metric_name         = "node_cpu_utilization"
      namespace           = "ContainerInsights"
      period              = 300
      statistic           = "Average"
      threshold           = 80
      alarm_actions       = [module.sns.alerts_topic_arn]
    }
    
    rds_cpu_high = {
      alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-high"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 2
      metric_name         = "CPUUtilization"
      namespace           = "AWS/RDS"
      period              = 300
      statistic           = "Average"
      threshold           = 80
      alarm_actions       = [module.sns.alerts_topic_arn]
      
      dimensions = {
        DBInstanceIdentifier = module.rds_mysql.instance_id
      }
    }
  }

  tags = local.common_tags
}

# ====== Outputs ======
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint"
  value       = module.rds_mysql.endpoint
  sensitive   = true
}

output "documentdb_endpoint" {
  description = "DocumentDB cluster endpoint"
  value       = module.documentdb.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = module.elasticache_redis.primary_endpoint_address
  sensitive   = true
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.dns_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.cloudfront.distribution_id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name"
  value       = module.cloudfront.domain_name
}

output "frontend_bucket_name" {
  description = "Frontend S3 bucket name"
  value       = module.s3.frontend_bucket_id
}
