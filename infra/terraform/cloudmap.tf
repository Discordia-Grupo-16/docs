resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = "discordia.local"
  description = "DNS interno para microservicios de Discordia"
  vpc         = aws_vpc.main.id
}

locals {
  internal_dns_names = [
    "postgres", "postgres-community", "mongo", "redis", "rabbitmq",
    "identity", "community", "chat"
  ]
}

resource "aws_service_discovery_service" "internal_services" {
  for_each = toset(local.internal_dns_names)
  name     = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  lifecycle {
    ignore_changes = [
      health_check_custom_config
    ]
  }
}