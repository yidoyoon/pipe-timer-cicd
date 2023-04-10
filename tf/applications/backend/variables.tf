variable "cidr_vpc" {
  description = "CIDR block for the VPC"
  default     = "172.31.0.0/16"
}
variable "cidr_subnet" {
  description = "CIDR block for the subnet"
  default     = "172.31.0.0/20"
}

variable "environment_tag" {
  description = "Environment tag"
  default     = "staging"
}

variable "region" {
  description = "The region Terraform deploys your instance"
}

variable "registry_url" {
  description = "The docker registry url"
  type        = string
}

variable "registry_id" {
  description = "The docker registry username"
  type        = string
}

variable "registry_password" {
  description = "The docker registry password"
  type        = string
}

variable "cicd_path" {
  description = "The cicd path"
  type        = string
}

variable "mysql_db_name" {
  description = "The mysql db name"
  type        = string
}

variable "mysql_username" {
  description = "The mysql username"
  type        = string
}

variable "mysql_password" {
  description = "The mysql password"
  type        = string
}
