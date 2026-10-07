# Probar reviewNfcGo 5.0 con Sideloadly y Apple Watch

Se requiere un ordenador Windows o Mac, un iPhone y un Watch enlazado con watchOS 10 o posterior.

Este procedimiento es una **prueba de instalación y renovación**, pendiente de comprobar en un reloj real. Sideloadly 0.70.1 documenta que conserva y vuelve a firmar los bundles WatchKit, y su daemon renueva automáticamente las apps del iPhone. Eso no demuestra por sí solo que registre y renueve correctamente nuestro Watch y su complicación. Las capacidades y los perfiles de tu cuenta pueden impedir la instalación.

## Preparación

1. En la app instalada, abre Perfil → Copias de seguridad y exporta una copia a Archivos. Conserva la instalación actual hasta comprobar la nueva.
2. Descarga Sideloadly **0.70.1 o posterior** desde https://sideloadly.io/ y el archivo `reviewNfcGo-5.0-build21-iPhone-Watch-Sideloadly.ipa` de la release 5.0. El IPA normal de SideStore no incluye el Watch y el ZIP de Watch tampoco se importa como IPA.
3. En Windows, instala los componentes iTunes/iCloud indicados por la web oficial de Sideloadly. En Mac sigue su instalador. Usa los enlaces oficiales; no hace falta instalar Xcode para intentar esta vía.
4. Conecta el iPhone al ordenador por USB, desbloquéalo y acepta «Confiar». Mantén el Watch enlazado, cerca, desbloqueado y con batería.
5. Activa Modo desarrollador en el iPhone desde Ajustes → Privacidad y seguridad. En el Watch actívalo desde Ajustes → Privacidad y seguridad si aparece; reinicia y confirma cuando se solicite. Si no aparece y la instalación lo exige, conserva el mensaje de error: puede ser necesaria la configuración desde Xcode.

## Instalación de prueba

6. Abre Sideloadly, selecciona tu iPhone y arrastra el IPA que dice **iPhone-Watch-Sideloadly**.
7. Usa la misma cuenta Apple con la que firmas SideStore y habilita la opción de renovación automática. Introduce la contraseña y el código de verificación únicamente en Sideloadly; no los envíes por el chat. Mantén los identificadores coherentes y no actives opciones que eliminen apps del Watch. Si crea otra instalación de iPhone, abre sesión con el correo de tu copia y restáurala ahí.
8. Pulsa Start. Espera a que Sideloadly confirme la instalación; guarda el registro si falla. Confía en la app de desarrollo desde Ajustes → General → VPN y gestión de dispositivos si se solicita.
9. Abre Watch en el iPhone → Mi reloj. Si reviewNfcGo aparece en Apps disponibles, pulsa Instalar. Si aparece como instalada, ábrela directamente en el reloj. Si no aparece, este intento no ha instalado la versión Watch: no es evidencia de que la renovación funcione. En ese caso necesitamos el error o registro, y sigue disponible la vía Xcode de WATCH-INSTALL.md.
10. Abre reviewNfcGo en el iPhone y el Watch. Desde Perfil → Apple Watch → Sincronizar ahora comprueba que el reloj muestra tus negocios. Verifica una acción sencilla antes de usar las ventas reales. Si aparece la app pero la complicación queda vacía, puede faltar la autorización del grupo compartido.

## Renovación y cómo comprobarla

11. Habilita la conexión Wi-Fi: en Windows, iTunes → iPhone → Resumen → Opciones → Sincronizar con este iPhone vía Wi-Fi; en Mac, Finder → iPhone → General → Mostrar este iPhone cuando esté conectado a Wi-Fi. Aplica o sincroniza los cambios.
12. Deja Sideloadly Daemon activo al iniciar el ordenador. Para renovar, el ordenador debe estar encendido y el iPhone detectado por Wi-Fi en la misma red o por USB. Desbloquea el iPhone si lo pide.
13. Prueba primero una renovación manual desde el menú del daemon y revisa su registro. Comprueba que ambas apps se siguen abriendo; si falla, no esperes a que caduquen.
14. **La renovación automática del Watch solo queda comprobada si su app sigue funcionando después del vencimiento de su primer perfil, sin reinstalarla con Xcode.** El contador o el éxito de renovación del iPhone por sí solos no lo demuestran. Con cuenta gratuita el plazo normal es 7 días.

No es una instalación permanente ni funciona con el ordenador apagado todo el tiempo. La fuente de SideStore sigue distribuyendo su IPA normal de iPhone. No alternes la renovación del paquete combinado entre varios instaladores mientras pruebas qué firma y qué perfiles conserva cada uno.

Fuentes: https://sideloadly.io/changelog y https://sideloadly.io/faq.html.
