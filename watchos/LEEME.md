# reviewNfcGo para Apple Watch — preparación con cuenta gratuita

Este es el complemento nativo para próximas visitas, negocios, indicaciones y saldo. Su icono es plano y los datos llegan del iPhone mediante WatchConnectivity; el reloj no recibe contraseñas ni tokens de inicio de sesión. No registra ventas por su cuenta.

La instalación se realiza con Xcode en un Mac compatible con el reloj. Xcode puede preparar la firma de desarrollo de una cuenta gratuita (Personal Team). Esa firma caduca: no se anuncia renovación automática verificada del Watch ni una instalación permanente. El modo desarrollador no reemplaza la firma.

La app de iPhone debe incluir el puente complementario (candidato 7.2.0/build 38 de este proyecto). La 7.1.0 publicada en SideStore contiene las mejoras de ventas pero todavía no ese puente. Esta preparación no se publica como si el Watch ya estuviera instalado o renovándose.

## Preparación del Mac

1. Comprueba la versión de macOS, watchOS y la versión de Xcode compatible en https://developer.apple.com/support/xcode/.
2. Abre Xcode → Settings → Accounts y añade tu cuenta Apple gratuita. No compartas su contraseña por el chat.
3. Enlaza el iPhone y el Watch con ese Mac desde la gestión de dispositivos de Xcode. Confirma la confianza y el modo desarrollador cuando lo soliciten. Conserva la app de iPhone instalada.
4. Abre `watchos/reviewNfcGoWatch.xcodeproj`. En Signing & Capabilities deja la gestión automática y elige tu Personal Team.

## Identificadores del complemento

El identificador del Watch y `WKCompanionAppBundleIdentifier` deben corresponder a la app que está realmente instalada en el iPhone. SideStore puede haberla renombrado: no se debe suponer que conserva el identificador original.

El helper local puede consultar solo los metadatos de reviewNfcGo en un iPhone que ya esté enlazado con Xcode:

```sh
python3 watchos/Scripts/configure-watch.py --phone IDENTIFICADOR_DEL_IPHONE
```

El identificador se ve en la lista de dispositivos de Xcode o mediante `xcrun devicectl list devices`. La opción `--phone` corresponde al iPhone, no al Watch. El helper rechaza resultados ambiguos y no firma, instala, compra nada ni lee claves privadas. También admite `--bundle-id IDENTIFICADOR_REAL` y `--dry-run`.

Después abre el proyecto, selecciona el Watch enlazado como destino y pulsa Run. Xcode gestionará el perfil de desarrollo y la instalación si tu cuenta, Mac y reloj son compatibles. Abre reviewNfcGo en los dos dispositivos para recibir los datos. La compilación del simulador no demuestra esta instalación física.

## Renovación

Con una cuenta gratuita necesitarás volver a ejecutar la app desde Xcode cuando corresponda renovar el perfil. No se ha verificado un proceso autónomo de renovación del Watch sin Mac. Si buscas esa automatización, Sideloadly 0.71.0 la documenta mediante su daemon en ordenador, pero su soporte de firma del Watch requiere actualmente Apple Developer Program de pago; su soporte gratuito sigue pendiente.

Fuentes: https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device, https://developer.apple.com/support/compare-memberships/, https://sideloadly.io/changelog y https://sideloadly.io/faq.html.
