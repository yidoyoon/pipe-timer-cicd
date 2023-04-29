variable "env" {
  description = "Environment"
  default     = "staging"
}

variable "region" {
  description = "The region terraform deploys instance"
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
