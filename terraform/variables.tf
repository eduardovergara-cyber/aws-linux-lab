# variables.tf
# Las "entradas" del proyecto. Los valores que tienen `default` se pueden
# dejar tal cual; los que NO tienen default hay que darlos en terraform.tfvars.

variable "aws_region" {
  description = "Región de AWS donde se crea todo."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto. Se usa en los nombres y etiquetas de los recursos."
  type        = string
  default     = "aws-linux-lab"
}

variable "vpc_cidr" {
  description = "Rango de IPs privadas de la VPC (65.536 direcciones con /16)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Rango de IPs de la subred pública, dentro de la VPC (256 direcciones con /24)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "Tamaño de la EC2. t3.micro entra en el nivel gratuito."
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "Tu IP pública en formato CIDR /32 (ej: 203.0.113.10/32). Solo esa IP podrá conectarse por SSH."
  type        = string
  # Sin default a propósito: Terraform te obliga a darla, para que nunca
  # quede abierto a todo internet por olvido.

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0)) && endswith(var.allowed_ssh_cidr, "/32")
    error_message = "allowed_ssh_cidr debe ser UNA sola IP con /32, por ejemplo 203.0.113.10/32. Nunca 0.0.0.0/0."
  }
}

variable "public_key_path" {
  description = "Ruta a tu clave pública SSH (.pub). La privada nunca sale de tu PC."
  type        = string
  default     = "~/.ssh/aws-linux-lab.pub"
}

variable "admin_username" {
  description = "Usuario no root que crea el script de arranque para administrar el servidor."
  type        = string
  default     = "labadmin"
}
