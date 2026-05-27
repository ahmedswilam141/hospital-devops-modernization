# =============================================================================
# terraform/modules/redis/main.tf
#
# WHAT THIS BUILDS:
#   - An ElastiCache Redis 7 cluster in a private subnet
#   - A subnet group (same concept as RDS subnet group)
#   - A security group allowing only EKS nodes to connect on port 6379
#
# WHY THIS EXISTS:
#   In Docker Compose, PHP sessions are stored in the redis container.
#   When you move to Kubernetes with multiple frontend pods, each pod has
#   its own memory — a session written on Pod A is not readable on Pod B.
#   Redis solves this by giving every pod a shared external session store.
#   This is the fix you already implemented in php-sessions.ini.
#   ElastiCache is the managed version of that redis container — same protocol,
#   same config, but AWS handles HA, backups, and patching.
#
# =============================================================================

resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Allow Redis access from EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_node_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-redis-sg"
  }
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1           # single node — enough for graduation project
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]

  # Maintenance window — when AWS applies patches
  maintenance_window   = "sun:05:00-sun:06:00"

  tags = {
    Name = "${var.project_name}-redis"
  }
}
