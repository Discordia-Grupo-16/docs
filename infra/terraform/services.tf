# ==========================================
# MICROSERVICIO: IDENTITY (Python - Puerto 8080)
# ==========================================
resource "aws_cloudwatch_log_group" "identity_logs" {
  name              = "/ecs/discordia-identity"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "identity" {
  family                   = "discordia-identity"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "identity"
    # Busca la imagen en tu ECR
    image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/discordia-identity:latest"
    portMappings = [{ containerPort = 8080, hostPort = 8080 }]

    # Chupa su propio archivo .env desde S3
    environmentFiles = [{
      value = "${aws_s3_bucket.configs.arn}/identity.env"
      type  = "s3"
    }]
    secrets = [
      { name = "DATABASE_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn },
      { name = "REDIS_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn },
      { name = "JWT_SECRET_KEY", valueFrom = aws_ssm_parameter.jwt_secret.arn }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.identity_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "identity" {
  name            = "discordia-identity-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.identity.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
    # Usamos el Security Group aislado creado en security.tf
    security_groups  = [aws_security_group.internal_services_sg.id]
    assign_public_ip = true
  }

  service_registries {
    # Lo atamos al DNS interno identity.discordia.local
    registry_arn = aws_service_discovery_service.internal_services["identity"].arn
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ==========================================
# MICROSERVICIO: CHAT (Go - Puerto 8080)
# ==========================================
resource "aws_cloudwatch_log_group" "chat_logs" {
  name              = "/ecs/discordia-chat"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "chat" {
  family                   = "discordia-chat"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "chat"
    image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/discordia-chat:latest"

    portMappings = [{ containerPort = 8080, hostPort = 8080 }]

    environmentFiles = [{
      value = "${aws_s3_bucket.configs.arn}/chat.env"
      type  = "s3"
    }]

    secrets = [
      { name = "MONGO_URI", valueFrom = aws_ssm_parameter.mongo_uri.arn },
      { name = "RABBITMQ_URL", valueFrom = aws_ssm_parameter.rabbitmq_url.arn }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.chat_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "chat" {
  name            = "discordia-chat-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.chat.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
    security_groups  = [aws_security_group.internal_services_sg.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.internal_services["chat"].arn
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_cloudwatch_log_group" "community_logs" {
  name              = "/ecs/discordia-community"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "community" {
  family                   = "discordia-community"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "community"
    image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/discordia-community:latest"

    portMappings = [{ containerPort = 8000, hostPort = 8000 }]

    environmentFiles = [{
      value = "${aws_s3_bucket.configs.arn}/community.env"
      type  = "s3"
    }]

    secrets = [
      { name = "DATABASE_URL", valueFrom = aws_ssm_parameter.community_db_url.arn },
      { name = "RABBITMQ_URL", valueFrom = aws_ssm_parameter.rabbitmq_url.arn }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.community_logs.name
        "awslogs-region"        = "${var.aws_region}"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "community" {
  name            = "discordia-community-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.community.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
    security_groups  = [aws_security_group.internal_services_sg.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.internal_services["community"].arn
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}
