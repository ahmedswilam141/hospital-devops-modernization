#!/bin/bash
# =============================================================================
# scripts/deploy-phase2.sh
#
# WHAT THIS IS:
#   A step-by-step deployment runbook for Phase 2.
#   Run each section manually — do NOT run the whole script at once.
#   Read the comments before running each command.
#
# USAGE:
#   Read through this file, understand each step, then run commands manually.
#   This file documents every command you need to deploy Phase 2 in order.
# =============================================================================

set -euo pipefail   # exit on error, undefined variable, pipe failure

# ============================================================================
# CONFIGURATION — set these before running anything
# ============================================================================

PROJECT_NAME="hospital-devops"
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_FRONTEND="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-frontend"
ECR_BACKEND="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-backend"
ECR_NGINX="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-nginx"
EKS_CLUSTER="${PROJECT_NAME}-cluster"

echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "ECR Frontend: ${ECR_FRONTEND}"
echo "ECR Backend:  ${ECR_BACKEND}"
echo ""

# ============================================================================
# STEP 1 — Terraform remote state (run ONCE before terraform init)
# ============================================================================
step1_remote_state() {
  echo "=== STEP 1: Create Terraform remote state backend ==="

  BUCKET_NAME="${PROJECT_NAME}-tfstate-$(whoami)"

  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${AWS_REGION}"

  aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

  aws dynamodb create-table \
    --table-name "${PROJECT_NAME}-tflock" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}"

  echo "✅ Remote state backend created: ${BUCKET_NAME}"
  echo "⚠️  Update terraform/backend.tf with bucket name: ${BUCKET_NAME}"
}

# ============================================================================
# STEP 2 — Terraform apply
# ============================================================================
step2_terraform() {
  echo "=== STEP 2: Apply Terraform ==="

  # Get your public IP for bastion security group
  MY_IP=$(curl -s https://checkip.amazonaws.com)/32
  echo "Your IP: ${MY_IP}"

  cd terraform/

  terraform init
  terraform validate
  terraform plan -var="db_password=YourSecurePassword123!" -var="my_ip_cidr=${MY_IP}"

  echo "Review the plan above. Type 'yes' when ready:"
  terraform apply -var="db_password=YourSecurePassword123!" -var="my_ip_cidr=${MY_IP}"

  # Save outputs for later steps
  terraform output -json > /tmp/tf-outputs.json
  echo "✅ Terraform outputs saved to /tmp/tf-outputs.json"

  cd ..
}

# ============================================================================
# STEP 3 — Build and push Docker images to ECR
# ============================================================================
step3_push_images() {
  echo "=== STEP 3: Push Docker images to ECR ==="

  # Authenticate Docker to ECR
  aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin \
    "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

  # Build images (they should already exist from Phase 1)
  docker-compose build

  # Tag images for ECR
  docker tag hospital-devops-frontend:latest "${ECR_FRONTEND}:latest"
  docker tag hospital-devops-backend:latest  "${ECR_BACKEND}:latest"
  docker tag hospital-devops-nginx:latest    "${ECR_NGINX}:latest"

  # Push to ECR
  docker push "${ECR_FRONTEND}:latest"
  docker push "${ECR_BACKEND}:latest"
  docker push "${ECR_NGINX}:latest"

  echo "✅ Images pushed to ECR"
}

# ============================================================================
# STEP 4 — Configure kubectl to connect to EKS
# ============================================================================
step4_kubectl_config() {
  echo "=== STEP 4: Connect kubectl to EKS ==="

  aws eks update-kubeconfig \
    --name "${EKS_CLUSTER}" \
    --region "${AWS_REGION}"

  kubectl get nodes
  echo "✅ kubectl connected to EKS"
}

# ============================================================================
# STEP 5 — Run Ansible against bastion
# ============================================================================
step5_ansible() {
  echo "=== STEP 5: Configure bastion with Ansible ==="

  BASTION_IP=$(cat /tmp/tf-outputs.json | jq -r '.bastion_public_ip.value')
  echo "Bastion IP: ${BASTION_IP}"

  # Update inventory
  sed -i "s/BASTION_PUBLIC_IP/${BASTION_IP}/" ansible/inventory.ini

  ansible-playbook \
    -i ansible/inventory.ini \
    ansible/playbook-bastion.yml \
    -v

  echo "✅ Bastion configured"
}

# ============================================================================
# STEP 6 — Update K8s manifests with real Terraform output values
# ============================================================================
step6_update_manifests() {
  echo "=== STEP 6: Update K8s manifests with Terraform outputs ==="

  RDS_ENDPOINT=$(cat /tmp/tf-outputs.json | jq -r '.rds_endpoint.value')
  REDIS_ENDPOINT=$(cat /tmp/tf-outputs.json | jq -r '.redis_endpoint.value')
  S3_BUCKET=$(cat /tmp/tf-outputs.json | jq -r '.s3_bucket_name.value')

  echo "RDS:   ${RDS_ENDPOINT}"
  echo "Redis: ${REDIS_ENDPOINT}"
  echo "S3:    ${S3_BUCKET}"

  # Replace placeholders in ConfigMaps
  sed -i "s|REPLACE_WITH_RDS_ENDPOINT|${RDS_ENDPOINT}|g" k8s/frontend/configmap.yaml
  sed -i "s|REPLACE_WITH_REDIS_ENDPOINT|${REDIS_ENDPOINT}|g" k8s/frontend/configmap.yaml
  sed -i "s|REPLACE_WITH_S3_BUCKET_NAME|${S3_BUCKET}|g" k8s/frontend/configmap.yaml

  sed -i "s|REPLACE_WITH_RDS_ENDPOINT|${RDS_ENDPOINT}|g" k8s/backend/deployment.yaml
  sed -i "s|REPLACE_WITH_REDIS_ENDPOINT|${REDIS_ENDPOINT}|g" k8s/backend/deployment.yaml
  sed -i "s|REPLACE_WITH_S3_BUCKET_NAME|${S3_BUCKET}|g" k8s/backend/deployment.yaml

  # Replace ACCOUNT_ID in image references
  sed -i "s|ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" k8s/frontend/deployment.yaml
  sed -i "s|ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" k8s/backend/deployment.yaml
  sed -i "s|ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" k8s/nginx/deployment.yaml

  echo "✅ Manifests updated"
}

# ============================================================================
# STEP 7 — Run database migration against RDS via bastion SSH tunnel
# ============================================================================
step7_db_migration() {
  echo "=== STEP 7: Database migration ==="

  BASTION_IP=$(cat /tmp/tf-outputs.json | jq -r '.bastion_public_ip.value')
  RDS_ENDPOINT=$(cat /tmp/tf-outputs.json | jq -r '.rds_endpoint.value')

  # Copy schema to bastion
  scp -i ~/.ssh/hospital-key.pem \
    -o StrictHostKeyChecking=no \
    scripts/schema.sql \
    "ec2-user@${BASTION_IP}:~/schema.sql"

  # Run migration via bastion (RDS is in private subnet — only reachable from VPC)
  echo "Running migration against RDS..."
  ssh -i ~/.ssh/hospital-key.pem \
    -o StrictHostKeyChecking=no \
    "ec2-user@${BASTION_IP}" \
    "mysql -h ${RDS_ENDPOINT} -u admin -pYourSecurePassword123! hospital < ~/schema.sql"

  echo "✅ Database migrated to RDS"
}

# ============================================================================
# STEP 8 — Apply Kubernetes manifests
# ============================================================================
step8_apply_k8s() {
  echo "=== STEP 8: Apply Kubernetes manifests ==="

  # Apply in dependency order
  kubectl apply -f k8s/namespaces/
  sleep 3

  kubectl apply -f k8s/secrets/
  sleep 5

  kubectl apply -f k8s/frontend/configmap.yaml
  kubectl apply -f k8s/frontend/deployment.yaml
  kubectl apply -f k8s/frontend/service.yaml

  kubectl apply -f k8s/backend/deployment.yaml

  kubectl apply -f k8s/nginx/deployment.yaml

  # Wait for pods to be ready
  echo "Waiting for pods to be ready..."
  kubectl wait --for=condition=ready pod \
    -l app=frontend -n hospital \
    --timeout=180s

  kubectl wait --for=condition=ready pod \
    -l app=backend -n hospital \
    --timeout=180s

  kubectl wait --for=condition=ready pod \
    -l app=nginx -n hospital \
    --timeout=180s

  echo "✅ All pods are ready"
}

# ============================================================================
# STEP 9 — Verify everything is working
# ============================================================================
step9_verify() {
  echo "=== STEP 9: Verification ==="

  kubectl get pods -n hospital
  kubectl get services -n hospital
  kubectl get hpa -n hospital

  # Get the ALB DNS name
  ALB_DNS=$(kubectl get service nginx -n hospital \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

  echo ""
  echo "Waiting for ALB DNS to resolve (this takes 2-3 minutes)..."
  sleep 60

  echo "Testing health endpoints..."
  curl -f "http://${ALB_DNS}/nginx-health" && echo " ✅ nginx-health OK"
  curl -f "http://${ALB_DNS}/health.php" && echo " ✅ frontend health.php OK"
  curl -f "http://${ALB_DNS}/admin/health.php" && echo " ✅ backend health.php OK"

  echo ""
  echo "=============================================="
  echo "🎉 Phase 2 complete!"
  echo "Live URL: http://${ALB_DNS}"
  echo "=============================================="
}

# ============================================================================
# DESTROY (saves money — run at end of each work session)
# Your state is safe in S3. terraform apply recreates everything.
# ============================================================================
destroy() {
  echo "=== DESTROY: Removing all AWS resources ==="
  echo "⚠️  This will delete all infrastructure. State is safe in S3."
  echo "    Run 'terraform apply' again to recreate."

  kubectl delete namespace hospital --ignore-not-found=true

  cd terraform/
  terraform destroy
  cd ..
}

# ============================================================================
# MAIN — run specific steps or all
# ============================================================================
case "${1:-help}" in
  step1)  step1_remote_state ;;
  step2)  step2_terraform ;;
  step3)  step3_push_images ;;
  step4)  step4_kubectl_config ;;
  step5)  step5_ansible ;;
  step6)  step6_update_manifests ;;
  step7)  step7_db_migration ;;
  step8)  step8_apply_k8s ;;
  step9)  step9_verify ;;
  destroy) destroy ;;
  *)
    echo "Usage: $0 <step1|step2|step3|step4|step5|step6|step7|step8|step9|destroy>"
    echo ""
    echo "Steps:"
    echo "  step1  — Create S3 + DynamoDB for Terraform remote state"
    echo "  step2  — Run terraform apply (provisions all AWS infrastructure)"
    echo "  step3  — Build + push Docker images to ECR"
    echo "  step4  — Connect kubectl to EKS cluster"
    echo "  step5  — Run Ansible against bastion"
    echo "  step6  — Fill in Terraform output values in K8s manifests"
    echo "  step7  — Run database migration against RDS"
    echo "  step8  — Apply all Kubernetes manifests"
    echo "  step9  — Verify everything is healthy + print live URL"
    echo "  destroy — Remove all AWS resources (saves money)"
    ;;
esac
