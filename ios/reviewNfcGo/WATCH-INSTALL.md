# reviewNfcGo para Apple Watch

watchOS 10 o posterior; compilación con Xcode 26.2. Desarrollado por Pablo Cancho Flores.

La app ofrece próxima visita y cuenta atrás, negocios y acciones rápidas (llegada, volver mañana, venta), indicaciones en Mapas, resumen del día, Smart Stack y complicaciones. Seleccionar «Preparar NFC en iPhone» abre la ficha del negocio en el iPhone; la escritura se inicia y se realiza acercando la tarjeta al iPhone. Apple no publica Core NFC para escritura de etiquetas desde watchOS.

## Qué descarga SideStore

La fuente compatible distribuye el IPA de **iPhone**, con sus widgets y Live Activities. Ese IPA no incluye el bundle del Watch: SideStore no ofrece una instalación watchOS verificada en nuestro flujo. Las Live Activities compatibles pueden reflejarse automáticamente en la Smart Stack del reloj en iOS 18 / watchOS 11 o posteriores, con las opciones de Live Activities activadas. Esto no equivale a instalar la app nativa del Watch.

La release incluye `reviewNfcGo-5.0-Watch-device.zip` (compilación sin firma de dispositivo, no instalable hasta firmarla) y `reviewNfcGo-5.0-Xcode.zip` (proyecto completo para firmar y ejecutar). No basta con cambiar la extensión de un archivo ni importarlo en SideStore.

## Instalar en tu Watch desde un Mac

1. Guarda antes una copia de tus datos desde Perfil → Copias de seguridad. La versión firmada en Xcode puede tener un identificador distinto al generado por SideStore; no desinstales tu app sin una copia.
2. Descarga y descomprime el proyecto de Xcode de la release. Abre `reviewNfcGo/reviewNfcGo.xcodeproj` en Xcode 26.2.
3. En Xcode → Settings → Accounts, añade tu Apple ID. Conecta el iPhone al Mac, enlaza el Watch al iPhone y activa el modo desarrollador en ambos dispositivos. Confía en el Mac si se solicita.
4. En Signing & Capabilities, selecciona el mismo Team para **reviewNfcGo**, **reviewNfcGoLiveActivity**, **reviewNfcGoWatch** y **reviewNfcGoWatchWidgets** y activa Automatically manage signing. Si los identificadores ya están registrados por otro Team, cambia los cuatro de forma coherente. En el Info.plist del Watch, `WKCompanionAppBundleIdentifier` debe coincidir con el identificador real de iPhone.
5. Registra los grupos de apps de los widgets y del Watch con tu Team; si cambias un grupo, actualiza los entitlements y los nombres en `WidgetSharedStore.swift` y `WatchSharedStore.swift`. La disponibilidad de estas capacidades depende de tu cuenta Apple. La cuenta gratuita puede no admitir todas las capacidades del proyecto.
6. Configura tu propia clave de Google Places en `reviewNfcGo/Info.plist` (campo `GooglePlacesAPIKey`); no publiques esa clave. El ZIP del proyecto no incluye claves. La compilación de dispositivo tampoco incluye una clave para un Team ajeno.
7. Ejecuta primero el esquema **reviewNfcGo** en tu iPhone con Xcode. Después selecciona **reviewNfcGoWatch** y tu Apple Watch como destino y pulsa Run. Para sincronización nativa, los identificadores y la firma deben asociar correctamente ambas apps; no se garantiza la asociación con la versión re-firmada por SideStore.
8. Inicia sesión en el iPhone con el mismo correo de tu copia, restáurala y abre ambas apps. Añade la complicación desde la edición de tu esfera, o el widget desde la Smart Stack. Los cambios offline se guardan en el Watch y se confirman cuando el sistema permite comunicar ambos dispositivos; no hay entrega instantánea garantizada si están apagados o la app está forzada a cerrar.

## Evitar la renovación semanal

- **Apple ID gratuito / Personal Team:** Apple indica que los perfiles de desarrollo caducan a los **7 días**. Necesitas volver a firmar e instalar; no existe en este proyecto un método gratuito de firma oficial permanente. Las restricciones de capacidades de la cuenta gratuita también pueden impedir la complicación con grupo compartido.
- **Apple Developer Program:** permite firmar con las capacidades necesarias y distribuir mediante Apple. La firma de desarrollo o ad hoc sigue teniendo una fecha de caducidad (consulta el perfil; habitualmente hasta un año). Pagar la suscripción no vuelve permanente un archivo de desarrollo.
- **App Store para Apple Watch:** es la vía normal para una app que no requiere renovaciones semanales de su firma de desarrollo. Hace falta pertenecer al programa, configurar App Store Connect, enviar una compilación firmada y obtener aprobación de Apple. No hay una publicación de App Store creada en esta release.
- **TestFlight:** sirve para pruebas y cada compilación caduca a los **90 días**; no es una instalación permanente.

Documentación oficial: [comparar cuentas Apple](https://developer.apple.com/support/compare-memberships/), [configurar un proyecto watchOS](https://developer.apple.com/documentation/watchos-apps/setting-up-a-watchos-project), [TestFlight](https://developer.apple.com/testflight/).

## Datos, costes y protección

El iPhone es la fuente de los datos. El Watch recibe una selección de los próximos negocios, existencias, saldo y resumen de hoy; no recibe correo, contraseña, clave de Google Places ni foto de perfil. Las acciones llevan un identificador único, sesión y revisión del negocio. Los reenvíos no duplican ventas; si otra edición cambia la ficha, se rechaza la acción pendiente y se informa en el Watch. Restaurar o deshacer en el iPhone invalida la sesión anterior. Las confirmaciones se guardan aparte de las copias para evitar reenvíos después de restaurar.

El beneficio de tarjetas utiliza el coste medio de las compras registradas y conserva el coste al guardar la venta. Una venta antigua sin coste capturado se reconstruye con las compras disponibles; si falta un producto o coste, se indica que no puede calcularse. Los demás gastos permanecen en el saldo general.
