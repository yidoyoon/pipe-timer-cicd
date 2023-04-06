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

