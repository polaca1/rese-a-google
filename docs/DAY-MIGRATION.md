# Migración de interfaz a Day

Rama de trabajo: `day/native-ui`. No es una versión terminada ni un IPA de producción.

## Límite de la arquitectura

Las pantallas de la aplicación principal se construyen en Rust con piezas Day en `src/pages.rs`. El destino no depende de `day-piece-swiftui` ni enlaza el paquete antiguo `ReviewNfcGoViews`.

`native-services/` conserva los servicios y modelos existentes de cuentas, sincronización, ventas, inventario, notificaciones y dispositivos. No contiene pantallas SwiftUI. MapKit se monta mediante un renderizador nativo de Day; conserva el coordinador de cámara y los marcadores del mapa original. Los widgets y Live Activities continúan usando las APIs nativas de WidgetKit, como exige ese punto de extensión de Apple.

La carpeta `swiftui/` permanece como referencia de diseño y de pruebas del comportamiento anterior. No forma parte del producto Day migrado. El IPA `native-preview` anterior pertenece a otra rama y usa el contenedor antiguo; no demuestra esta migración.

## Diseño que se conserva

- Sitios, Dinero, Avisos, Inicio y Perfil, en ese orden; Inicio sigue siendo la selección inicial.
- MapKit, altura de mapa de 330 puntos, marcador azul, enfoque y comportamiento de selección de locales existentes.
- Nombre, dirección, escritura NFC, copia del enlace y «Volver más tarde» en la ficha de Inicio.
- Venta con productos marcables, cantidad, precio, stands seleccionados gratuitos cuando se entrega una tarjeta, y guardado fuera del contenido desplazable.
- Nombre, correo, foto, resumen y acciones de cuenta en Perfil.
- Tipografía semántica, tarjetas agrupadas y modos claro y oscuro. Las diferencias concretas de los controles Day requieren comparación en iPhone.

## Comprobación y trabajo pendiente

Las pantallas principales, actividad, presupuestos y PDF, rutas, objetivos y gráficos, seguimiento, movimientos, corrección de gastos, entradas gratuitas y edición de ventas anteriores están portadas a controles Day. Las pantallas de diagnóstico y copias de seguridad que estaban excluidas de producción no se han añadido al producto normal. Se mantienen los servicios y las reglas financieras anteriores.

El workflow `Native Day migration` comprueba Rust, el límite entre interfaz y servicios, la compilación del paquete de servicios nativos y el destino UIKit. El host convencional de Day 0.7.4 requiere Xcode 27. El workflow `Day device candidate` prueba por separado un host PBX temporal generado con XcodeGen y Xcode 26.3: utiliza el mismo `platform/ios/Runner/main.swift`, el archivo Rust real de Day y sus fases `xcode-backend`. No enlaza `preview/` ni las pantallas SwiftUI antiguas. Este host temporal no sustituye el host convencional exigido para publicar en App Fair.

No se declara paridad funcional o visual del 100 % ni preparación para producción sin ejecutar y revisar el host completo en iPhone, incluidas las cuentas, restauración y NFC. Una compilación o captura de navegador no acredita esas pruebas físicas.

La variante `verification` usa exclusivamente datos sintéticos para comparar la distribución de pantallas en navegador. No autentica cuentas ni simula ventas guardadas. Sus capturas no son capturas de un iPhone.


## Verificación de esta rama

El commit `1afc68f` superó los dos trabajos de CI (ejecución `43628024780`): servicios nativos sin vistas antiguas y comprobación Rust para UIKit, además de las pruebas existentes de reglas del negocio. Los ajustes posteriores de navegación y tamaño del saldo se comprueban con clippy y el recorrido visual. Ninguno de estos resultados equivale a compilar y ejecutar el host iOS completo.

Las comprobaciones visuales se ejecutan a 390 × 844, en modo claro y oscuro, con datos de `fixtures/day-ui.json`. Se verifica Inicio como selección inicial, el orden de las pestañas, volver entre formularios y la venta con total y stands gratuitos. El navegador utiliza los controles web de Day; no prueba el tamaño final de los controles UIKit ni la escritura física NFC.


El recorrido de navegador está en `scripts/verify-day-ui.cjs` (Node.js, Playwright y Chromium). Tras compilar la variante, sirve `build/day/flavors/verification/cargo/web-dom/debug/dist` en el puerto 8073 y ejecuta el script desde la raíz. `REVIEW_UI_URL` y `REVIEW_BROWSER` permiten cambiar la URL y el ejecutable. Guarda el informe y catorce capturas en `evidence/day-ui/`, fuera del código distribuido. La última ejecución pasó en ambos modos sin errores JavaScript; también comprobó que volver a otra pantalla limpia los errores y que una venta nueva desde Dinero no hereda otro cliente.


## IPA de dispositivo

`Day-device.toml` conserva `com.pablo.resenagoogle.20261004` y el host temporal conserva el widget `.liveactivity`. El workflow asigna números de compilación nuevos, archiva para `iphoneos`, verifica arm64, el punto de entrada Rust `day_main`, los widgets y el manifiesto de privacidad, y empaqueta un IPA sin firmar. Solo después de esas verificaciones publica un candidato de pruebas con su procedencia y SHA-256. No actualiza la fuente estable de SideStore ni publica en App Store.
