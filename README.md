# reviewNfcGo · interfaz Day

Migración en curso de las pantallas de iPhone a controles Day en Rust, conservando al máximo el diseño y los servicios existentes.

- Interfaz y navegación: `src/pages.rs`.
- Estado de pantalla y venta: `src/model.rs`.
- Mapa MapKit como componente Day: `src/mapkit.rs`.
- Servicios de cuenta, datos y dispositivos sin pantallas SwiftUI: `native-services/`.
- Referencia anterior de diseño y pruebas: `swiftui/`, que no se enlaza en el destino migrado.

**La migración todavía no está terminada.** El alcance, las comprobaciones y los flujos pendientes están en [docs/DAY-MIGRATION.md](docs/DAY-MIGRATION.md).

## Comprobar

```sh
python3 scripts/check-day-boundary.py
cargo fmt --all -- --check
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
day lint --strict
day build -t web-dom --flavor verification
```

La variante de verificación solo contiene datos sintéticos para inspeccionar la interfaz. Para la aplicación real se requiere el destino `ios-uikit`; el host convencional de Day exige Xcode 27. La compilación de los servicios por separado y las capturas de navegador no demuestran el funcionamiento del host completo en un teléfono.

La publicación en App Fair/App Store sigue pendiente; consulta [docs/PUBLICACION.md](docs/PUBLICACION.md).
