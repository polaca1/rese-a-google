# Instalación y renovación del Apple Watch: comprobado el 26 de octubre de 2026

El modo desarrollador habilita ejecutar apps de desarrollo. No sustituye el certificado, el perfil del reloj ni la capacidad del instalador para conservar y firmar la app de watchOS. La instalación automática de apps compatibles de Apple Watch tampoco firma paquetes.

El código actual de SideStore y su dependencia SideSign prepara la app principal y sus extensiones PlugIns/*.appex. No prepara el paquete Watch ni su perfil de aprovisionamiento. Añadirlo al IPA habitual no demuestra una instalación o renovación correcta, por lo que esta actualización mantiene un IPA compatible de iPhone.

- SideStore revisado: https://github.com/SideStore/SideStore/tree/cd260851ae99bf1fc946b123db24e89c8cd21dc6
- SideSign usado por esa revisión: https://github.com/SideStore/SideSign/blob/752d1ef602aa792a432ffa1e71646dc1ecf7363c/Sources/Models/AppBundle.swift#L119
- Preparación de perfiles: https://github.com/SideStore/SideStore/blob/cd260851ae99bf1fc946b123db24e89c8cd21dc6/SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift
- Modo desarrollador: https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device

## Alternativa encontrada

Sideloadly 0.71.0 anuncia firma y procesamiento de apps de Apple Watch para cuentas inscritas en Apple Developer Program. Indica expresamente que el soporte para cuentas gratuitas llegará en otra versión. No confundirlo con la nota de 0.70.1 que simplemente conserva y vuelve a firmar los bundles WatchKit.

Sideloadly también dispone de renovación automática mediante su daemon. Su FAQ exige un Mac o PC encendido y el iPhone detectado por USB o por la misma red Wi-Fi. La firma y renovación específicas de nuestra app en un reloj real requieren comprobarse después de elegir y configurar esa vía; las pruebas del simulador no las demuestran.

Fuentes: https://sideloadly.io/changelog y https://sideloadly.io/faq.html.

No se ha encontrado una alternativa verificada que renueve gratuitamente una app nativa de Watch utilizando solo el iPhone y SideStore. No se han comprado cuentas, certificados ni suscripciones.

Si se prepara posteriormente el paquete complementario para una vía compatible, su icono será plano, sin Liquid Glass, conforme a la preferencia del usuario. Mantendrá un bundle ID hijo de la app de iPhone y versiones coordinadas, y se verificará de forma independiente antes de distribuirlo.

## Cuenta gratuita: alternativa de instalación con Xcode

Se ha preparado el complemento nativo en `watchos/reviewNfcGoWatch.xcodeproj` con un puente de datos en el candidato iPhone 7.2. La firma inicial puede gestionarla Xcode con Personal Team en un Mac compatible. No se anuncia renovación automática: el perfil gratuito caduca y necesitará renovarse. El reloj no recibe credenciales del servicio. La instalación física sigue pendiente de comprobar el Mac y el reloj del usuario.

Las instrucciones y el helper que adapta los identificadores reales del teléfono están en `watchos/LEEME.md` y `watchos/Scripts/configure-watch.py`. El helper rechaza identificadores inválidos o varias instalaciones posibles y no selecciona una cuenta de Apple por suposiciones.
