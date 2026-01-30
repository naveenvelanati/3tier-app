# Deployment Guide

## Prerequisites Checklist

Before deploying, ensure you have:

- [ ] AWS Account with appropriate IAM permissions
- [ ] AWS CLI installed and configured
- [ ] Terraform v1.3+ installed
- [ ] kubectl v1.24+ installed
- [ ] Docker Desktop installed
- [ ] Helm v3+ installed
- [ ] Domain name registered and Route53 hosted zone created
- [ ] SSL certificate requested in ACM (or let Terraform create it)

## Step-by-Step Deployment

### Phase 1: Infrastructure Setup (30-45 minutes)

#### 1.1 Configure Terraform Backend

First, create the S3 bucket and DynamoDB table for Terraform state:

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://your-terraform-state-bucket --region us-east-1
aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1
```

#### 1.2 Configure Variables

```bash
cd infrastructure/terraform

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit with your specific values
nano terraform.tfvars
```

Update the following critical values:
- `owner_email` - Your email for alerts
- `primary_domain` - Your domain name
- `alert_email` - Email for production alerts
- `allowed_cidr_blocks` - Restrict to your IP ranges

#### 1.3 Update Backend Configuration

Edit `main.tf` and update the backend configuration:

```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"  # Update this
  key            = "production/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "terraform-state-lock"
}
```

#### 1.4 Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan -out=tfplan

# Apply the infrastructure (takes 30-45 minutes)
terraform apply tfplan
```

**Important**: Save the Terraform outputs. You'll need them for the next steps:

```bash
terraform output > ../outputs.txt
```

### Phase 2: Configure Kubernetes (15-20 minutes)

#### 2.1 Update Kubeconfig

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name production-cluster

# Verify connection
kubectl get nodes
```

#### 2.2 Create Kubernetes Secrets

Create secrets using the values from Terraform outputs:

```bash
cd ../../devops/kubernetes

# Database secrets
kubectl create secret generic database-secrets \
  --from-literal=mysql-host='<RDS_ENDPOINT>' \
  --from-literal=mysql-user='admin' \
  --from-literal=mysql-password='<SECURE_PASSWORD>' \
  --from-literal=mysql-database='production_db' \
  --from-literal=mongodb-host='<DOCDB_ENDPOINT>' \
  --from-literal=mongodb-user='admin' \
  --from-literal=mongodb-password='<SECURE_PASSWORD>' \
  --from-literal=mongodb-database='production_db' \
  --namespace=production

# Cache secrets
kubectl create secret generic cache-secrets \
  --from-literal=redis-host='<REDIS_ENDPOINT>' \
  --from-literal=redis-password='<SECURE_PASSWORD>' \
  --namespace=production

# API secrets
kubectl create secret generic api-secrets \
  --from-literal=jwt-secret='<GENERATE_RANDOM_STRING>' \
  --namespace=production

# Monitoring secrets (optional)
kubectl create secret generic monitoring-secrets \
  --from-literal=sentry-dsn='<YOUR_SENTRY_DSN>' \
  --namespace=production
```

**Security Best Practice**: Use AWS Secrets Manager and External Secrets Operator instead:

```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace

# Apply SecretStore and ExternalSecret manifests
kubectl apply -f config/external-secrets/
```

#### 2.3 Create ConfigMaps

```bash
kubectl create configmap app-config \
  --from-literal=s3-bucket-name='<S3_BUCKET_NAME>' \
  --from-literal=aws-region='us-east-1' \
  --namespace=production
```

#### 2.4 Deploy Namespaces and RBAC

```bash
kubectl apply -f namespaces/
kubectl apply -f rbac/
```

### Phase 3: Build and Push Docker Images (10-15 minutes)

#### 3.1 Login to ECR

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```

#### 3.2 Build and Push Backend

```bash
cd ../../backend/python-api

# Build image
docker build -t backend-api:latest .

# Tag for ECR
docker tag backend-api:latest \
  <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/backend-api:latest

# Push to ECR
docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/backend-api:latest
```

#### 3.3 Build and Push Frontend

```bash
cd ../../frontend

# Build image
docker build \
  --build-arg REACT_APP_API_URL=https://api.yourdomain.com \
  --build-arg REACT_APP_ENVIRONMENT=production \
  -t frontend:latest .

# Tag for ECR
docker tag frontend:latest \
  <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/frontend:latest

# Push to ECR
docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/frontend:latest
```

### Phase 4: Deploy Applications (10 minutes)

#### 4.1 Update Deployment Manifests

Edit `devops/kubernetes/deployments/backend-api-deployment.yaml` and replace placeholders:

```yaml
image: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/backend-api:latest
```

#### 4.2 Deploy to Kubernetes

```bash
cd ../../devops/kubernetes

# Deploy applications
kubectl apply -f deployments/
kubectl apply -f services/

# Verify deployments
kubectl get pods -n production
kubectl get svc -n production
```

#### 4.3 Wait for Rollout

```bash
kubectl rollout status deployment/backend-api -n production --timeout=5m
```

### Phase 5: Deploy Frontend to S3 + CloudFront (5 minutes)

```bash
cd ../../frontend

# Build production assets
npm install
npm run build

# Sync to S3
aws s3 sync build/ s3://<FRONTEND_BUCKET_NAME> --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id <CLOUDFRONT_DISTRIBUTION_ID> \
  --paths "/*"
```

### Phase 6: Setup Monitoring (15-20 minutes)

#### 6.1 Install Prometheus Stack

```bash
cd ../../monitoring

# Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f prometheus/prometheus-values.yaml
```

#### 6.2 Install Grafana

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana \
  --namespace monitoring \
  -f grafana/grafana-values.yaml

# Get Grafana admin password
kubectl get secret grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode
```

#### 6.3 Access Grafana

```bash
kubectl port-forward svc/grafana -n monitoring 3000:80
```

Visit http://localhost:3000 and login with admin/<password>

### Phase 7: Configure DNS (5 minutes)

#### 7.1 Get Load Balancer DNS

```bash
kubectl get svc -n istio-system istio-ingressgateway
```

#### 7.2 Update Route53 Records

The Terraform scripts should have already created the records. Verify:

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id <HOSTED_ZONE_ID>
```

### Phase 8: Verification (10 minutes)

#### 8.1 Health Checks

```bash
# Backend API health
curl https://api.yourdomain.com/health

# Frontend
curl https://yourdomain.com

# Metrics endpoint
curl https://api.yourdomain.com/metrics
```

#### 8.2 Load Testing

```bash
cd ../../tests/load

# Install k6
brew install k6  # macOS
# or
sudo snap install k6  # Linux

# Run load test
k6 run load-test.js
```

#### 8.3 Security Testing

```bash
cd ../security

# Run security tests
./run-security-tests.sh
```

## Post-Deployment Configuration

### Enable Auto-Scaling

Auto-scaling is already configured via HPA. Verify:

```bash
kubectl get hpa -n production
```

### Configure Alerts

1. Update Alertmanager configuration
2. Configure Slack/PagerDuty webhooks
3. Test alert routing

### Setup CI/CD

1. Add repository secrets in GitHub:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `ECR_REGISTRY`
   - `CLOUDFRONT_DISTRIBUTION_ID`
   - `FRONTEND_BUCKET_NAME`
   - `SLACK_WEBHOOK_URL`

2. Enable GitHub Actions workflows

### Backup Configuration

Verify backup jobs are running:

```bash
kubectl get cronjobs -n production
```

## Troubleshooting

### Pods Not Starting

```bash
kubectl describe pod <pod-name> -n production
kubectl logs <pod-name> -n production
```

### Database Connection Issues

```bash
# Test from a pod
kubectl run -it --rm debug --image=mysql:8.0 --restart=Never -- \
  mysql -h <RDS_ENDPOINT> -u admin -p
```

### High Latency

Check service mesh metrics:

```bash
kubectl -n istio-system logs -l app=istio-ingressgateway
```

## Rollback Procedure

If deployment fails:

```bash
# Rollback Kubernetes deployment
kubectl rollout undo deployment/backend-api -n production

# Restore previous S3 version
aws s3 sync s3://<FRONTEND_BUCKET_NAME>-backup/ s3://<FRONTEND_BUCKET_NAME>/

# Invalidate CloudFront
aws cloudfront create-invalidation \
  --distribution-id <CLOUDFRONT_DISTRIBUTION_ID> \
  --paths "/*"
```

## Maintenance Windows

Schedule maintenance during low-traffic periods:

1. Enable maintenance mode
2. Apply updates
3. Run health checks
4. Disable maintenance mode

## Cost Optimization

After deployment, review costs:

```bash
# Get monthly cost estimate
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Security Hardening

Post-deployment security tasks:

1. Enable GuardDuty
2. Configure Security Hub
3. Enable CloudTrail
4. Setup AWS Config rules
5. Enable VPC Flow Logs
6. Configure WAF rules
7. Rotate all secrets

## Support

For issues:
- Check logs: `kubectl logs <pod-name> -n production`
- Review monitoring dashboards
- Contact DevOps team
- Create incident ticket

## Next Steps

1. Configure custom domains
2. Setup additional environments (staging)
3. Enable advanced monitoring
4. Configure backup retention policies
5. Document runbooks
6. Train team on operations
