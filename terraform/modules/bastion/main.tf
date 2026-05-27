# =============================================================================
# terraform/modules/bastion/main.tf
#
# WHAT THIS BUILDS:
#   - One EC2 instance (t3.micro) in the public subnet
#   - A security group allowing SSH only from your IP
#   - An IAM instance profile with SSM (alternative SSH via browser)
#
# WHY BASTION:
#   RDS and Redis are in private subnets — not reachable from your laptop directly.
#   The bastion is a "jump box": you SSH into it, then connect to RDS from there.
#
#   Use cases:
#   1. Run the database migration (schema.sql) against RDS
#   2. Debug Redis connection issues
#   3. Emergency database access without exposing RDS to the internet
#   4. Ansible target — playbook configures the bastion itself
#
# HOW TO USE:
#   SSH tunnel to RDS:
#     ssh -i hospital-key.pem -L 3307:<rds-endpoint>:3306 ec2-user@<bastion-ip>
#     mysql -h 127.0.0.1 -P 3307 -u admin -p hospital < scripts/schema.sql
#
#   Direct shell:
#     ssh -i hospital-key.pem ec2-user@<bastion-ip>
#
# =============================================================================

# Find the latest Amazon Linux 2 AMI — maintained by AWS, free to use
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg"
  description = "Allow SSH from your IP only"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from your IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
    # Only your IP can SSH in. No 0.0.0.0/0 — that is never acceptable.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    # Bastion needs outbound to reach RDS, Redis, and the internet for yum updates
  }

  tags = {
    Name = "${var.project_name}-bastion-sg"
  }
}

resource "aws_iam_role" "bastion" {
  name = "${var.project_name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project_name}-bastion-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  # You must create this key pair in EC2 console first:
  #   EC2 → Key Pairs → Create key pair → hospital-key → download .pem
  key_name               = "${var.project_name}-key"

  # Bootstrap: install mysql client so you can run migrations from the bastion
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y mysql
    # mysql client lets you: mysql -h <rds-endpoint> -u admin -p hospital < schema.sql
  EOF

  tags = {
    Name = "${var.project_name}-bastion"
  }
}
