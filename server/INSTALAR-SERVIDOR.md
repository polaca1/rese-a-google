# Servidor de cuentas en tu PC

Con unos 4 GB de RAM basta para las cuentas de reviewNfcGo. La PC debe estar encendida, conectada a Internet y sin suspensión. Este servidor verifica contraseñas y sesiones; los negocios, inventario y dinero siguen en cada dispositivo y se transfieren con copias de seguridad. Todavía no está instalado en tu PC.

## 1. Preparar la PC

Para dedicarla a esto, recomiendo **Debian 13 de 64 bits sin escritorio**, conectado por cable. Comprueba que su procesador sea de 64 bits. Descarga el instalador desde https://www.debian.org/ y crea un USB. **Guarda primero tus archivos de Windows: elegir borrar el disco durante la instalación los elimina.** Instala Debian, marca servidor SSH y utilidades estándar, sin entorno de escritorio. Puedes administrarlo desde Terminal del Mac con `ssh usuario@IP-DE-LA-PC`.

Instala Docker Engine y el complemento Compose siguiendo https://docs.docker.com/engine/install/debian/ . Después:

```sh
sudo apt update
sudo apt install git curl
sudo systemctl enable --now docker
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

## 2. Arrancar las cuentas

```sh
git clone --branch desktop/macos14-5.1 --single-branch https://github.com/polaca1/rese-a-google.git
cd rese-a-google/server
cp .env.example .env
sed -i 's/ALLOW_REGISTRATION=false/ALLOW_REGISTRATION=true/' .env
sudo docker compose up -d --build
curl http://127.0.0.1:8080/health
```

Debe devolver `{"status":"ok","schema":1}`. Los datos persisten en un volumen Docker. No ejecutes `docker compose down -v`, porque borra ese volumen.

## 3. Conectar por HTTPS desde casa o fuera

Instala Tailscale en Debian siguiendo https://tailscale.com/download/linux y ejecuta:

```sh
sudo tailscale up
sudo tailscale serve --bg http://127.0.0.1:8080
sudo tailscale serve status
```

Si pide activar HTTPS, sigue el enlace que muestra Tailscale. Instala Tailscale también en el iPhone y el Mac e inicia sesión con la misma cuenta de Tailscale. **Serve es privado para tu red Tailscale; no actives Funnel.** No necesitas abrir puertos en el router. El servicio HTTP solo escucha en la PC en 127.0.0.1.

Copia la URL real que muestre Serve, por ejemplo `https://mi-pc.mi-red.ts.net`, sin añadir `/v1/auth`. No uses la IP local ni localhost en la app.

## 4. Activar el login real

1. Exporta una copia de seguridad de la app de iPhone antes de cambiar la cuenta.
2. En iPhone, cierra sesión → despliega **Servidor de cuentas** → pega la URL HTTPS → Guardar servidor. En Mac: reviewNfcGo → Ajustes → Servidor de cuentas.
3. Crea una cuenta con **el mismo correo** que usabas para conservar el acceso a tus datos locales. La contraseña se guarda con Argon2id en el servidor; la app guarda la sesión en el llavero.
4. Tras crear las cuentas necesarias, cierra el registro:

```sh
sed -i 's/ALLOW_REGISTRATION=true/ALLOW_REGISTRATION=false/' .env
sudo docker compose up -d
```

Con un servidor configurado, el login se comprueba allí. Si la PC está apagada o no hay conexión, se muestra un error; no se comprueba una contraseña local en su lugar. Una sesión ya guardada permite trabajar con los datos locales sin conexión mientras sea válida. El servidor debe estar disponible para entrar o renovar la sesión.

**SideStore y Tailscale:** iOS suele permitir una sola VPN personal activa. Cambia temporalmente a la VPN que necesite SideStore al renovar sus apps, y vuelve a Tailscale para conectar con el servidor. Eso no borra tus datos.

## 5. Copias y mantenimiento

Crear una copia consistente de SQLite sin parar el servicio:

```sh
sudo docker compose exec -T accounts python -c 'import sqlite3; s=sqlite3.connect("/app/data/accounts.sqlite3"); d=sqlite3.connect("/app/data/accounts-backup.sqlite3"); s.backup(d); d.close(); s.close()'
sudo docker compose cp accounts:/app/data/accounts-backup.sqlite3 ./accounts-backup.sqlite3
chmod 600 accounts-backup.sqlite3
```

Guarda la copia fuera de esa PC. Contiene cuentas y sesiones: no la subas a GitHub. Las copias de negocios se exportan por separado desde cada app.

Actualizar:

```sh
git pull --ff-only
sudo docker compose up -d --build
sudo docker compose ps
```

El contenedor limita la memoria a 512 MB. Mantén Debian actualizado (`sudo apt update && sudo apt upgrade`), y conserva una copia antes de cambios. La opción de instalar sobre Windows con una máquina virtual consume más memoria; para esta PC antigua conviene Debian directamente.
