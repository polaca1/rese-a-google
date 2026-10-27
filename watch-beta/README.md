# Watch Beta personal

Esta rama es una variante independiente de SideStore para pruebas personales, no una contribución al proyecto oficial. Conserva las licencias, autorías y reglas del proyecto original para cualquier futura contribución oficial. No publicar material generado por IA como si fuera una contribución humana al upstream.

## Compilar

1. Obtén el repositorio en el commit del manifiesto con `git clone --recurse-submodules` y selecciona esta rama.
2. Ejecuta `python3 watch-beta/bootstrap.py`. Los parches solo se aplican a los submódulos fijados por este commit.
3. Ejecuta `python3 watch-beta/build-idevice.py` en un Mac con Rust 1.99.1 (incluido llvm-tools-preview) y Xcode. Compila el soporte companion_proxy ausente del binario oficial para iPhone y verifica sus símbolos. Después compila el esquema `SideStore - Release` con Xcode, sin firma para generar el archivo que firmará el instalador. El workflow `watch-beta.yml` contiene los argumentos exactos.
4. `watch-beta/package.py` prepara el IPA y manifiesto. Una firma ad hoc no permite ejecutar la app en un dispositivo; el instalador debe firmarla con la cuenta del usuario.

## Alcance 0.7.0 (707)

Detección del reloj por companion_proxy y prueba explícita de obtención de un perfil para watchOS reutilizando el identificador existente del SideStore instalado. No crea identificadores ni certificados. Puede registrar el reloj como dispositivo de desarrollo tras pulsar el botón de prueba. No es un instalador de watchOS ni un store autónomo del reloj. Los pasos de instalación/renovación se muestran pendientes.

La prueba de perfil utiliza la ruta iOS de Developer Services con `DTDK_Platform=watchos`, siguiendo la implementación experimental de Rzbck/isideload. No utiliza una ruta watchos inventada. El perfil se valida contra reloj, app, equipo, plataforma, expiración y presencia de certificados.

La consulta del registro se ejecuta en la cola FFI serial del motor Idevice. No modifica emparejamientos ni abre servicios de instalación. Los informes exportados usan campos enumerados y no incluyen identificadores ni errores libres.

## Referencias

- https://github.com/SideStore/SideStore
- https://github.com/SideStore/minimuxer
- https://github.com/SideStore/SideSign
- https://github.com/Rzbck/iloader-watch-companion

Código bajo las licencias originales incluidas en el repositorio y dependencias; los cambios de esta variante se distribuyen bajo AGPL-3.0, de acuerdo con la base SideStore.

## Identidad y compatibilidad con datos móviles

Se reutiliza `com.SideStore.SideStore`, sus App Groups, espacio de llavero y esquemas URL originales para una actualización sobre la instalación actual con la misma cuenta Apple. La variante no debe renombrar IDs de widgets/SideBackup ni usar un identificador de otra app. La prueba de perfil emplea el bundle ID real leído del ejecutable ya firmado, incluyendo sufijos del instalador.

Se conservan los App Intents `RefreshAllAppsIntent` e `InstallIPAIntent` y el flujo `CellularRefreshManager`, con nombres de atajos configurables. La identidad original evita enviar el retorno de los atajos a otra copia de SideStore. Las pruebas por software no prueban refirma física con datos móviles.

El usuario confirmó el 27 de octubre de 2026 que su SideStore 0.7.0 y LocalDevVPN renuevan apps usando 5G. También indicó que ya tiene tres apps activas y agotó los App IDs. Por ello se cambió el plan inicial de app separada por una actualización sobre SideStore y se eliminó cualquier creación de App IDs. El objetivo final sigue siendo una tienda autónoma en watchOS; esta primera herramienta de diagnóstico no la implementa.

La reconstrucción FFI conserva los slices originales de otras plataformas; solo se ha añadido el soporte experimental al slice iPhone arm64. No añade soporte watchOS ni al simulador. El manifiesto de procedencia registra el compilador y SHA exactos.
