# ============================================
# Terraform Variables
# ============================================

# ====== General Configuration ======
variable "aws_region" {
  description = "AWS region for primary resources"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "AWS region for disaster recovery"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "high-availability-app"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

variable "owner_email" {
  description = "Owner email for notifications"
  type        = string
}

# ====== VPC Configuration ======
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
}

variable "enable_vpn_gateway" {
  description = "Enable VPN gateway"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ====== EKS Configuration ======
variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "node_group_desired_capacity" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "node_group_min_capacity" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 3
}

variable "node_group_max_capacity" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 10
}

# ====== RDS Configuration ======
variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "rds_allocated_storage" {
  description = "Allocated storage for RDS (GB)"
  type        = number
  default     = 100
}

variable "rds_max_allocated_storage" {
  description = "Maximum allocated storage for RDS (GB)"
  type        = number
  default     = 1000
}

variable "mysql_database_name" {
  description = "MySQL database name"
  type        = string
  default     = "production_db"
}

variable "mysql_master_username" {
  description = "MySQL master username"
  type        = string
  default     = "admin"
}

# ====== DocumentDB Configuration ======
variable "docdb_instance_class" {
  description = "DocumentDB instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "mongodb_master_username" {
  description = "MongoDB master username"
  type        = string
  default     = "admin"
}

# ====== ElastiCache Configuration ======
variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.r6g.large"
}

# ====== CloudFront Configuration ======
variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_All"
}

# ====== Domain Configuration ======
variable "primary_domain" {
  description = "Primary domain name"
  type        = string
}

variable "alternative_domains" {
  description = "Alternative domain names"
  type        = list(string)
  default     = []
}

variable "frontend_domain_names" {
  description = "Frontend domain names for CloudFront"
  type        = list(string)
}

# ====== Security Configuration ======
variable "blocked_countries" {
  description = "Countries to block in WAF"
  type        = list(string)
  default     = []
}

# ====== Notifications ======
variable "alert_email" {
  description = "Email address for alerts"
  type        = string
}
