variable "image_tag" {
  description = "Tag de l'image Docker"
  type        = string
  default     = "latest"
}

variable "app_port" {
  description = "Port expose en staging"
  type        = number
  default     = 8001
}

variable "container_name" {
  description = "Nom du conteneur"
  type        = string
  default     = "sentiment-staging"
}

variable "registry" {
  description = "Registry Docker"
  type        = string
  default     = "ghcr.io/andmadeleine"
}