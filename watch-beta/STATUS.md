# Estado de la variante personal de SideStore Watch

## 716 publicada y comprobada

Código compilado: 955652a1bb5bfc328e11fff38d72623ceb496018. Actions https://github.com/polaca1/rese-a-google/actions/runs/40736914981, trabajo 122988037231: success. 94 pruebas, transporte nativo, compilación real iPhone y watchOS 10 arm64_32 aprobadas. IPA público: https://github.com/polaca1/rese-a-google/releases/download/sidestore-watch-beta-0.7.1-build716/SideStore-Watch-Beta-0.7.1-build716.ipa. Tamaño 32336275, SHA-256 a377e793c452137282590e73dfb12321a3bcf97125a3209b105264fd7871a23b. Publicador verificó descarga pública y ambas fuentes. La protección adicional del intercambio evita registrar tanto solicitud como respuesta de confianza.

Pendiente: actualizar sin borrar SideStore, abrir Watch beta, pulsar Instalar SideStore en el Watch con reloj desbloqueado/cerca, aceptar Confiar si aparece. El botón no requiere elegir App ID, IP ni IPA. Falta prueba física; no llamar definitiva ni autónoma a la app del Watch. Siguiente publicación debe ser 717 o posterior.


## 717 publicada — diagnóstico de Pair de 716

Usuario: 716, perfil/certificado válidos, pairWatch/nativeFailure/43, instalación física falsa. Ese código agrupaba UnexpectedResponse/UnknownErrorType; no permite conocer el rechazo concreto.

717 separa campos del registro local y enviado al Watch según libimobiledevice: retira RootPrivateKey, HostPrivateKey y DevicePublicKey solo del intercambio, preserva claves locales. Distingue lista cerrada de rechazos con códigos 50–65 (InvalidPairRecord=51, InvalidCertificate=52, PairingProhibitedOverThisConnection=53, MCChallengeRequired=56); desconocidos siguen 43. No se exportan respuestas libres ni claves. No afirmar que esta diferencia sea la causa demostrada.

Código 47c913deb6a8ae298202bd949e14d3d8f1125591. Actions 40740575604, trabajo 123000738406: success. 98 pruebas; compilaciones iPhone y watchOS aprobadas. Publicador verificó IPA público y ambas fuentes. Tamaño 32336858; SHA256 6c41b9bcfe7097398427dc4006dbc24c8be16c988ca10b5887132057e4a86301. Descarga https://github.com/polaca1/rese-a-google/releases/download/sidestore-watch-beta-0.7.1-build717/SideStore-Watch-Beta-0.7.1-build717.ipa.

Pendiente prueba física: actualizar sin borrar, botón Instalar SideStore en el Watch. Si falla, copiar nuevo diagnóstico. No hay instalación ni renovación ni tienda autónoma verificadas. Siguiente build 718 o posterior. El usuario pidió economizar créditos: cambios y búsquedas mínimos.


## Trabajo 718

Usuario informa 717, perfil/certificado válidos, pairWatch/código51: InvalidPairRecord. Se identifica un defecto comprobable en idevice v0.1.68-ss-3e55c84/ca.rs: genera certificados con Profile::Root para dispositivo y anfitrión; el dispositivo tiene issuer CN=Device aunque firma la clave raíz con subject vacío. Se crea generador específico Watch con raíz y dos hojas consistentes, sin tocar el generador del iPhone. Referencia de convenciones: libimobiledevice src/userpref.c y pymobiledevice3/ca.py. El defecto existe; aún no se ha demostrado que sea el único motivo del rechazo físico.

Se añaden pruebas criptográficas de firmas, claves, extensiones y casos negativos usando el mismo código de producción. La compilación y publicación 718 están pendientes. Instalar solo sobre SideStore sin borrar; no hay autonomía Watch ni instalación/renovación físicas verificadas.
