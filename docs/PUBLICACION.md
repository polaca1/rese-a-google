# Preparación para App Fair

## Estado actual

La rama `day/native-ui` contiene la interfaz principal en Day/UIKit: `src/pages.rs` y `src/workspace.rs`. Los servicios existentes están en `native-services/`; MapKit usa un renderizador nativo de Day. El paquete antiguo de pantallas SwiftUI no está enlazado. Los widgets y Live Activities conservan las APIs de Apple.

El candidato [7.3.1 (47)](https://github.com/polaca1/rese-a-google/releases/tag/reviewnfcgo-day-7.3.1-build47) es un IPA arm64 sin firmar, compilado con el punto de entrada real de Day y un host XcodeGen temporal con Xcode 26.3. Pasó las comprobaciones de archivo, widgets, privacidad, SHA-256 y pruebas de Rust/servicios. Las capturas de navegador usan datos sintéticos; la instalación física y los flujos completos en iPhone siguen pendientes. Véase [DAY-MIGRATION.md](DAY-MIGRATION.md).

El mantenimiento público actual está en `polaca1/rese-a-google`. El token propuesto `ReviewNfcGo`, la futura organización/repositorio homónimos y el identificador `org.appfair.app.ReviewNfcGo` son configuración propuesta: no acreditan reservas ni aprobación. `Day-appfair.toml` conserva ese identificador de publicación.

## Presentación inicial

La presentación de [APPFAIR-PROPUESTA.md](APPFAIR-PROPUESTA.md) se ha enviado como consulta preliminar al contacto oficial `contact@appfair.org`, con enlaces al código y al candidato iOS. El canal oficial previo al catálogo es una [discusión de App Fair](https://github.com/orgs/appfair/discussions), que sigue pendiente: la integración de GitHub no tiene permiso para crearla. El correo no equivale a un PR de catálogo ni a una aprobación. Se espera respuesta sobre el encaje del proyecto.

## Requisitos pendientes antes del PR de catálogo

1. Completar Android con funciones equivalentes. El destino web actual es de presentación y no constituye una versión Android de la app.
2. Validar el host convencional de Day y los recorridos nativos de ambos destinos. El host temporal de Xcode 26.3 permite probar un candidato iOS, pero no sustituye los requisitos del flujo oficial de App Fair.
3. Probar en iPhone la cuenta, sincronización y recuperación de datos, teclado, ventas, permisos, widgets y NFC. Consultar el encaje del envío de escritura a Simply NFC, una app externa.
4. Implementar y probar la eliminación de cuenta y sus datos en servidor; completar el contacto y la política de retención. Revisar el acceso con Google respecto a la regla 4.8 de Apple e incorporar Sign in with Apple si corresponde.
5. Completar la revisión de licencias de dependencias y titularidad del material gráfico. Los avisos están incluidos en los recursos, pero no equivalen a la aprobación de App Fair.
6. Crear la organización y el repositorio públicos homónimos, instalar App Fair Publisher con el acceso necesario y publicar GitHub Pages. La instalación requiere la intervención del propietario para conceder permisos.
7. Preparar el prerelanzamiento reproducible con paquetes iOS/Android, capturas nativas y metadatos; después presentar el PR de catálogo enlazando la discusión inicial. App Fair y cada tienda deciden la aceptación.

## Datos existentes

La firma e identidad de App Store pueden usar un sandbox distinto de la versión de SideStore. No tendrán acceso automático a sus archivos locales o a su llavero. La cuenta y el servidor permiten recuperar los datos que ya estén sincronizados al iniciar sesión. Antes de migrar hay que comprobar que los últimos cambios están guardados y que la descarga funciona; no borrar la instalación anterior como prueba.

Fuentes: [inclusión](https://appfair.org/docs/inclusion-criteria/) · [primeros pasos](https://appfair.org/docs/getting-started/) · [contribución al catálogo](https://github.com/appfair/appfair-apps/blob/main/CONTRIBUTING.md).
