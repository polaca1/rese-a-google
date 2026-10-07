# reviewNfcGo

App de Pablo Cancho Flores para organizar negocios, tarjetas NFC, visitas, inventario e ingresos y gastos.

- iPhone: SwiftUI, controles nativos, widgets, recordatorios y Live Activities. Instalación mediante SideStore.
- Mac: app nativa para macOS 14 o posterior, Intel y Apple Silicon, con dashboard, tablas, gráficos, mapa y exportación CSV.
- Servidor opcional: cuentas reales y sesiones con FastAPI, SQLite y Argon2id. Negocios y dinero permanecen en cada dispositivo y se transfieren mediante copias de seguridad.

[Fuente de SideStore](https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore/source-compatible.json) · [Descargas](https://github.com/polaca1/rese-a-google/releases)

## Mac

Consulta [macos/LEEME.txt](macos/LEEME.txt). Abre el DMG y mueve la app a Aplicaciones. La app usa firma ad hoc; al no estar notarizada, macOS puede requerir clic derecho → Abrir. No necesita renovarse cada siete días.

Para compilar: Xcode 16.2 o posterior, esquema reviewNfcGoMac en macos/reviewNfcGo.xcodeproj. La distribución automatizada usa Xcode 26.2 y genera ambos procesadores con mínimo macOS 14.

## Tu PC como servidor

[Instrucciones paso a paso](server/INSTALAR-SERVIDOR.md). Recomendación para una PC dedicada con 4 GB: Debian sin escritorio, Docker y HTTPS privado con Tailscale. El servidor debe instalarse y configurarse en la PC antes de usar el login remoto.

## Claves de Google Places

La compilación lee REVIEWNFCGO_GOOGLE_PLACES_API_KEY y la clave opcional REVIEWNFCGO_GOOGLE_PLACES_FALLBACK_API_KEY de GitHub Actions. Si la principal no está disponible en el entorno, se utiliza la configuración heredada de la app sin imprimirla en el registro. No se añade una segunda clave hasta configurarla. Se intenta una sola petición alternativa en errores de autorización/cuota/servidor o conexión temporal; un resultado vacío no consume una segunda petición.
