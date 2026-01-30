# High Availability 3-Tier Cloud Application

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![AWS](https://img.shields.io/badge/AWS-Ready-orange.svg)](https://aws.amazon.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Ready-blue.svg)](https://kubernetes.io/)

## 🏗️ Architecture Overview

Production-grade, highly available 3-tier cloud application with:
- **Presentation Tier**: React/Angular frontend with CDN distribution
- **Application Tier**: Python/Java microservices APIs
- **Data Tier**: MySQL (RDS) + MongoDB hybrid database architecture
- **DevOps**: Complete CI/CD automation pipeline
- **Monitoring**: AI-driven observability with predictive analytics
- **Security**: Enterprise-grade security controls and compliance

## 📋 Prerequisites

- AWS Account with appropriate permissions
- Docker Desktop (v20+)
- Kubernetes (kubectl v1.24+)
- Terraform (v1.3+)
- Node.js (v18+)
- Python (v3.9+) or Java (v17+)
- AWS CLI configured
- Helm (v3+)

## 🚀 Quick Start

### 1. Clone and Setup Environment

```bash
git clone <your-repo>
cd high-availability-3tier-app
cp .env.example .env
# Edit .env with your AWS credentials and configuration
```

### 2. Configure Variables

Edit the following files with your environment-specific values:
- `.env` - Application configuration
- `infrastructure/terraform/terraform.tfvars` - Infrastructure variables
- `devops/kubernetes/config/secrets.yaml.example` - Kubernetes secrets

### 3. Deploy Infrastructure

```bash
# Initialize and deploy AWS infrastructure
cd infrastructure/terraform
terraform init
terraform plan
terraform apply

# Note the outputs (VPC ID, Subnet IDs, RDS endpoints, etc.)
```

### 4. Deploy Kubernetes Cluster

```bash
# Update kubeconfig for EKS
aws eks update-kubeconfig --region us-east-1 --name production-cluster

# Deploy applications
cd ../../devops/kubernetes
kubectl apply -f namespaces/
kubectl apply -f config/
kubectl apply -f deployments/
kubectl apply -f services/
```

### 5. Deploy Frontend

```bash
cd frontend
npm install
npm run build

# Deploy to S3 + CloudFront (automated via CI/CD)
aws s3 sync build/ s3://your-frontend-bucket
aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths "/*"
```

### 6. Deploy Backend

```bash
cd backend

# Python version
cd python-api
docker build -t your-registry/api:latest .
docker push your-registry/api:latest

# Or Java version
cd java-api
./mvnw clean package
docker build -t your-registry/api:latest .
docker push your-registry/api:latest
```

### 7. Setup Monitoring

```bash
cd monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -f prometheus-values.yaml
helm install grafana grafana/grafana -f grafana-values.yaml
```

## 📁 Project Structure

```
.
├── frontend/                    # React/Angular application
│   ├── src/
│   ├── public/
│   ├── Dockerfile
│   └── package.json
├── backend/                     # API services
│   ├── python-api/             # Python (FastAPI/Django) implementation
│   ├── java-api/               # Java (Spring Boot) implementation
│   └── shared/                 # Shared libraries
├── infrastructure/             # Infrastructure as Code
│   ├── terraform/              # AWS infrastructure
│   ├── cloudformation/         # Alternative CloudFormation templates
│   └── scripts/                # Utility scripts
├── devops/                     # DevOps automation
│   ├── kubernetes/             # K8s manifests
│   ├── helm-charts/            # Helm charts
│   ├── ci-cd/                  # Pipeline definitions
│   └── docker/                 # Docker configurations
├── monitoring/                 # Observability stack
│   ├── prometheus/
│   ├── grafana/
│   └── elk/
└── docs/                       # Documentation
    ├── architecture/
    ├── api/
    └── runbooks/
```

## 🔐 Security Configuration

### Required Secrets

Create these secrets in AWS Secrets Manager:

```bash
# Database credentials
aws secretsmanager create-secret --name prod/db/mysql \
  --secret-string '{"username":"admin","password":"YOUR_SECURE_PASSWORD"}'

aws secretsmanager create-secret --name prod/db/mongodb \
  --secret-string '{"username":"admin","password":"YOUR_SECURE_PASSWORD"}'

# API keys
aws secretsmanager create-secret --name prod/api/jwt-secret \
  --secret-string '{"secret":"YOUR_JWT_SECRET"}'

# Third-party integrations
aws secretsmanager create-secret --name prod/api/integrations \
  --secret-string '{"datadog_api_key":"YOUR_KEY","newrelic_key":"YOUR_KEY"}'
```

### IAM Roles

The Terraform scripts automatically create:
- EKS cluster role
- Node group roles
- RDS access roles
- S3 access roles
- Lambda execution roles

## 🔄 CI/CD Pipeline

### GitHub Actions Workflow

```bash
# Triggers on:
- Push to main/develop branches
- Pull request creation
- Manual workflow dispatch

# Stages:
1. Code quality checks (SonarQube, ESLint, Pylint)
2. Security scanning (Snyk, Trivy)
3. Unit tests
4. Build Docker images
5. Push to ECR
6. Deploy to staging
7. Integration tests
8. Deploy to production (with approval)
```

### GitLab CI Alternative

See `devops/ci-cd/gitlab-ci.yml` for GitLab implementation.

## 📊 Monitoring & Observability

### Dashboards

Access monitoring dashboards:
- **Grafana**: `https://grafana.amaravathi.today`
- **Prometheus**: `https://prometheus.amaravathi.today`
- **Kibana**: `https://kibana.amaravathi.today`
- **Jaeger (Tracing)**: `https://jaeger.amaravathi.today`

### Key Metrics

- Application latency (p50, p95, p99)
- Error rates by service
- Database query performance
- Infrastructure costs
- Security events

### Alerts

Configured alerts for:
- High error rates (>1%)
- Slow response times (>500ms)
- Database connection failures
- High CPU/Memory usage (>80%)
- SSL certificate expiration
- Security anomalies

## 🧪 Testing

```bash
# Unit tests
cd backend/python-api && pytest
cd backend/java-api && ./mvnw test

# Integration tests
cd tests/integration && python -m pytest

# Load tests
cd tests/load && k6 run load-test.js

# Security tests
cd tests/security && ./run-security-tests.sh
```

## 🔧 Troubleshooting

### Common Issues

**Issue**: Pods not starting
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

**Issue**: Database connection failures
```bash
# Check security groups
aws ec2 describe-security-groups --group-ids sg-xxxxx
# Verify RDS endpoint
aws rds describe-db-instances --db-instance-identifier prod-mysql
```

**Issue**: High latency
```bash
# Check service mesh metrics
kubectl -n istio-system logs -l app=istio-ingressgateway
```

## 📈 Scaling

### Horizontal Scaling

```bash
# Scale deployments
kubectl scale deployment api-backend --replicas=10

# Configure HPA
kubectl autoscale deployment api-backend --cpu-percent=70 --min=3 --max=20
```

### Vertical Scaling

Update resource limits in `devops/kubernetes/deployments/`:
```yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

## 🔄 Disaster Recovery

### Backup Strategy

- **RDS**: Automated daily backups, 7-day retention
- **MongoDB**: Continuous backup to S3
- **Application State**: Redis snapshots every 6 hours
- **Configuration**: GitOps repository as source of truth

### Recovery Procedures

See `docs/runbooks/disaster-recovery.md` for detailed procedures.

## 💰 Cost Optimization

Estimated monthly costs (based on moderate traffic):
- **EKS Cluster**: $150-300
- **RDS (Multi-AZ)**: $200-400
- **DocumentDB**: $150-300
- **ALB/NLB**: $50-100
- **CloudFront**: $50-150
- **Monitoring**: $100-200

**Total**: ~$700-1,450/month

Tips for cost reduction:
- Use Spot instances for non-critical workloads
- Implement auto-scaling to scale down during low traffic
- Use S3 Intelligent-Tiering
- Review CloudWatch log retention policies

## 📚 Documentation

- [Architecture Overview](docs/architecture/overview.md)
- [API Documentation](docs/api/README.md)
- [Deployment Guide](docs/deployment.md)
- [Security Best Practices](docs/security.md)
- [Monitoring Guide](docs/monitoring.md)
- [Troubleshooting](docs/troubleshooting.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

- Documentation: [docs/](docs/)
- Issues: GitHub Issues
- Email: naveenkumarvelanati@gmailcom

## 🙏 Acknowledgments

- AWS for cloud infrastructure
- Kubernetes community
- Open source contributors

---

**Built with ❤️ for production workloads**