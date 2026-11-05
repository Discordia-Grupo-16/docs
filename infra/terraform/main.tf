terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "produccion"
      ManagedBy   = "Terraform"
    }
  }
}

# Repositorios en Elastic Container Registry (ECR)
resource "aws_ecr_repository" "gateway" {
  name                 = "discordia-api-gateway"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "identity" {
  name                 = "discordia-identity"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "community" {
  name                 = "discordia-community"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "chat" {
  name                 = "discordia-chat"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

output "ecr_registry_url" {
  value = split("/", aws_ecr_repository.gateway.repository_url)[0]
}