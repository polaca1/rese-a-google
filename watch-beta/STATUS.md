# Estado verificado — 28 de octubre de 2026

## Publicado

- Variante personal: 0.7.1, build 714.
- Código compilado: f693c62a5d4efeb1aac3c91303e434b0f631121d.
- GitHub Actions: https://github.com/polaca1/rese-a-google/actions/runs/40728252552
- SHA-256 del IPA: a7109cb49d70094ef5010241b7b569a20a1ab76202e0b729abd049a58003825d
- Tamaño: 32324153 bytes.
- Descarga: https://github.com/polaca1/rese-a-google/releases/download/sidestore-watch-beta-0.7.1-build714/SideStore-Watch-Beta-0.7.1-build714.ipa
- Fuente compatible: https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore-watch-source/source-compatible.json
- Ambas fuentes y SOURCE-PROVENANCE.json se comprobaron después de publicar.
- La publicación comprueba los bytes públicos por tamaño, SHA-256, CRC ZIP e identidad del host, y valida el payload nativo.
- 89 comprobaciones de modelos/validación y pruebas del framing ZIP; compilaciones reales de iPhone y watchOS 10, incluida arm64_32.
- El usuario ha confirmado un perfil válido para su Watch con cuenta gratuita y el ID existente de reviewNfcGo .liveactivity. La instalación falla después. Aún no hay instalación física ni renovación verificadas.

## Implementado

714: diagnóstico schema 5 con pasos separados de firma, conexión y transporte. El Rust FFI ya no colapsa todo a 4: conserva códigos fijos para emparejamiento, sesión, apertura de streaming_zip_conduit, envío/confirmación, timeout y una lista de rechazos de watchOS. Swift solo interpreta el formato fijo completo del bridge, nunca exporta mensajes arbitrarios. Se comprueba por DER que el certificado activo está incluido en el perfil; no se crean/revocan certificados. Se bloquean solapamientos entre cola automática y pantalla/operación manual. El bootstrap de SideStore elige únicamente un hijo existente de su ID (.watch/.SideBackup/.AltWidget), no el ID manual de reviewNfcGo. La apertura del bootstrap no sobrescribe el resultado de una app importada. 89 pruebas y verificación de framing/CRC/categorías nativas; compilaciones reales y publicación verificadas.

713: On-Device Anisette desactivado por defecto y https://mac-ani.jkcoxson.com seleccionado/habilitado, tanto en instalación nueva como mediante migración única de instalaciones anteriores. Cambios posteriores del usuario se respetan. El preset se conserva aunque falte en una sincronización del catálogo. Se preservan credenciales/certificados/IDs. El diagnóstico schema 4 conserva la detección correcta del Watch ante errores posteriores de cuenta y distingue resolveTeam, fetchAnisette y listAppIDs con categorías fijas y código numérico. No se exportan mensajes completos ni identificadores. Las 70 pruebas cubren la regresión y la migración.

Se conserva el SideStore completo del iPhone y su identidad original, widgets, SideBackup y atajos de datos móviles. La instalación normal prepara y firma los componentes de Watch/ y sus extensiones con IDs ya existentes, conserva una cola antes de instalar el host y envía las apps tras la instalación. Una autoactualización conserva los trabajos pendientes y comprueba la versión del host al volver a arrancar. Requiere Idevice TCP y un único Watch. No desinstala previamente las apps del reloj.

El recurso WatchBootstrap.ipa incluido en el host contiene un prototipo nativo para watchOS 10. Al abrir el host se intenta firmar e instalar con un ID real de la cuenta, sin crear IDs de Watch. El prototipo informa de su apertura por WatchConnectivity y prueba si el puerto local 62078 es accesible. No ejecuta firma ni instalación desde el reloj. No constituye todavía la tienda autónoma solicitada.

Las actualizaciones de la variante se buscan al abrirla desde las dos URLs permitidas. Se usa la versión del binario en ejecución, no solo los metadatos de Core Data, para evitar reinstalaciones o retrocesos. Se sigue el catálogo de la fuente añadida aunque la asociación anterior conserve la fuente oficial. Se mantienen las comprobaciones y posibles solicitudes del instalador original. No se garantiza ejecución en segundo plano.

## Hechos recibidos del usuario

- SideStore original 0.7.0, LocalDevVPN y refresco sobre 5G funcionan.
- Tres apps activas y App IDs agotados. No crear IDs de prueba ni revocar certificados.
- WatchOS 10.6.2, conectado al iPhone, sin Wi-Fi propio.
- 706: conexión, detección y cuenta correctas; un Watch; freeAccount=true; perfil fallido sin detalle.
- 707: existingAppIDMissing en listAppIDs. No llegó a solicitar el perfil; no demuestra incompatibilidad de la cuenta gratuita.
- 711: usuario confirma que SideStore no aparece en el Watch; informe invalidProfile, cuenta/conexión/discovery correctas, perfil fallido, instalación y renovación pendientes. El informe no distinguía el motivo del rechazo.
- 712 corrige la exigencia incorrecta de etiqueta literal watchOS: permite perfiles de familia iOS solo si coinciden App ID, cuenta y Watch, están vigentes y contienen certificado. Añade diagnóstico schema 3 con categorías allowlisted y booleanos, sin datos privados. Se conserva por separado el resultado de perfil del instalador automático. La cola valida la cuenta contra la sesión actual.
- Justificación y caso instalado documentado por el autor: https://github.com/ryakel/boomerang/wiki/iOS-Native-App#the-watch-must-be-in-the-signing-profile
- La causa concreta de invalidProfile en el perfil del usuario no se pudo conocer en 711. La comprobación corregida podía producir ese rechazo; el siguiente intento no llegó al perfil.
- 712: usuario devuelve pairedWatchCount=1, connection=passed, discovery=failed, account/profile/install pending y discoveryFailed. El código demuestra que la captura de errores etiquetaba como discovery también fallos posteriores en cuenta/Anisette/listAppIDs. No es prueba de que se perdiera el Watch ni permite saber el error subyacente.
- El usuario pide desactivar ODA y elegir por defecto https://mac-ani.jkcoxson.com, URL confirmada explícitamente en chat. Implementado en 713; pendiente comprobar la sesión de su cuenta con ese servidor.
- El usuario confirma que la beta está instalada directamente sobre SideStore; NO se ejecuta dentro de LiveContainer.
- Siguiente prueba: actualizar sobre SideStore a 713 sin borrar, abrir Watch beta con Watch desbloqueado/cerca, detectar; si la cuenta falla, copiar schema 4/accountDiagnostic. Si cuenta e IDs funcionan, probar perfil y copiar profileChecks; comprobar si aparece el componente del Watch.
- No realizar llamadas: el usuario pidió resolver dudas por chat.

## Pendiente para el objetivo autónomo

1. El modo directo sobre SideStore, un ID compatible existente y un perfil aceptado están confirmados para Review. Falta resolver la firma/transporte/instalación posterior y verificar el perfil del bootstrap SideStore con su propio ID.
2. Verificar instalación y apertura del componente en el Watch físico.
3. Si el servicio local es accesible, comprobar su protocolo y autenticación desde el reloj; conectar un puerto no demuestra acceso al instalador.
4. Portar y compilar el login, la firma, las dependencias y el cliente de instalación en watchOS. CodeSignKit y GSACryptoKit declaran watchOS; AnisetteKit declara iOS/macOS y su integración completa no se ha verificado en Watch. La declaración de plataformas no acredita el recorrido funcional.
5. Probar instalación y reemplazo iniciados y ejecutados desde el Watch, renovación real de la fecha de un perfil y recuperación. No presentar la refirma en iPhone como autonomía de watchOS.
6. Solo después completar las funciones e interfaz de tienda del Watch. No añadir botones que aparenten ejecutar acciones inexistentes.

## Reproducción y alcance

La rama de trabajo es work/watch-automatic, en el repositorio propio del usuario; no es una contribución al upstream. La rama beta/sidestore-watch conserva la etapa anterior. Se preservan las licencias originales y la licencia MIT del transporte adaptado de Rzbck/isideload, incluida dentro del IPA y del código.

El entorno local falló al iniciar el 28 de octubre. Las ediciones actuales se realizaron mediante las herramientas Git de GitHub y se validaron con macOS/Xcode en Actions. El código publicado y su ZIP corresponden al SHA indicado; esta nota no cambia ese binario.
