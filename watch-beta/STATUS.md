# Estado verificado — 28 de octubre de 2026

## Publicado

- Variante personal: 0.7.1, build 711.
- Código compilado: 415146c926d97b25d77eed3f22cc48cd95cd21cc.
- GitHub Actions: https://github.com/polaca1/rese-a-google/actions/runs/40708361679
- SHA-256 del IPA: 86b67ceeecb92219429d1a8e5aedf18bb704dc67a4731189e49191228747ddaf
- Tamaño: 32300089 bytes.
- Descarga: https://github.com/polaca1/rese-a-google/releases/download/sidestore-watch-beta-0.7.1-build711/SideStore-Watch-Beta-0.7.1-build711.ipa
- Fuente compatible: https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore-watch-source/source-compatible.json
- Ambas fuentes y SOURCE-PROVENANCE.json se comprobaron después de publicar.
- La publicación comprueba los bytes públicos por tamaño, SHA-256, CRC ZIP e identidad del host, y valida el payload nativo.
- 43 comprobaciones de modelos/validación y pruebas del framing ZIP; compilaciones reales de iPhone y watchOS 10, incluida arm64_32.
- No hay prueba física de instalación de esta versión ni perfil de watchOS aceptado por la cuenta gratuita del usuario.

## Implementado

Se conserva el SideStore completo del iPhone y su identidad original, widgets, SideBackup y atajos de datos móviles. La instalación normal prepara y firma los componentes de Watch/ y sus extensiones con IDs ya existentes, conserva una cola antes de instalar el host y envía las apps tras la instalación. Una autoactualización conserva los trabajos pendientes y comprueba la versión del host al volver a arrancar. Requiere Idevice TCP y un único Watch. No desinstala previamente las apps del reloj.

El recurso WatchBootstrap.ipa incluido en el host contiene un prototipo nativo para watchOS 10. Al abrir el host se intenta firmar e instalar con un ID real de la cuenta, sin crear IDs de Watch. El prototipo informa de su apertura por WatchConnectivity y prueba si el puerto local 62078 es accesible. No ejecuta firma ni instalación desde el reloj. No constituye todavía la tienda autónoma solicitada.

Las actualizaciones de la variante se buscan al abrirla desde las dos URLs permitidas. Se usa la versión del binario en ejecución, no solo los metadatos de Core Data, para evitar reinstalaciones o retrocesos. Se sigue el catálogo de la fuente añadida aunque la asociación anterior conserve la fuente oficial. Se mantienen las comprobaciones y posibles solicitudes del instalador original. No se garantiza ejecución en segundo plano.

## Hechos recibidos del usuario

- SideStore original 0.7.0, LocalDevVPN y refresco sobre 5G funcionan.
- Tres apps activas y App IDs agotados. No crear IDs de prueba ni revocar certificados.
- WatchOS 10.6.2, conectado al iPhone, sin Wi-Fi propio.
- 706: conexión, detección y cuenta correctas; un Watch; freeAccount=true; perfil fallido sin detalle.
- 707: existingAppIDMissing en listAppIDs. No llegó a solicitar el perfil; no demuestra incompatibilidad de la cuenta gratuita.
- 711 permite resolver el ID a partir de la firma incluida y elegir entre los IDs reales de Apple. No se ha recibido aún su resultado físico.
- Se preguntó si actualiza SideStore directamente o ejecuta la beta dentro de LiveContainer. Pendiente: no asumir identidad y asociación del host virtual.
- Se solicitó probar 711 y devolver el nuevo diagnóstico o el texto de Servicio local del componente del Watch.
- No realizar llamadas: el usuario pidió resolver dudas por chat.

## Pendiente para el objetivo autónomo

1. Confirmar el modo real de instalación, el ID válido y un perfil de watchOS aceptado, con las cuotas actuales.
2. Verificar instalación y apertura del componente en el Watch físico.
3. Si el servicio local es accesible, comprobar su protocolo y autenticación desde el reloj; conectar un puerto no demuestra acceso al instalador.
4. Portar y compilar el login, la firma, las dependencias y el cliente de instalación en watchOS. CodeSignKit y GSACryptoKit declaran watchOS; AnisetteKit declara iOS/macOS y su integración completa no se ha verificado en Watch. La declaración de plataformas no acredita el recorrido funcional.
5. Probar instalación y reemplazo iniciados y ejecutados desde el Watch, renovación real de la fecha de un perfil y recuperación. No presentar la refirma en iPhone como autonomía de watchOS.
6. Solo después completar las funciones e interfaz de tienda del Watch. No añadir botones que aparenten ejecutar acciones inexistentes.

## Reproducción y alcance

La rama de trabajo es work/watch-automatic, en el repositorio propio del usuario; no es una contribución al upstream. La rama beta/sidestore-watch conserva la etapa anterior. Se preservan las licencias originales y la licencia MIT del transporte adaptado de Rzbck/isideload, incluida dentro del IPA y del código.

El entorno local falló al iniciar el 28 de octubre. Las ediciones actuales se realizaron mediante las herramientas Git de GitHub y se validaron con macOS/Xcode en Actions. El código publicado y su ZIP corresponden al SHA indicado; esta nota no cambia ese binario.
