variable "env" {
  description = "Environment"
  default     = "staging"
}

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

variable "region" {
  description = "The region terraform deploys instance"
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

variable "cf_zone_id" {
  description = "The cloudflare zone id"
  type        = string
}

variable "cf_token" {
  description = "The cloudflare api token"
  type        = string
}

variable "host_url" {
  description = "The host base url"
  type        = string
}

variable "upstream_backend" {
  description = "The upstream backend"
  type        = string
}
