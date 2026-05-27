# =============================================================================
# terraform/modules/eks/main.tf
#
# WHAT THIS BUILDS:
#   - EKS Control Plane (the Kubernetes API server — managed by AWS)
#   - EKS Managed Node Group (EC2 instances — your worker nodes)
#   - IAM roles for the cluster and nodes
#   - Security groups for cluster-to-node communication
#   - OIDC provider (enables pods to assume IAM roles — "IRSA")
#   - Core add-ons: CoreDNS, kube-proxy, VPC CNI
#
# WHAT IS EKS:
#   EKS = AWS runs the Kubernetes control plane for you.
#   You don't manage etcd, the API server, or controller-manager.
#   You only manage the worker nodes (EC2 instances where pods run).
#   With Managed Node Groups, AWS even handles node OS patching and replacement.
#
# OIDC + IRSA EXPLAINED:
#   IRSA = IAM Roles for Service Accounts.
#   Problem: pods need AWS credentials to call S3, Secrets Manager, etc.
#   Bad solution: put AWS access keys in pod env vars (leaks if pod is compromised)
#   Good solution: IRSA. The pod is associated with a K8s Service Account.
#   The Service Account is bound to an IAM Role via the OIDC provider.
#   AWS provides temporary credentials automatically — no keys in code.
#   This is how real AWS workloads handle credentials.
#
# =============================================================================

# =============================================================================
# IAM ROLE — EKS CONTROL PLANE
# AWS needs permission to manage EC2, ELB, etc. on your behalf.
# This role is assumed by the EKS service itself, not by your pods.
# =============================================================================

data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.project_name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# =============================================================================
# IAM ROLE — EKS NODE GROUP
# EC2 worker nodes need permissions to: join the cluster, pull ECR images,
# send metrics to CloudWatch, and manage networking via VPC CNI.
# =============================================================================

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${var.project_name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
}

# Required managed policies for EKS worker nodes
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  # VPC CNI: allows the kubelet to manage pod networking (IP allocation)
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.eks_node.name
  # Allows nodes to pull images from ECR
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.eks_node.name
  # SSM allows you to shell into nodes without SSH keys (Session Manager)
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# =============================================================================
# EKS CLUSTER
# =============================================================================

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-cluster"
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = concat(var.private_subnet_ids, var.public_subnet_ids)

    # endpoint_public_access: you can run kubectl from your laptop
    endpoint_public_access  = true
    # endpoint_private_access: pods inside the VPC can reach the API server
    endpoint_private_access = true

    # Restrict kubectl access to your IP only (security best practice)
    # Leave empty to allow all IPs — easier for a graduation project
    # public_access_cidrs = ["YOUR_IP/32"]
  }

  # Enable CloudWatch logging for the control plane
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Name = "${var.project_name}-cluster"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# =============================================================================
# EKS MANAGED NODE GROUP
# EC2 instances that run your pods. "Managed" means AWS handles:
# - Node provisioning and termination
# - Node OS updates (Amazon Linux 2)
# - Graceful pod draining before termination
# =============================================================================

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids   # nodes in private subnets — not internet-facing

  instance_types = [var.node_instance_type]  # t3.small: 2 vCPU, 2GB RAM

  scaling_config {
    desired_size = var.node_desired_count
    min_size     = var.node_min_count
    max_size     = var.node_max_count
  }

  # Rolling update strategy — replaces nodes one at a time, keeping cluster available
  update_config {
    max_unavailable = 1
  }

  # Wait for IAM role policies to be attached before creating the node group
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read_only,
  ]

  tags = {
    Name = "${var.project_name}-node-group"
  }
}

# =============================================================================
# EKS ADD-ONS
# Core Kubernetes functionality that runs as managed components.
# AWS keeps these patched and updated automatically.
# =============================================================================

resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "coredns"
  # CoreDNS: internal DNS for K8s. "frontend-service.hospital.svc.cluster.local"
  # resolves to the frontend Service ClusterIP. Without this, service discovery breaks.

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
  # kube-proxy: manages iptables rules for Service → Pod traffic routing
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  # VPC CNI: assigns real VPC IP addresses to pods (not an overlay network).
  # Each pod gets an IP from your private subnet — pods are first-class VPC citizens.
}

# =============================================================================
# OIDC PROVIDER — enables IRSA (IAM Roles for Service Accounts)
#
# This is what allows a Kubernetes pod to say "I am the backend service account"
# and AWS to respond "OK, here are temporary credentials for the S3 bucket policy
# I have on that service account's IAM role." No static credentials needed.
# =============================================================================

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
