# Proveedor OIDC de GitHub
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1", # CA 1
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd", # CA 2
    "1b511abead59c6ce207077c0bf0e0043b1382612", # CA 3 (Nuevo Root)
    "ab9d0263244dd0326eb67015705a667e79cfe998"  # Leaf certificate
  ]
}

# Rol que asumirá GitHub Actions
resource "aws_iam_role" "github_actions_role" {
  name = "DiscordiaDeployRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub": [
            "repo:Discordia-Grupo-16@324703434/*"
          ]
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }]
  })
}

# Permisos para subir imágenes a ECR
resource "aws_iam_role_policy_attachment" "ecr_power_user" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy" "ecs_deploy_policy" {
  name = "DiscordiaECSDeployPolicy"
  role = aws_iam_role.github_actions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        # Esto le permite actualizar los servicios del clúster
        Resource = "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.main.name}/*"
      }
    ]
  })
}

output "github_role_arn" {
  value = aws_iam_role.github_actions_role.arn
}