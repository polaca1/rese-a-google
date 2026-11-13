# Adaptación de reviewNfcGo para App Fair

Estado: interfaz original integrada como paquete SwiftUI y host Day preparado. Pendiente de verificación nativa completa y requisitos de publicación; no es una versión publicable todavía.

## Prioridad del usuario

Conservar la interfaz lo máximo posible. Se permite cambiar la implementación del backend; esto no autoriza a perder datos ni funciones.

Referencia: `polaca1/rese-a-google`, rama `features/reviewnfcgo-6.0`, commit `69150a6582bdddc942dfac7d614d7cb594cb846c` (versión 7.3.0, build 39).

## Contrato visual

- Mantener las pestañas Sitios, Dinero, Avisos, Inicio y Perfil, en ese orden. Inicio continúa siendo la selección inicial.
- Conservar el mapa de Inicio, las fichas de negocios y el flujo de escritura NFC y venta.
- Mantener formularios nativos, tipografía del sistema, colores semánticos y modo claro y oscuro.
- Conservar el acceso con correo y Google, recuperación de contraseña y Perfil. Sin controles de servidores, nube, copias ni desarrollo en la interfaz habitual.
- Conservar el guardado accesible de ventas y la posibilidad de cerrar el teclado.
- No añadir pantallas o pasos técnicos para satisfacer requisitos internos de publicación.

## Ruta para reutilizar la interfaz

Day 0.7.4 documenta la integración de vistas SwiftUI mediante `day-piece-swiftui` y un paquete SwiftPM. Se utiliza esta vía para reutilizar las pantallas de iPhone. Requiere integrar también el ciclo de vida, notificaciones, enlaces OAuth, permisos, recursos y NFC; copiar las vistas por sí solo no constituye una adaptación funcional.

Referencias oficiales:

- https://daybrite.dev/docs/how-to/guide-swiftui
- https://appfair.org/docs/inclusion-criteria/
- https://appfair.org/docs/getting-started/

La integración SwiftUI solo cubre plataformas Apple. Los criterios de App Fair exigen mantener los destinos móviles que se presenten y web-dom. Esta adaptación presenta únicamente iOS, con una web informativa; no incorpora ni promete un port de Android. La aceptación de esta arquitectura debe confirmarse con App Fair antes de presentar una versión.

## Datos y publicación

Antes de cambiar el backend, conservar una vía de acceso a los datos existentes, identificar usuarios por identidad verificada y verificar recuperación tras reinstalar. No incluir credenciales privadas ni datos de usuarios en el repositorio o las pruebas.

La versión instalada y la fuente estable de SideStore permanecen fuera de esta adaptación. La publicación está pendiente de completar y comprobar la app, auditar licencias y privacidad, configurar la organización/repositorio y obtener la revisión de App Fair y de las tiendas.
