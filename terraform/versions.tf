# versions.tf
# Fija qué versiones de Terraform y del provider de AWS acepta el proyecto,
# y configura el provider (a qué región de AWS nos conectamos).

terraform {
  # Versión mínima de Terraform. Evita que alguien use una versión vieja
  # que no entienda la sintaxis del proyecto.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # "~> 6.23" significa: 6.23 o superior, pero menor que 7.0.
      # 6.23 es la primera versión que entiende las credenciales de `aws login`.
      # No aceptamos la 7.x porque un cambio de versión mayor puede romper el código.
      version = "~> 6.23"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Etiquetas que se agregan a TODOS los recursos que cree Terraform.
  # Sirven para saber en la consola qué pertenece a este proyecto
  # y para filtrar costos por proyecto.
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
