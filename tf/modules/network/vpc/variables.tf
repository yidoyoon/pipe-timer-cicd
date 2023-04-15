variable "cidr_vpc" {
  description = "CIDR block for the VPC"
  default     = "172.31.0.0/16"
}

variable "cidr_subnet_1" {
  description = "CIDR block for the subnet"
  default     = "172.31.0.0/18"
}

variable "cidr_subnet_2" {
  description = "CIDR block for the subnet"
  default     = "172.31.64.0/18"
}
