# terraform/modules/rds/outputs.tf

output "endpoint" {
  value = aws_db_instance.main.address
  # Example: hospital-devops-mysql.abc123.us-east-1.rds.amazonaws.com
}

output "port" {
  value = aws_db_instance.main.port
}

output "secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "security_group_id" {
  value = aws_security_group.rds.id
}
