# main.tf
# Todos los recursos de AWS del laboratorio, en el orden en que "se conectan":
#   1. Datos de consulta (zona de disponibilidad e imagen de Ubuntu)
#   2. Red: VPC -> Internet Gateway -> subred pública -> tabla de rutas
#   3. Firewall: security group (SSH solo desde tu IP)
#   4. Servidor: key pair + instancia EC2

locals {
  # Prefijo para el nombre de todos los recursos (ej: "aws-linux-lab-vpc").
  name = var.project_name
}

# ---------------------------------------------------------------------------
# 1. DATOS (data sources): no crean nada, solo CONSULTAN información a AWS.
# ---------------------------------------------------------------------------

# Zonas de disponibilidad (data centers) activas en la región.
# Usamos la primera para la subred.
data "aws_availability_zones" "available" {
  state = "available"
}

# Busca la imagen (AMI) más reciente de Ubuntu Server 24.04 LTS.
# owners = Canonical (la empresa detrás de Ubuntu): así evitamos usar
# una imagen subida por un desconocido que se llame parecido.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# 2. RED
# ---------------------------------------------------------------------------

# VPC: tu red privada y aislada dentro de AWS.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

# Internet Gateway: la "puerta" entre tu VPC e internet.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-igw" }
}

# Subred pública: un pedazo de la VPC donde vivirá el servidor.
# "Pública" porque su tabla de rutas sale a internet por el Internet Gateway.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true # Las instancias aquí reciben IP pública automáticamente

  tags = { Name = "${local.name}-public-subnet" }
}

# Tabla de rutas: le dice a la subred "todo lo que no sea de la VPC (0.0.0.0/0),
# mándalo al Internet Gateway".
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name}-public-rt" }
}

# Asocia la tabla de rutas con la subred (sin esto, la subred no la usa).
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# 3. FIREWALL
# ---------------------------------------------------------------------------

# Toda VPC trae un security group "default". Lo dejamos SIN reglas para que,
# si algún recurso termina usándolo por error, quede sin acceso en vez de abierto.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-default-sg-sin-reglas" }
}

# Security group del servidor: firewall de AWS delante de la instancia.
# Por defecto bloquea TODO; solo pasa lo que permiten las reglas de abajo.
resource "aws_security_group" "server" {
  name        = "${local.name}-server-sg"
  description = "SSH solo desde la IP del administrador; salida solo HTTP/HTTPS"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-server-sg" }
}

# ENTRADA: SSH (puerto 22) únicamente desde tu IP (/32).
resource "aws_vpc_security_group_ingress_rule" "ssh_admin" {
  security_group_id = aws_security_group.server.id
  description       = "SSH desde la IP del administrador"
  cidr_ipv4         = var.allowed_ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

# SALIDA: solo HTTP y HTTPS, para descargar actualizaciones de Ubuntu.
# (El DNS y la hora de AWS no pasan por el security group, así que siguen funcionando.)
resource "aws_vpc_security_group_egress_rule" "http_out" {
  security_group_id = aws_security_group.server.id
  description       = "HTTP saliente (repositorios apt)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "https_out" {
  security_group_id = aws_security_group.server.id
  description       = "HTTPS saliente (repositorios y actualizaciones)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# ---------------------------------------------------------------------------
# 4. SERVIDOR
# ---------------------------------------------------------------------------

# Sube a AWS tu clave PÚBLICA (el "candado"). La privada nunca sale de tu PC.
resource "aws_key_pair" "admin" {
  key_name   = "${local.name}-key"
  public_key = file(pathexpand(var.public_key_path))
}

resource "aws_instance" "server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.server.id]
  key_name               = aws_key_pair.admin.key_name

  # Script de endurecimiento que corre en el primer arranque (Paso 5).
  # templatefile() le pasa variables de Terraform al script.
  user_data = templatefile("${path.module}/../scripts/user-data.sh", {
    admin_username = var.admin_username
  })
  # Si cambias el script, Terraform reemplaza la instancia para que se vuelva a ejecutar.
  user_data_replace_on_change = true

  # IMDSv2 obligatorio: protege los metadatos de la instancia (y sus credenciales)
  # contra ataques SSRF. Es una recomendación estándar de seguridad de AWS.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Disco: 8 GB gp3 y CIFRADO (el nivel gratuito incluye hasta 30 GB).
  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # Las t3 vienen en modo "unlimited": si usan mucha CPU por mucho tiempo,
  # AWS cobra extra. "standard" lo impide: la instancia se pone lenta, pero no cobra.
  credit_specification {
    cpu_credits = "standard"
  }

  # El monitoreo detallado de CloudWatch tiene costo; el básico es gratis.
  monitoring = false

  tags = { Name = "${local.name}-server" }
}
