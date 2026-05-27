# terraform/modules/s3/variables.tf

variable "project_name"       { type = string }
variable "eks_node_role_arn"  { type = string }
variable "eks_node_role_name" { type = string }
