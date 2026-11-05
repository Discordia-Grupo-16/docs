variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Región de AWS donde se despliega Discordia"
}

variable "project_name" {
  type        = string
  default     = "discordia"
  description = "Nombre base para los recursos"
}
