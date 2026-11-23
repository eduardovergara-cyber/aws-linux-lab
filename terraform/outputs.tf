# outputs.tf
# Lo que Terraform muestra al terminar `terraform apply`.
# También se puede consultar después con `terraform output`.

output "instance_id" {
  description = "ID de la instancia EC2 (para buscarla en la consola)."
  value       = aws_instance.server.id
}

output "ami_name" {
  description = "Nombre de la imagen de Ubuntu que se usó."
  value       = data.aws_ami.ubuntu.name
}

output "public_ip" {
  description = "IP pública del servidor."
  value       = aws_instance.server.public_ip
}

output "ssh_command" {
  description = "Comando para conectarte (el usuario lo crea user-data.sh en el Paso 5)."
  value       = "ssh -i ~/.ssh/aws-linux-lab ${var.admin_username}@${aws_instance.server.public_ip}"
}
