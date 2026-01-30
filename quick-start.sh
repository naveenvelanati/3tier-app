#!/bin/bash

# ============================================
# Quick Start Script
# High Availability 3-Tier Application
# ============================================

set -e

echo "=========================================="
echo "High Availability 3-Tier App - Quick Start"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: Do not run this script as root${NC}"
    exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "Checking prerequisites..."
echo ""

MISSING_DEPS=()

if ! command_exists docker; then
    MISSING_DEPS+=("docker")
fi

if ! command_exists kubectl; then
    MISSING_DEPS+=("kubectl")
fi

if ! command_exists terraform; then
    MISSING_DEPS+=("terraform")
fi

if ! command_exists aws; then
    MISSING_DEPS+=("aws-cli")
fi

if ! command_exists helm; then
    MISSING_DEPS+=("helm")
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "${RED}Missing dependencies:${NC}"
    printf '%s\n' "${MISSING_DEPS[@]}"
    echo ""
    echo "Please install the missing dependencies and try again."
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites installed${NC}"
echo ""

# Prompt for deployment type
echo "Select deployment type:"
echo "1) Local Development (Docker Compose)"
echo "2) AWS Production Deployment"
echo ""
read -p "Enter choice [1-2]: " deployment_choice

case $deployment_choice in
    1)
        echo ""
        echo "Starting local development environment..."
        echo ""
        
        # Check if .env exists
        if [ ! -f .env ]; then
            echo "Creating .env file from template..."
            cp .env.example .env
            echo -e "${YELLOW}⚠ Please update .env with your configuration${NC}"
        fi
        
        # Start Docker Compose
        echo "Starting services with Docker Compose..."
        docker-compose up -d
        
        echo ""
        echo -e "${GREEN}✓ Local environment started successfully!${NC}"
        echo ""
        echo "Services available at:"
        echo "  - Frontend: http://localhost:3000"
        echo "  - Backend API: http://localhost:8000"
        echo "  - API Docs: http://localhost:8000/api/docs"
        echo "  - Prometheus: http://localhost:9090"
        echo "  - Grafana: http://localhost:3001 (admin/admin)"
        echo ""
        echo "To view logs: docker-compose logs -f"
        echo "To stop: docker-compose down"
        echo ""
        ;;
    
    2)
        echo ""
        echo "AWS Production Deployment"
        echo "========================="
        echo ""
        
        # Check AWS credentials
        if ! aws sts get-caller-identity >/dev/null 2>&1; then
            echo -e "${RED}Error: AWS credentials not configured${NC}"
            echo "Please run: aws configure"
            exit 1
        fi
        
        echo -e "${GREEN}✓ AWS credentials configured${NC}"
        echo ""
        
        # Check if terraform.tfvars exists
        if [ ! -f infrastructure/terraform/terraform.tfvars ]; then
            echo -e "${YELLOW}Creating terraform.tfvars from template...${NC}"
            cp infrastructure/terraform/terraform.tfvars.example infrastructure/terraform/terraform.tfvars
            echo ""
            echo -e "${RED}IMPORTANT: Edit infrastructure/terraform/terraform.tfvars with your values${NC}"
            echo ""
            read -p "Press Enter when you've updated terraform.tfvars..."
        fi
        
        # Terraform deployment
        echo ""
        echo "Step 1: Deploying AWS Infrastructure with Terraform"
        echo "====================================================="
        echo ""
        echo -e "${YELLOW}This will create:${NC}"
        echo "  - VPC with public, private, and database subnets"
        echo "  - EKS cluster with autoscaling node groups"
        echo "  - RDS MySQL (Multi-AZ)"
        echo "  - DocumentDB (MongoDB-compatible)"
        echo "  - ElastiCache Redis"
        echo "  - Application Load Balancer"
        echo "  - CloudFront distribution"
        echo "  - S3 buckets"
        echo "  - WAF, CloudWatch, and more..."
        echo ""
        echo -e "${RED}Estimated time: 30-45 minutes${NC}"
        echo -e "${RED}Estimated cost: $700-1,450/month${NC}"
        echo ""
        read -p "Continue with Terraform deployment? (yes/no): " terraform_confirm
        
        if [ "$terraform_confirm" != "yes" ]; then
            echo "Deployment cancelled."
            exit 0
        fi
        
        cd infrastructure/terraform
        
        echo ""
        echo "Initializing Terraform..."
        terraform init
        
        echo ""
        echo "Planning deployment..."
        terraform plan -out=tfplan
        
        echo ""
        read -p "Review the plan above. Apply? (yes/no): " apply_confirm
        
        if [ "$apply_confirm" != "yes" ]; then
            echo "Deployment cancelled."
            exit 0
        fi
        
        echo ""
        echo "Applying Terraform configuration..."
        terraform apply tfplan
        
        echo ""
        echo -e "${GREEN}✓ Infrastructure deployed successfully!${NC}"
        echo ""
        
        # Save outputs
        echo "Saving Terraform outputs..."
        terraform output > ../outputs.txt
        
        cd ../..
        
        echo ""
        echo "Step 2: Configuring Kubernetes"
        echo "==============================="
        echo ""
        
        # Get EKS cluster name from terraform output
        CLUSTER_NAME=$(cd infrastructure/terraform && terraform output -raw eks_cluster_name 2>/dev/null || echo "production-cluster")
        AWS_REGION=$(cd infrastructure/terraform && terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
        
        echo "Updating kubeconfig for EKS cluster..."
        aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
        
        echo ""
        echo "Verifying cluster connection..."
        kubectl get nodes
        
        echo ""
        echo -e "${GREEN}✓ Kubernetes configured${NC}"
        echo ""
        
        echo "Next steps:"
        echo "==========="
        echo "1. Create Kubernetes secrets (database passwords, JWT secret, etc.)"
        echo "   See: docs/deployment.md - Phase 2.2"
        echo ""
        echo "2. Build and push Docker images to ECR"
        echo "   See: docs/deployment.md - Phase 3"
        echo ""
        echo "3. Deploy applications to Kubernetes"
        echo "   See: docs/deployment.md - Phase 4"
        echo ""
        echo "4. Setup monitoring (Prometheus, Grafana)"
        echo "   See: docs/deployment.md - Phase 6"
        echo ""
        echo "5. Configure DNS and SSL"
        echo "   See: docs/deployment.md - Phase 7"
        echo ""
        echo -e "${YELLOW}Full deployment guide: docs/deployment.md${NC}"
        echo ""
        ;;
    
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "For more information, see:"
echo "  - README.md"
echo "  - docs/deployment.md"
echo "  - docs/architecture/"
echo ""
