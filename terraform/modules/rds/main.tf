# =============================================================================
# terraform/modules/rds/main.tf
#
# WHAT THIS BUILDS:
#   - A MySQL 8.0 managed database (RDS) in a private subnet
#   - A DB subnet group (tells RDS which subnets it can use)
#   - A security group (controls which resources can connect on port 3306)
#   - An AWS Secrets Manager secret (stores credentials securely)
#
# WHY RDS INSTEAD OF THE MYSQL CONTAINER:
#   The mysql container in docker-compose stores data on a Docker volume — if
#   the node dies, data dies with it. RDS is managed by AWS: automated backups,
#   point-in-time recovery, patching, Multi-AZ failover. In production, you never
#   run your own database on a container without a persistent volume strategy.
#
# SECRETS MANAGER INTEGRATION:
#   The DB password is stored in Secrets Manager, not in environment variables
#   or K8s secrets (which are only base64-encoded, not encrypted).
#   K8s pods retrieve the password at runtime via the External Secrets Operator.
#   This is the production-correct credential management pattern.
#
# =============================================================================

# =============================================================================
# SECURITY GROUP — controls who can reach RDS on port 3306
# =============================================================================

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow MySQL access from EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from EKS nodes"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.eks_node_sg_id]
    # Only EKS nodes can connect. Not the internet. Not even the bastion by default.
    # To connect from bastion: add bastion SG here, or use SSH tunnel.
  }

  # Also allow from bastion for migration and debugging
  ingress {
    description = "MySQL from Bastion (for migration and debugging)"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]   # entire VPC — tighten to bastion IP if preferred
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# =============================================================================
# DB SUBNET GROUP
# Tells RDS which subnets it can deploy into.
# Must span at least 2 AZs even if you're not using Multi-AZ — AWS requirement.
# =============================================================================

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# =============================================================================
# RDS INSTANCE — MySQL 8.0
# =============================================================================

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-mysql"

  # Engine
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.instance_class

  # Storage
  allocated_storage     = 20      # GB — minimum for MySQL
  max_allocated_storage = 100     # GB — auto-scales up to this if needed
  storage_type          = "gp2"   # General Purpose SSD

  # Credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false   # never expose DB to internet

  # Backup & Recovery
  backup_retention_period = 0   
  backup_window           = "03:00-04:00"   # UTC — run backups at 3 AM
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Performance & Reliability
  multi_az               = false   # true = ~2x cost; fine for graduation project
  deletion_protection    = false   # set to true in real production
  skip_final_snapshot    = true    # set to false in real production

  # Parameter group for UTF8MB4 support (emoji, multilingual patient names)
  parameter_group_name = aws_db_parameter_group.main.name

  tags = {
    Name = "${var.project_name}-mysql"
  }
}

resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-mysql-params"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }
}

# =============================================================================
# SECRETS MANAGER — stores DB credentials for K8s pods to retrieve at runtime
#
# Why not K8s Secrets?
#   K8s Secrets are base64-encoded, not encrypted. Anyone with kubectl access
#   can decode them. Secrets Manager encrypts with KMS, has rotation support,
#   and provides an audit trail via CloudTrail. This is the production pattern.
# =============================================================================

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/db-credentials"
  description             = "MySQL credentials for the hospital application"
  recovery_window_in_days = 0   # allow immediate deletion (graduation project)
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.main.address
    port     = 3306
    dbname   = var.db_name
  })
}
