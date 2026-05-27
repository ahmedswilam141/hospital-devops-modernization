# terraform/modules/bastion/variables.tf
variable "project_name"     { type = string }
variable "vpc_id"           { type = string }
variable "public_subnet_id" { type = string }
variable "my_ip_cidr"       { type = string }
variable "instance_type"    { type = string }
