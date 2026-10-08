# Tu RKM como servidor de reviewNfcGo

Preparado para el Rikomagic MK36S de tu foto: 2 GB de RAM, 32 GB de almacenamiento e Intel de 64 bits. Usaremos **Debian 13 con XFCE**, un escritorio ligero. El servidor no utiliza Docker.

El servidor almacena las cuentas y sesiones de todos los usuarios cuando la app esté conectada a su dirección. **No sincroniza todavía negocios, inventario ni operaciones entre dispositivos.** Los registros de las versiones antiguas tampoco se trasladan solos: conserva la copia JSON del iPhone.

## 1. Lo que necesitas

- Tu Mac, un USB vacío de al menos 8 GB y el RKM con su fuente de alimentación.
- Un teclado USB y una pantalla o TV conectada al RKM por HDMI durante la instalación.
- Un cable de red entre el RKM y el router. Así evitamos depender del controlador Wi-Fi del mini PC durante la instalación.

**Grabar el USB borra el USB. Elegir «usar todo el disco» durante la instalación borra Windows y los archivos del RKM. Si necesitas conservar algo, copia esos archivos antes de confirmar el particionado. No requiere conocer la contraseña antigua de Windows.**

## 2. Preparar el USB desde el Mac

1. Entra en https://www.debian.org/distrib/netinst y pulsa **amd64**. Descarga el archivo que termine en `amd64-netinst.iso`. «amd64» también sirve para tu Intel. No elijas arm64, que es otra arquitectura.
2. Descarga balenaEtcher desde https://etcher.balena.io/ e instala su versión para **Mac Intel**.
3. Conecta el USB al Mac. Abre Etcher → **Flash from file** → selecciona la ISO → **Select target** → selecciona tu USB por nombre y capacidad → **Flash**.
4. Espera hasta que termine. Si macOS dice que el disco no se puede leer, pulsa **Ignorar**: no lo inicialices ni lo vuelvas a formatear. Expulsa el USB.

## 3. Arrancar el RKM desde el USB

1. Conecta al RKM el USB preparado, el teclado, la pantalla HDMI y el cable de red. Enciende la pantalla y el RKM.
2. Pulsa **Esc repetidamente desde el encendido**. Es la tecla documentada en una prueba del MK36S. Si no entra, apaga normalmente si puedes y prueba **Supr/Del** al encender, preferiblemente con teclado USB con cable.
3. Dentro de la BIOS busca **Boot Override**, normalmente en **Save & Exit**, y selecciona el USB, preferiblemente la entrada que empiece por **UEFI**. Si solo hay prioridades de arranque, pon el USB primero y usa la opción visible **Save Changes and Exit**.
4. Aparecerá Debian. Elige **Graphical install**. Hasta este momento no has borrado Windows.

## 4. Instalar Debian con ventanas

1. Selecciona español, tu país y el teclado español.
2. Nombre del equipo: **reviewnfcgo**. Puedes dejar el dominio vacío y mantener los valores predeterminados de la red.
3. En **contraseña de root / administrador**, deja ambos campos vacíos. Así el instalador permite que tu usuario normal administre el PC con `sudo`.
4. Crea tu usuario y una contraseña nueva. Guárdala: será la que utilices cuando el configurador pida permiso de administrador. No es la contraseña de Windows ni la de reviewNfcGo.
5. Si aceptas borrar el RKM: **Guiado — utilizar todo el disco** → selecciona su almacenamiento interno de unos 32 GB, no el USB → **Todos los ficheros en una partición** → **Finalizar el particionado y escribir los cambios**. Revisa el resumen y confirma **Sí**. Aquí se borran los datos del disco elegido.
6. Para descargar paquetes, elige un servidor de Debian de tu país y deja el proxy vacío. La encuesta de popularidad es opcional.
7. En la selección de programas, conserva **Entorno de escritorio Debian**, **XFCE** y **Utilidades estándar del sistema**. Desmarca **GNOME** y los otros escritorios. No necesitas seleccionar servidor web ni SSH para este configurador.
8. Si pregunta por el cargador de arranque, instálalo en el almacenamiento interno, no en el USB. Cuando indique que ha terminado, retira el USB y reinicia.

Entra con la contraseña nueva. Ya no necesitas la contraseña anterior de Windows.

## 5. Instalar reviewNfcGo una vez

1. En el navegador del RKM descarga:
   https://github.com/polaca1/rese-a-google/releases/download/reviewnfcgo-server-linux-1.1/reviewNfcGo-Servidor-Linux.zip
2. Haz clic derecho en el ZIP → **Extraer aquí**. Verás la carpeta `reviewNfcGo-Servidor-Linux` y dentro el archivo **Instalar.sh**.
3. Abre **Terminal** desde el menú de aplicaciones. Escribe `sudo bash `, con un espacio al final, y arrastra **Instalar.sh** a la terminal. Pulsa Intro.
4. Escribe la contraseña de Debian y pulsa Intro. **Mientras la escribes no aparecen letras ni asteriscos: es normal.** Espera a que termine. Puede tardar varios minutos según la conexión.
5. Cuando diga **Servidor instalado**, abre **reviewNfcGo - Servidor** desde el menú de aplicaciones. Si no aparece inmediatamente, cierra sesión en Debian y vuelve a entrar.

El instalador configura arranque automático, usuario de servicio sin permisos de administrador, cuentas privadas, suspensión e hibernación desactivadas y actualizaciones de seguridad del sistema. Escucha solo en el propio PC; la conexión externa se hace por Tailscale Funnel.

## 6. Crear la dirección pública

1. En el configurador pulsa **1. Activar conexión**. Autoriza con la contraseña de Debian si aparece una ventana.
2. Se abrirá el navegador. Crea una cuenta o inicia sesión en Tailscale. Acepta habilitar HTTPS/Funnel cuando aparezca el permiso. Es una acción del propietario una sola vez: los usuarios de la app no instalan Tailscale ni configuran direcciones.
3. Si se agota el tiempo antes de terminar, completa la autorización y vuelve a pulsar **Activar conexión**. No borra las cuentas.
4. Pulsa **3. Mantener conexión: desactivar caducidad del PC**. En la página de Tailscale busca **reviewnfcgo** → menú **⋯ → Disable key expiry**. Mantén el nombre de este PC y el de tu red de Tailscale para conservar la dirección.
5. Pulsa **Comprobar conexión y arranque automático**. Espera a que indique **Conexión comprobada**. Si acaba de crearse el dominio, puede necesitar varios minutos.
6. Pulsa **2. Copiar dirección para conectar todas las apps** y pega esa dirección HTTPS en el chat con el desarrollador.

**Hasta que se compruebe esa dirección y se publique la actualización que la usa, las apps antiguas no envían sus registros a este PC.** No introduzcas direcciones inventadas ni publiques los archivos de cuentas.

## 7. Dejarlo encendido sin pantalla

- Puedes cerrar el configurador, cerrar sesión y desconectar la pantalla. El servicio permanece activo.
- No pulses **Apagar**. La pantalla puede apagarse, pero el PC debe seguir encendido. El instalador bloquea la suspensión y la hibernación.
- Reinicia una vez y prueba desde el móvil, mejor con datos móviles, tu dirección seguida de `/health`: debe aparecer `"status":"ok"`, incluso sin entrar en Debian.
- Si el servicio se cierra inesperadamente, systemd intenta reiniciarlo tras cinco segundos. Tailscale Funnel queda configurado en segundo plano y se reanuda con su servicio tras arrancar.
- Si hay un corte de corriente, puede que el RKM necesite pulsar su botón al volver la luz. El encendido automático tras un corte depende de su BIOS: solo activa una opción como **Restore on AC Power Loss / Power On** si realmente aparece en tu unidad. No actualices la BIOS para buscarla.
- La disponibilidad depende de electricidad, Internet, disco sano y mantenimiento. No prometemos funcionamiento continuo durante un corte. Mantén ventiladas las rejillas; el RKM debe estar sobre una superficie firme.

## 8. Cuentas y copias de seguridad

El configurador incluye **Ver cuentas registradas** y **Guardar copia de seguridad ahora**. Las contraseñas no se muestran: se guardan como hashes Argon2id. No hay una lista pública de usuarios.

Datos: `/var/lib/reviewnfcgo-cuentas/accounts.sqlite3`.
Copias diarias: `/var/lib/reviewnfcgo-cuentas/copias`, con las últimas 30 fechas disponibles. Las copias se actualizan cada hora y con el botón de copia; funcionan sin detener registros.

Para guardar una copia fuera del RKM, conecta otro disco o USB y abre una terminal:

```sh
sudo reviewnfcgo-servidor backup
sudo tar -czf "$HOME/reviewNfcGo-cuentas-copias.tar.gz" -C /var/lib/reviewnfcgo-cuentas copias
sudo chown "$USER" "$HOME/reviewNfcGo-cuentas-copias.tar.gz"
```

Copia el archivo `reviewNfcGo-cuentas-copias.tar.gz` de tu carpeta personal al disco externo. Contiene datos privados y hashes: no lo publiques ni lo subas a GitHub. Las copias guardadas solo en el mismo PC no protegen contra la rotura de su disco.

Si el servicio no responde:

```sh
sudo reviewnfcgo-servidor status
sudo journalctl -u reviewnfcgo-cuentas -n 25
```

Puedes volver a ejecutar **Instalar.sh** para reparar la instalación. No elimina las cuentas existentes y guarda una copia antes de detener un servicio activo.

Fuentes: [Debian y equipos con pocos recursos](https://www.debian.org/releases/stable/amd64/ch03s04.en.html), [instalación de Debian](https://www.debian.org/releases/stable/amd64/), [Tailscale Funnel](https://tailscale.com/docs/features/tailscale-funnel), [prueba de arranque del RKM MK36S](https://androidpc.es/review-rkm-mk36s/).
