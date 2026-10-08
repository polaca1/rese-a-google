#!/bin/bash
# Owner runs this once; accounts remain intact when rerunning the installer.
set -euo pipefail
umask 022
trap 'printf "\nNo se ha completado la instalación. Conservamos las cuentas existentes. Revisa el mensaje anterior y vuelve a ejecutar el instalador.\n" >&2' ERR
if [ "$(id -u)" -ne 0 ]; then
    printf 'Abre una terminal y ejecuta: sudo bash seguido de la ruta de este archivo.\n' >&2
    exit 1
fi
task_source="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
task_local_only=false
if [ "${1:-}" = --local-only ]; then task_local_only=true
elif [ "$#" -ne 0 ]; then printf 'Opción desconocida.\n' >&2; exit 1; fi
if [ "$(dpkg --print-architecture)" != amd64 ]; then
    printf 'Este paquete está preparado para Intel/AMD de 64 bits (amd64).\n' >&2
    exit 1
fi
. /etc/os-release
case "$ID:${VERSION_CODENAME:-}" in
    debian:trixie|debian:bookworm|ubuntu:noble|ubuntu:jammy) ;;
    *) printf 'Usa Debian 13/12 o Ubuntu 24.04/22.04.\n' >&2; exit 1 ;;
esac
for task_file in app.py runtime.py requirements.txt action.py Configurar.py reviewnfcgo-cuentas.service; do
    test -f "$task_source/$task_file"
done
export DEBIAN_FRONTEND=noninteractive
printf '\n1/4 Preparando dependencias ligeras…\n'
apt-get update -qq
apt-get install -y --no-install-recommends python3 python3-venv python3-tk curl ca-certificates polkitd pkexec unattended-upgrades
if ! id reviewnfcgo >/dev/null 2>&1; then
    useradd --system --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin reviewnfcgo
fi
task_install=/opt/reviewnfcgo-cuentas
install -d -m 0755 -o root -g root "$task_install"
install -d -m 0700 -o reviewnfcgo -g reviewnfcgo /var/lib/reviewnfcgo-cuentas
if systemctl is-active --quiet reviewnfcgo-cuentas; then
    runuser -u reviewnfcgo -- "$task_install/venv/bin/python" "$task_install/runtime.py" --data /var/lib/reviewnfcgo-cuentas --backup
    systemctl stop reviewnfcgo-cuentas
fi
printf '\n2/4 Instalando el servidor y protegiendo las cuentas…\n'
for task_file in app.py runtime.py requirements.txt action.py Configurar.py; do
    install -m 0644 -o root -g root "$task_source/$task_file" "$task_install/$task_file"
done
python3 -m venv "$task_install/venv"
"$task_install/venv/bin/python" -m pip install --disable-pip-version-check --no-cache-dir -r "$task_install/requirements.txt"
install -m 0644 "$task_source/reviewnfcgo-cuentas.service" /etc/systemd/system/reviewnfcgo-cuentas.service
install -d -m 0755 /usr/local/sbin /usr/share/applications
cat > /usr/local/sbin/reviewnfcgo-servidor <<'WRAPPER'
#!/bin/sh
exec /usr/bin/python3 /opt/reviewnfcgo-cuentas/action.py "$@"
WRAPPER
chmod 0755 /usr/local/sbin/reviewnfcgo-servidor
cat > /usr/share/applications/reviewnfcgo-servidor.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=reviewNfcGo - Servidor
Comment=Conectar y comprobar el servidor de cuentas
Exec=/usr/bin/python3 /opt/reviewnfcgo-cuentas/Configurar.py
Icon=network-server
Terminal=false
Categories=System;
DESKTOP
printf '\n3/4 Configurando funcionamiento sin pantalla…\n'
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
install -d -m 0755 /etc/systemd/sleep.conf.d /etc/apt/apt.conf.d
cat > /etc/systemd/sleep.conf.d/reviewnfcgo.conf <<'SLEEP'
[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowHybridSleep=no
AllowSuspendThenHibernate=no
SLEEP
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'UPDATES'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
UPDATES
systemctl daemon-reload
systemctl enable --now reviewnfcgo-cuentas.service
if [ "$task_local_only" = false ]; then
    printf '\n4/4 Instalando la conexión HTTPS oficial de Tailscale…\n'
    install -d -m 0755 /usr/share/keyrings
    curl --fail --show-error --location --proto '=https' "https://pkgs.tailscale.com/stable/$ID/$VERSION_CODENAME.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
    curl --fail --show-error --location --proto '=https' "https://pkgs.tailscale.com/stable/$ID/$VERSION_CODENAME.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
    apt-get update -qq
    apt-get install -y --no-install-recommends tailscale
    systemctl enable --now tailscaled.service
fi
for task_attempt in $(seq 1 40); do
    if curl --fail --silent --max-time 2 http://127.0.0.1:8080/health >/dev/null; then
        printf '\nServidor instalado. Abre «reviewNfcGo - Servidor» en el menú de aplicaciones y pulsa «Activar conexión».\n'
        printf 'Arranca solo, no se suspende y guarda copias diarias. Todavía falta conectar Tailscale y enviar la dirección HTTPS.\n'
        exit 0
    fi
    sleep 0.5
done
printf 'El servicio no responde. Ejecuta: sudo journalctl -u reviewnfcgo-cuentas -n 25\n' >&2
exit 1
