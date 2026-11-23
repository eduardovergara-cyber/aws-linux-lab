#!/bin/bash
# =============================================================================
# user-data.sh — Endurecimiento inicial del servidor (Ubuntu 24.04)
#
# AWS ejecuta este script UNA sola vez, como root, en el primer arranque
# (a través de cloud-init). Terraform lo carga con templatefile(), que
# reemplaza las variables con formato $ + {nombre} antes de enviarlo a AWS.
#
# Pasos:
#   1. Actualizar el sistema
#   2. Crear un usuario administrador no root
#   3. Endurecer SSH
#   4. Activar el firewall (ufw)
#   5. Activar actualizaciones de seguridad automáticas
#
# Registro de ejecución dentro del servidor: /var/log/user-data.log
# =============================================================================

# -e: detenerse ante cualquier error | -u: error si se usa una variable no definida
# -o pipefail: un error en medio de un "|" también cuenta como error
set -euo pipefail

# Todo lo que imprima el script (salida y errores) queda guardado en el log.
exec > >(tee -a /var/log/user-data.log) 2>&1
echo "=== Inicio del endurecimiento: $(date -Is) ==="

# Valor que inyecta Terraform (variable admin_username).
ADMIN_USER="${admin_username}"

# Evita que apt se quede esperando respuestas en pantalla (nadie va a contestar).
export DEBIAN_FRONTEND=noninteractive
APT_OPTS='-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'

# -----------------------------------------------------------------------------
# 1. Actualizar el sistema
#    Cierra vulnerabilidades conocidas que vengan en la imagen base.
# -----------------------------------------------------------------------------
echo "--- [1/5] Actualizando paquetes"
apt-get update
apt-get $APT_OPTS upgrade
apt-get $APT_OPTS install ufw unattended-upgrades

# -----------------------------------------------------------------------------
# 2. Usuario administrador no root
#    Nadie trabaja como root: se entra con este usuario y se usa sudo
#    solo cuando hace falta (y queda registrado en /var/log/auth.log).
# -----------------------------------------------------------------------------
echo "--- [2/5] Creando usuario $ADMIN_USER"
if ! id "$ADMIN_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --groups sudo "$ADMIN_USER"
fi

# Sin contraseña: la cuenta queda bloqueada para login con password.
# Solo se puede entrar con la clave SSH.
passwd -l "$ADMIN_USER"

# Copiamos la clave pública que AWS instaló en el usuario por defecto (ubuntu).
install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "/home/$ADMIN_USER/.ssh"
install -m 600 -o "$ADMIN_USER" -g "$ADMIN_USER" \
  /home/ubuntu/.ssh/authorized_keys "/home/$ADMIN_USER/.ssh/authorized_keys"

# sudo sin contraseña (el usuario no tiene contraseña). Es lo mismo que hace
# AWS con el usuario "ubuntu". Se valida con visudo antes de dejarlo activo:
# un error de sintaxis en sudoers podría dejarnos sin sudo.
SUDOERS_FILE="/etc/sudoers.d/90-$ADMIN_USER"
echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE"

# -----------------------------------------------------------------------------
# 3. Endurecer SSH
#    Se usa un archivo aparte en sshd_config.d/ en vez de editar el original.
#    Se llama "00-..." porque en sshd GANA LA PRIMERA definición que encuentra,
#    y los archivos se leen en orden alfabético (así va antes que 50-cloud-init.conf).
# -----------------------------------------------------------------------------
echo "--- [3/5] Endureciendo SSH"
SSHD_HARDENING="/etc/ssh/sshd_config.d/00-hardening.conf"
cat > "$SSHD_HARDENING" <<EOF
# Gestionado por user-data.sh (aws-linux-lab)
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
AuthenticationMethods publickey
AllowUsers $ADMIN_USER
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
LogLevel VERBOSE
EOF
chmod 644 "$SSHD_HARDENING"

# Validar la configuración ANTES de reiniciar. Si tiene un error, se borra
# el archivo para no dejar SSH roto (y quedarnos sin acceso al servidor).
# En Ubuntu 24.04 sshd arranca "a demanda" (ssh.socket) y puede faltar
# /run/sshd, que `sshd -t` necesita para validar.
mkdir -p /run/sshd
if sshd -t; then
  systemctl restart ssh
else
  echo "ERROR: configuración SSH inválida; se descarta $SSHD_HARDENING"
  rm -f "$SSHD_HARDENING"
  exit 1
fi

# -----------------------------------------------------------------------------
# 4. Firewall del sistema operativo (ufw)
#    Segunda capa además del security group de AWS (defensa en profundidad):
#    si alguien abre por error el security group, el servidor sigue protegido.
# -----------------------------------------------------------------------------
echo "--- [4/5] Configurando ufw"
ufw default deny incoming
ufw default allow outgoing   # La salida ya la restringe el security group (80/443)
ufw limit 22/tcp comment 'SSH con limite de intentos'
ufw --force enable

# -----------------------------------------------------------------------------
# 5. Actualizaciones de seguridad automáticas
# -----------------------------------------------------------------------------
echo "--- [5/5] Activando unattended-upgrades"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo "=== Endurecimiento terminado: $(date -Is) ==="
if [ -f /var/run/reboot-required ]; then
  echo "AVISO: hay actualizaciones que requieren reiniciar (sudo reboot)."
fi
