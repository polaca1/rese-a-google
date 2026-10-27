# Watch Beta personal

Esta rama es una variante independiente de SideStore para pruebas personales, no una contribución al proyecto oficial. Conserva las licencias, autorías y reglas del proyecto original para cualquier futura contribución oficial. No publicar material generado por IA como si fuera una contribución humana al upstream.

## Compilar

1. Obtén el repositorio en el commit del manifiesto con `git clone --recurse-submodules` y selecciona esta rama.
2. Ejecuta `python3 watch-beta/bootstrap.py`. Los parches solo se aplican a los submódulos fijados por este commit.
3. Compila el esquema `SideStore - Release` con Xcode, sin firma para generar el archivo que firmará el instalador. El workflow `watch-beta.yml` contiene los argumentos exactos.
4. `watch-beta/package.py` prepara el IPA y manifiesto. Una firma ad hoc no permite ejecutar la app en un dispositivo; el instalador debe firmarla con la cuenta del usuario.

## Alcance 0.1.0

Detección del reloj por companion_proxy y prueba explícita de obtención de un perfil para watchOS. No es un instalador de watchOS ni un store autónomo del reloj. Los pasos de instalación/renovación se muestran pendientes.

La prueba de perfil utiliza la ruta iOS de Developer Services con `DTDK_Platform=watchos`, siguiendo la implementación experimental de Rzbck/isideload. No utiliza una ruta watchos inventada. El perfil se valida contra reloj, app, equipo, plataforma, expiración y presencia de certificados.

La consulta del registro se ejecuta en la cola FFI serial del motor Idevice. No modifica emparejamientos ni abre servicios de instalación. Los informes exportados usan campos enumerados y no incluyen identificadores ni errores libres.

## Referencias

- https://github.com/SideStore/SideStore
- https://github.com/SideStore/minimuxer
- https://github.com/SideStore/SideSign
- https://github.com/Rzbck/iloader-watch-companion

Código bajo las licencias originales incluidas en el repositorio y dependencias; los cambios de esta variante se distribuyen bajo AGPL-3.0, de acuerdo con la base SideStore.
