# terraform/modules/rds/variables.tf

variable "project_name"   { type = string }
variable "vpc_id"         { type = string }
variable "subnet_ids"     { type = list(string) }
variable "db_name"        { type = string }
variable "db_username"    { type = string }
variable "instance_class" { type = string }
variable "eks_node_sg_id" { type = string }

variable "db_password" {
  type      = string
  sensitive = true
}
