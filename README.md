# reviewNfcGo · adaptación App Fair

Adaptación de la versión 7.3.0 (39), conservando las pantallas SwiftUI, navegación, modelos y servicio de cuentas existentes. **No es todavía una entrega aprobada para App Store.**

La aplicación original continúa en `features/reviewnfcgo-6.0`; su fuente de SideStore no se modifica.

## Qué incluye

- Proyecto Day 0.7.4 con destino iPhone/iPad y web de presentación.
- Paquete `swiftui/` con las pantallas actuales: Sitios, Dinero, Avisos, Inicio y Perfil; Inicio sigue siendo la selección inicial.
- Puente de enlaces de Day al router original y adaptación del ciclo de vida para sincronización, recordatorios y pregunta de venta tras NFC.
- Recursos gráficos originales desde el paquete, widgets y Live Activities con un grupo compartido propio.
- Misma autenticación de correo/Google y mismo servidor de sincronización. No se cambia el formato de datos, el propietario ni se consultan datos privados.
- Metadatos, borrador de privacidad, configuración de App Fair y CI de compilación y capturas.

La web presenta la app de iPhone; no es un port de sus herramientas NFC ni una aplicación de Android. NFC conserva el flujo actual hacia Simply NFC. La app no incorpora esa aplicación ni afirma verificar una escritura física al volver de ella.

## Comprobar

Instala Rust y Day 0.7.4. Desde la raíz:

```sh
python3 scripts/check-ui-parity.py
cargo fmt --all -- --check
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
day lint --strict
day lint --strict --flavor appfair
day build -t web-dom
```

En un Mac con Xcode:

```sh
swiftui/Tests/run.sh
cd swiftui
xcodebuild -scheme ReviewNfcGoViews -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
cd ..
day build -t ios-uikit --flavor appfair
day launch -t ios-uikit --flavor appfair --script dayscript/demo.yaml
```

Day requiere Xcode 27 para su host actual. Compilar únicamente el paquete SwiftUI no comprueba su integración completa con Day. Las pruebas de NFC, ubicación real, restauración de cuentas, notificaciones y widgets requieren un dispositivo o una sesión de pruebas apropiada. Los tests no usan cuentas privadas.

## Publicación pendiente

Consulta [ADAPTACION.md](ADAPTACION.md) y [docs/PUBLICACION.md](docs/PUBLICACION.md). La rama se prepara primero en el repositorio del propietario; la organización/repositorio homónimos y App Fair Publisher siguen siendo pasos externos pendientes.

No se promociona una versión, se publica en una tienda ni se reemplaza un IPA estable por generar este proyecto.
