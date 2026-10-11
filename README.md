# reviewNfcGo

App para organizar negocios, tarjetas NFC, visitas, clientes, presupuestos, inventario e ingresos y gastos.

- **iPhone 6.0.2:** Inicio con mapa y búsqueda, escritura NFC mediante Simply NFC, widgets y recordatorios. Distribución mediante SideStore.
- **Mac 2.0.2:** app nativa para macOS 14 o posterior, Intel y Apple Silicon, con tablas, gráficos, informes PDF y exportación CSV.
- **Cuentas:** acceso con correo/contraseña o Google mediante Supabase. Los datos de cada cuenta se guardan automáticamente y se recuperan al volver a entrar. La interfaz no requiere configurar servidores, sincronizar manualmente ni gestionar copias.

[Fuente de SideStore](https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore/source-compatible.json) · [Descargas](https://github.com/polaca1/rese-a-google/releases)

## Organización y mantenimiento

[Arquitectura](docs/ARCHITECTURE.md) · [Revisión de producción](docs/PRODUCTION.md) · [Instalación en Mac](macos/LEEME.txt)

SwiftUI gestiona las pantallas y la navegación; los almacenes realizan las operaciones de negocio; los servicios gestionan autenticación, sincronización y proveedores externos. Los modelos compartidos conservan el formato existente de datos entre iPhone y Mac. Las rutas de simulación e importación manual de mantenimiento se compilan solo en DEBUG.

## Compilar y comprobar

La distribución automatizada utiliza Xcode 26.2. El destino mínimo de Mac sigue siendo macOS 14. Compila con los esquemas `reviewNfcGo` y `reviewNfcGoMac` en sus proyectos respectivos.

Los scripts `ios/reviewNfcGo/Scripts/build-ipa.sh` y `macos/Scripts/build-mac.sh` generan paquetes Release, ejecutan pruebas y verifican metadatos, privacidad y ausencia de rutas de prueba antes del empaquetado. El flujo de GitHub Actions publica únicamente tras superar las comprobaciones de ambos productos.

Google Places utiliza la clave de compilación `GOOGLE_PLACES_API_KEY` y una alternativa opcional `GOOGLE_PLACES_FALLBACK_API_KEY`, inyectadas y ocultadas en los registros. La configuración heredada se mantiene como transición. Los secretos OAuth y credenciales administrativas permanecen en el proveedor, nunca en el paquete de la app.

## Servicio de cuentas

La configuración oficial se obtiene de `accounts-server.json` en la rama `sidestore`. Supabase Auth y las tablas privadas con RLS administran las cuentas y los datos. [Configuración del servicio](server/cloud/GUIA-SUPABASE.md). Los archivos del antiguo servidor autohospedado se conservan para mantenimiento; no forman parte de la configuración requerida al usuario.
