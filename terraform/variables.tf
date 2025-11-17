variable "username" {
  description = "VK Cloud username"
  type        = string
}

variable "password" {
  description = "VK Cloud password"
  type        = string
  sensitive   = true
}

variable "project_id" {
  description = "Project ID"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
  default     = "ME1"
}

variable "ssh_key_name" {
  description = "Name of SSH key pair in VK Cloud"
  type        = string
}
