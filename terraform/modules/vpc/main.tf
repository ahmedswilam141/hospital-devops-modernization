# =============================================================================
# terraform/modules/vpc/main.tf
#
# WHAT THIS BUILDS:
#   The entire network foundation for the project. Everything else lives inside
#   this VPC. No other module runs until this one succeeds.
#
# ARCHITECTURE:
#
#   VPC: 10.0.0.0/16
#   ├── Public Subnet AZ-a  (10.0.1.0/24)  — ALB, NAT Gateway, Bastion
#   ├── Public Subnet AZ-b  (10.0.2.0/24)  — ALB second AZ (HA)
#   ├── Private Subnet AZ-a (10.0.10.0/24) — EKS nodes, RDS, Redis
#   └── Private Subnet AZ-b (10.0.20.0/24) — EKS nodes, RDS replica (HA)
#
# WHY TWO AZs:
#   AWS requires EKS node groups and RDS Multi-AZ to span at least 2 AZs.
#   If AZ-a goes down, pods reschedule to AZ-b automatically.
#
# WHY PUBLIC/PRIVATE SPLIT:
#   Public: internet-facing resources (ALB receives traffic, Bastion lets you SSH)
#   Private: everything else — no inbound internet access, only outbound via NAT.
#   RDS and Redis are in private subnets and cannot be reached from the internet.
#   This is a real-world security requirement, not just a tutorial best practice.
#
# TRAFFIC FLOW:
#   Internet → ALB (public subnet) → Nginx (EKS, private subnet)
#              → Frontend / Backend pods
#   EKS pods → NAT Gateway (public subnet) → Internet (for apt-get, API calls)
#   Bastion (public) → RDS/Redis (private) via private subnet routing
#
# =============================================================================

# =============================================================================
# VPC
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true   # required for RDS endpoint DNS resolution
  enable_dns_support   = true   # required for EKS internal service discovery

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# =============================================================================
# INTERNET GATEWAY
# Connects the VPC to the internet. Without this, nothing can reach the internet
# and nothing from the internet can reach the VPC (even through the ALB).
# =============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# =============================================================================
# PUBLIC SUBNETS
# Resources here get a public IP and can be reached from the internet.
# Used for: ALB, NAT Gateway, Bastion host.
# =============================================================================

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # Auto-assign public IPv4 to EC2 instances launched here
  # Required for Bastion and NAT Gateway to have reachable IPs
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${var.availability_zones[count.index]}"

    # These tags are REQUIRED for EKS to discover which subnets to use for
    # external load balancers (ALB). Without these tags, the ALB won't deploy.
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
    "kubernetes.io/role/elb"                            = "1"
  }
}

# =============================================================================
# PRIVATE SUBNETS
# Resources here have NO public IP. They can reach the internet via NAT Gateway
# but cannot be reached from the internet directly.
# Used for: EKS worker nodes, RDS, ElastiCache.
# =============================================================================

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # No public IP — private means private
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-${var.availability_zones[count.index]}"

    # Required for EKS to discover which subnets to use for internal load balancers
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
    "kubernetes.io/role/internal-elb"                   = "1"
  }
}

# =============================================================================
# ELASTIC IP FOR NAT GATEWAY
# A NAT Gateway needs a static public IP. Elastic IP gives it one.
# EKS pods use this IP when calling external APIs — appears as one consistent IP.
# =============================================================================

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }

  # EIP must be created after the Internet Gateway exists
  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# NAT GATEWAY
# Sits in the public subnet. Allows private subnet resources to initiate
# outbound internet connections (for package downloads, AWS API calls)
# while blocking all inbound connections.
#
# Why one NAT Gateway: cost. Each NAT Gateway is ~$32/month.
# Production: one per AZ for HA. Graduation project: one is sufficient.
# =============================================================================

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id   # NAT Gateway lives in first public subnet

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# ROUTE TABLE — PUBLIC
# Routes all internet traffic (0.0.0.0/0) through the Internet Gateway.
# Any subnet associated with this table can reach the internet directly.
# =============================================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# ROUTE TABLE — PRIVATE
# Routes all internet traffic through the NAT Gateway (not Internet Gateway).
# Private resources can make outbound calls but are unreachable from outside.
# =============================================================================

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
