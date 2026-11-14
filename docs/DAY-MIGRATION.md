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

Se están portando y comprobando los flujos principales. Ya están portados el detalle de producto, sus movimientos, ajustes de existencias, mínimo de stock, seguimiento y beneficio por negocio. Todavía faltan superficies auxiliares de actividad, presupuestos, rutas, objetivos, corrección de gastos y adquisición avanzada de inventario, además de las pruebas completas del contenedor iOS. No se declara paridad funcional del 100 % mientras estos elementos estén pendientes.

El workflow `Native Day migration` comprueba Rust, el límite entre interfaz y servicios, la compilación del paquete de servicios nativos y el destino UIKit de Rust. El host convencional de Day 0.7.4 requiere Xcode 27. Estas comprobaciones parciales no sustituyen ejecutar ese host y probarlo físicamente.

La variante `verification` usa exclusivamente datos sintéticos para comparar la distribución de pantallas en navegador. No autentica cuentas ni simula ventas guardadas. Sus capturas no son capturas de un iPhone.


## Verificación de esta rama

El commit `1afc68f` superó los dos trabajos de CI (ejecución `43628024780`): servicios nativos sin vistas antiguas y comprobación Rust para UIKit, además de las pruebas existentes de reglas del negocio. Los ajustes posteriores de navegación y tamaño del saldo se comprueban con clippy y el recorrido visual. Ninguno de estos resultados equivale a compilar y ejecutar el host iOS completo.

Las comprobaciones visuales se ejecutan a 390 × 844, en modo claro y oscuro, con datos de `fixtures/day-ui.json`. Se verifica Inicio como selección inicial, el orden de las pestañas, volver entre formularios y la venta con total y stands gratuitos. El navegador utiliza los controles web de Day; no prueba el tamaño final de los controles UIKit ni la escritura física NFC.


El recorrido de navegador está en `scripts/verify-day-ui.cjs` (Node.js, Playwright y Chromium). Tras compilar la variante, sirve `build/day/flavors/verification/cargo/web-dom/debug/dist` en el puerto 8073 y ejecuta el script desde la raíz. `REVIEW_UI_URL` y `REVIEW_BROWSER` permiten cambiar la URL y el ejecutable. Guarda el informe y seis capturas en `evidence/day-ui/`, fuera del código distribuido. La última ejecución pasó en ambos modos sin errores JavaScript; también comprobó que volver a otra pantalla limpia los errores y que una venta nueva desde Dinero no hereda otro cliente.
