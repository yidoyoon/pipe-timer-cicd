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
