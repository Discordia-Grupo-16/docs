resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name        = "/${var.project_name}/db_password"
  description = "Contraseña maestra para bases de datos"
  type        = "SecureString"
  value       = random_password.db_password.result
}

resource "aws_ssm_parameter" "mongo_uri" {
  name        = "/${var.project_name}/mongo_uri"
  description = "URI de conexión completa para MongoDB (Chat)"
  type        = "SecureString"
  value       = "mongodb://root:${random_password.db_password.result}@mongo.discordia.local:27017/?authSource=admin"
}

resource "aws_ssm_parameter" "rabbitmq_url" {
  name        = "/${var.project_name}/rabbitmq_url"
  description = "URL de conexión completa para RabbitMQ (Chat)"
  type        = "SecureString"
  value       = "amqp://discordia:${random_password.db_password.result}@rabbitmq.discordia.local:5672/"
}

resource "aws_ssm_parameter" "community_db_url" {
  name        = "/${var.project_name}/community_db_url"
  description = "URL de conexión completa para PostgreSQL (Community)"
  type        = "SecureString"
  value       = "postgresql+psycopg://discordia_user:${random_password.db_password.result}@postgres-community.discordia.local:5432/discordia_community"
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = true
}

resource "aws_ssm_parameter" "jwt_secret" {
  name        = "/${var.project_name}/jwt_secret"
  description = "Clave secreta para firmar tokens JWT"
  type        = "SecureString"
  value       = random_password.jwt_secret.result
}
