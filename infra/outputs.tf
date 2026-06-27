output "staging_url" {
  value = "http://localhost:${var.app_port}"
}

output "container_name" {
  value = docker_container.sentiment_staging.name
}

output "image_name" {
  value = docker_image.sentiment.name
}