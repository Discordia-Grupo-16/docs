# Obtenemos dinámicamente tu ID de cuenta de AWS
data "aws_caller_identity" "current" {}

# 1. El Clúster
resource "aws_ecs_cluster" "main" {
  name = "discordia-cluster"
}

# 2. Logs en CloudWatch
resource "aws_cloudwatch_log_group" "gateway_logs" {
  name              = "/ecs/discordia-gateway"
  retention_in_days = 7
}

# 3. Rol de Ejecución (Permisos base)
resource "aws_iam_role" "ecs_execution_role" {
  name = "DiscordiaEcsExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# PERMISO NUEVO: Autorizamos a ECS a leer archivos del bucket de S3
resource "aws_iam_role_policy" "ecs_s3_policy" {
  name = "DiscordiaEcsS3Policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:GetBucketLocation"
      ]
      Resource = [
        aws_s3_bucket.configs.arn,
        "${aws_s3_bucket.configs.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 4. Definición de la Tarea
resource "aws_ecs_task_definition" "gateway" {
  family                   = "discordia-gateway-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "api-gateway"
    image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/discordia-api-gateway:latest"

    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
    }]

    # NUEVO: Fargate va a buscar este archivo exacto a S3 y cargará todas las variables
    environmentFiles = [
      {
        value = "${aws_s3_bucket.configs.arn}/api-gateway.env"
        type  = "s3"
      }
    ]
    secrets = [
      { name = "REDIS_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn },
      { name = "JWT_SECRET", valueFrom = aws_ssm_parameter.jwt_secret.arn }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.gateway_logs.name
        "awslogs-region"        = "${var.aws_region}"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# 5. El Servicio
resource "aws_ecs_service" "gateway" {
  name            = "discordia-gateway-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.gateway.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
    security_groups  = [aws_security_group.gateway_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_gateway.arn
    container_name   = "api-gateway"
    container_port   = 8080
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# Permiso para que las tareas ECS lean secretos de SSM
resource "aws_iam_role_policy" "ecs_ssm_policy" {
  name = "DiscordiaEcsSSMPolicy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "ssm:GetParameters",
        "ssm:GetParameter"
      ]
      Resource = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"]
    }]
  })
}
