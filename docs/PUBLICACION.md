# Preparación para App Fair

## Configuración preparada

- Token propuesto: `ReviewNfcGo` (pendiente de disponibilidad y creación).
- Identificador de desarrollo: `dev.polaca1.ReviewNfcGo`.
- Identificador de publicación en `Day-appfair.toml`: `org.appfair.app.ReviewNfcGo`.
- Widget: sufijo `ReviewNfcGoWidgets`, grupo `group.org.appfair.app.ReviewNfcGo.widgets`.
- Web prevista: `https://ReviewNfcGo.github.io/ReviewNfcGo`.
- CI reutiliza el flujo oficial de Day, prepara prerelanzamientos y conserva capturas claras/oscuras. En la rama de preparación se comprueba el paquete SwiftUI; el flujo completo de publicación se habilita al trasladar el proyecto al repositorio homónimo. `deploy-web` debe pasar a `true` allí.

Estos identificadores son configuración de código. No significan que Apple, GitHub o App Fair hayan creado o aprobado los recursos.

## Requisitos pendientes antes de una presentación

1. Compilar y ejecutar el host completo con Xcode 27. Comparar las capturas originales y adaptadas; probar teclado, venta, permisos, widgets, enlaces y recuperación de cuenta tras reinstalar. El CI del paquete aislado no sustituye estas pruebas.
2. Consultar a App Fair si acepta esta adaptación Day con interfaz SwiftUI alojada y web de presentación, y el flujo externo de escritura con Simply NFC. No se ha obtenido aceptación.
3. Revisar el acceso con Google frente a la regla 4.8 de Apple y, si corresponde, incorporar Sign in with Apple con su configuración de servidor.
4. Implementar y probar la eliminación de cuenta y sus datos en el servidor, completar el contacto privado del responsable y concretar retención de datos. La privacidad actual lo identifica como pendiente; no inventa plazos.
5. Revisar el informe de las 295 dependencias del lock en `provenance/dependency-licenses.json` y la titularidad del material gráfico. No hay dependencias sin licencia declarada; los avisos se incluyen como recurso del paquete. La selección de permisos y bibliotecas de cada paquete final también debe revisarse. No hay SDK de anuncios o telemetría añadido por esta adaptación.
6. Crear la organización y el repositorio públicos con el mismo token, instalar App Fair Publisher con acceso al repositorio y habilitar Pages. La instalación de una GitHub App concede permisos y debe revisarla el propietario.
7. Abrir primero una discusión de presentación; completar las verificaciones, generar un prerelanzamiento reproducible y después presentar el PR de catálogo que enlace la discusión. App Fair y las tiendas deciden la aceptación.

## Datos existentes

La nueva firma/identidad de App Store puede usar un sandbox distinto de la versión de SideStore. No tiene acceso automático a sus archivos locales o a su llavero. Mantener la cuenta y el servidor permite recuperar los datos que ya estén sincronizados tras iniciar sesión. Antes de migrar hay que verificar que los últimos cambios estén guardados y que la descarga funciona; no borrar la instalación anterior como prueba.

## Borrador de presentación (no enviado)

> I would like to submit reviewNfcGo, a Spanish iPhone app for business visits, review links, inventory and sales. Its existing native SwiftUI interface is hosted by the documented day-piece-swiftui integration in a conventional Day project; the web target is a presentation of the iPhone app. The client uses Supabase Auth/data and OS frameworks, with no advertising or telemetry SDKs. NFC writing currently hands the review URL to Simply NFC, an external app that is not bundled. Is this architecture and iPhone-only submission acceptable? We will complete native integration tests, account-deletion/privacy work and the license audit before submitting a release.

Fuentes: https://appfair.org/docs/inclusion-criteria/ · https://appfair.org/docs/getting-started/ · https://daybrite.dev/docs/reference/swiftui
