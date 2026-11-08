Variante personal SideStore Watch 0.7.1 (720), con identidad propia.

App iPhone: com.SideStore.SideStore.PabloWatch. App Watch: el identificador REAL de la app del iPhone, incluido el sufijo añadido al firmarla, más .watch. Apple requiere dos App IDs distintos y relacionados; no se comparte literalmente un solo ID entre iPhone y reloj.

Se instala aparte del SideStore actual. El instalador prepara el ID de iPhone y del widget; el botón de Apple Watch comprueba su ID dedicado, lo registra en la cuenta iniciada si falta y hay cupo, solicita su perfil y lo usa al firmar. No toma el ID del widget ni el de otra app. Los reintentos de registro incierto consultan el resultado y no repiten el envío a ciegas. Una cuota agotada se explica de forma específica.

Los grupos, el servicio de llavero, la base de datos, la identidad del helper/widget y las URLs propias corresponden a esta variante. Un grupo heredado permite que el instalador anterior preserve también el grupo propio. El certificado embebido por el instalador de SideStore se recupera si falta en memoria; esta función no revoca certificados ni los copia desde otra app.

Instalar desde el SideStore actual. Al ser otra app, requiere una plaza de app activa disponible y App IDs disponibles; el widget también tiene su identificador. Las sesiones y archivos privados del SideStore anterior no se copian automáticamente a través del aislamiento de iOS: iniciar sesión y configurar una vez el emparejamiento del iPhone en esta nueva variante. Después pulsar Instalar SideStore en el Watch, sin elegir ID ni importar un IPA del reloj. La confirmación Confiar, si aparece, debe aceptarse en el dispositivo.

El componente nativo del Watch sigue siendo una prueba de apertura/servicio local, no una tienda autónoma ni un motor de firma de watchOS. La instalación física y la renovación siguen sin verificarse. Esta versión resuelve la identidad propia y su registro automático; no demuestra por sí sola que haya resuelto InvalidPairRecord.

Incluye el código de recuperación de emparejamiento de 719. No modifica las fuentes automáticas de la variante anterior.
