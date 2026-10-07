# Todas las cuentas de reviewNfcGo, en tu PC

El servidor guarda **todas las cuentas de todos los usuarios**, no solo la tuya. Cada registro de la app escribe en la base de datos de tu PC. Cada inicio de sesión verifica allí la contraseña. Los usuarios no configuran direcciones ni instalan Tailscale. Si el servicio no responde, no se crea una cuenta local como sustituto.

## Configuración inicial en Windows (una vez)

1. Descarga y extrae `reviewNfcGo-Servidor-Windows.zip`. Abre **Instalar.cmd** y acepta el permiso de Windows.
2. Pulsa **Instalar y preparar** y después **Activar conexión**. Se abrirá el navegador: inicia sesión en Tailscale y acepta habilitar HTTPS/Funnel.
3. Pulsa **Mantener la conexión**. En la página que se abre, busca este PC → **⋯ → Disable key expiry**. Esto evita tener que volver a autenticarlo cada 180 días.
4. **Copia la dirección** y envíasela al desarrollador una sola vez. Tras comprobarla, se activa para todas las apps y se publica la actualización. No tienes que pegarla en cada iPhone ni en cada cuenta.

Windows 10/11 de 64 bits, Internet y aproximadamente 4 GB de RAM bastan para este servicio de cuentas. No hay que borrar Windows, instalar Docker o abrir puertos del router. La instalación evita la suspensión cuando el PC está enchufado. No apagues el PC: si no está disponible, los registros e inicios de sesión no pueden completarse.

## Después de instalarlo

Puedes cerrar el configurador. El servidor se inicia al arrancar Windows, sin iniciar sesión, y Windows lo vuelve a arrancar si se cierra inesperadamente. La conexión HTTPS de Funnel también se reanuda tras reiniciar. Mantén el nombre de este PC y de la red de Tailscale para conservar la dirección.

Para comprobar cuentas: abre `C:\Program Files\reviewNfcGo Accounts\Instalar.cmd` → **Ver cuentas**. Solo muestra nombre, correo y fecha; las contraseñas son hashes Argon2id, no texto legible.

Las cuentas están en `C:\ProgramData\reviewNfcGo\Cuentas\accounts.sqlite3`. Los archivos están protegidos para el administrador y el servicio de Windows. **Nunca subas esa carpeta a GitHub**: solo se publica la dirección HTTPS.

Hay copias diarias en la subcarpeta **copias**, conservadas durante 30 días. Copia esa carpeta periódicamente a otro disco: las copias del mismo PC no protegen frente a la rotura de su disco. Se puede reinstalar sin borrar las cuentas. Windows y Tailscale requieren sus actualizaciones habituales; ningún ordenador doméstico puede prometer disponibilidad permanente sin mantenimiento.

El servidor de esta versión guarda cuentas y sesiones. Los negocios, el inventario y las operaciones se conservan localmente en las apps y se transfieren con sus copias de seguridad. Las cuentas locales de versiones anteriores requieren registrarse en el servidor con el mismo correo para conservar sus datos del dispositivo; sus contraseñas anteriores no se publican ni se trasladan como texto legible.

Conexión: [Tailscale Funnel](https://tailscale.com/docs/features/tailscale-funnel). Arranque y caducidad: [modo desatendido](https://tailscale.com/docs/how-to/run-unattended).
