# aws-linux-lab

> 🚧 Proyecto en construcción.

Servidor Linux endurecido en AWS, creado con Terraform y dentro del nivel gratuito.

## Estructura

```text
aws-linux-lab/
├── terraform/                    # Infraestructura como código
│   ├── versions.tf               # Versiones de Terraform y del provider AWS
│   ├── variables.tf              # Entradas (región, IP permitida, clave pública...)
│   ├── main.tf                   # VPC, subred, security group, EC2
│   ├── outputs.tf                # IP pública y comando SSH
│   └── terraform.tfvars.example  # Plantilla de variables (la real no se sube)
├── scripts/
│   └── user-data.sh              # Endurecimiento del servidor en el primer arranque
├── docs/                         # Diagrama y capturas
├── .gitignore                    # Evita subir estado, claves y variables reales
└── .gitattributes                # Fuerza finales de línea LF en scripts
```

<!-- Las secciones de arquitectura, uso, decisiones de seguridad y aprendizajes
     se agregan cuando estén probadas. -->
