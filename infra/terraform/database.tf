# Log Group unificado para bases de datos
resource "aws_cloudwatch_log_group" "databases_logs" {
  name              = "/ecs/discordia-databases"
  retention_in_days = 7
}

# --- REDIS ---
resource "aws_ecs_task_definition" "redis" {
  family                   = "discordia-redis"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "redis"
    image = "redis:alpine"
    portMappings = [{ containerPort = 6379, hostPort = 6379 }]
    secrets = [
      { name = "REDIS_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn }
    ]
    command = ["sh", "-c", "exec redis-server --requirepass \"$REDIS_PASSWORD\""]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.databases_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "redis" {
  name            = "discordia-redis-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.redis.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
    security_groups  = [aws_security_group.databases_sg.id]
    assign_public_ip = true # Necesario para descargar la imagen de Docker Hub
  }

  service_registries {
    registry_arn = aws_service_discovery_service.internal_services["redis"].arn
  }
}

# --- POSTGRES ---
resource "aws_ecs_task_definition" "postgres" {
  family                   = "discordia-postgres"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "postgres"
    image = "postgres:15-alpine"
    portMappings = [{ containerPort = 5432, hostPort = 5432 }]
    environment = [
      { name = "POSTGRES_USER", value = "discordia_user" },
      { name = "POSTGRES_DB", value = "discordia_identity" }
    ]
    secrets = [
      { name = "POSTGRES_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn}
  ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.databases_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "postgres" {
  name            = "discordia-postgres-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.postgres.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
    security_groups  = [aws_security_group.databases_sg.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.internal_services["postgres"].arn
  }
}

# --- MONGO ---
resource "aws_ecs_task_definition" "mongo" {
  family                   = "discordia-mongo"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "mongo"
    image = "mongo:7.0"
    portMappings = [{ containerPort = 27017, hostPort = 27017 }]
    environment = [
      { name = "MONGO_INITDB_ROOT_USERNAME", value = "root" },
    ]
    secrets = [
      { name = "MONGO_INITDB_ROOT_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.databases_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "mongo" {
  name            = "discordia-mongo-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.mongo.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
    security_groups  = [aws_security_group.databases_sg.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.internal_services["mongo"].arn
  }
}

# --- RABBITMQ ---
resource "aws_ecs_task_definition" "rabbitmq" {
  family                   = "discordia-rabbitmq"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "rabbitmq"
    # Usamos la versión con 'management' para tener la UI de administración
    image = "rabbitmq:3-management-alpine"
    portMappings = [
      { containerPort = 5672, hostPort = 5672 },   # Puerto AMQP
      { containerPort = 15672, hostPort = 15672 }  # Puerto UI
    ]
    environment = [
      { name = "RABBITMQ_DEFAULT_USER", value = "discordia" }
    ]
    secrets = [
      { name = "RABBITMQ_DEFAULT_PASS", valueFrom = aws_ssm_parameter.db_password.arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.databases_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
}])
}

resource "aws_ecs_service" "rabbitmq" {
  name            = "discordia-rabbitmq-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.rabbitmq.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
    security_groups  = [aws_security_group.databases_sg.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.internal_services["rabbitmq"].arn
  }
}

# --- POSTGRES PARA COMMUNITY ---
resource "aws_ecs_task_definition" "postgres_community" {
  family                   = "discordia-postgres-community"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "postgres"
    image = "postgres:15-alpine"
    portMappings = [{ containerPort = 5432, hostPort = 5432 }]
    environment = [
      { name = "POSTGRES_USER", value = "discordia_user" },
      { name = "POSTGRES_DB", value = "discordia_community" }
    ]
    secrets = [
      { name = "POSTGRES_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.databases_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "postgres_community" {
  name            = "discordia-postgres-community-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.postgres_community.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
    security_groups  = [aws_security_group.databases_sg.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.internal_services["postgres-community"].arn
  }
}
