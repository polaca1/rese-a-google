Beta personal 0.7.1 (711), independiente del proyecto oficial SideStore.

La instalación normal del IPA de iPhone detecta sus componentes Watch/, obtiene sus perfiles y los firma antes del host. Los componentes firmados se conservan en una cola para enviarlos al reloj al completar la instalación. Una autoactualización que cierre SideStore conserva la cola y la retoma al abrir la nueva versión.

El IPA contiene también un componente nativo para watchOS 10 (arm64_32 y arm64). Al abrir SideStore se intenta preparar e instalar con un App ID ya registrado en tu cuenta. Es una prueba nativa de apertura y acceso al servicio local del reloj. TODAVÍA NO ES LA TIENDA AUTÓNOMA SOLICITADA NI FIRMA DESDE EL WATCH. La cuenta del usuario aún no ha demostrado un perfil válido o instalación física.

La prueba de perfil usa preferentemente el identificador de la firma incluida, no presupone que Info.plist tenga el mismo ID, y ofrece elegir un identificador de la lista real de Apple. No crea App IDs para Watch ni revoca certificados. Un perfil rechazado detiene la operación; no se inventan estados correctos.

La beta comprueba actualizaciones de su propia fuente al abrirse y puede instalarlas con el flujo original de SideStore cuando la cuenta, la red, la firma y los permisos lo permitan. No actualiza desde fuentes ajenas. Puede desactivarse en Watch beta. No se garantiza ejecución en segundo plano de iOS.

Requisitos: un único Watch enlazado y desbloqueado, backend Idevice con emparejamiento TCP, certificado activo y App IDs/perfiles de watchOS válidos para cada app y extensión. Actualiza sobre SideStore sin borrar la app y con la misma cuenta Apple.

Se conservan Apple ID, fuentes, instalación/refirma de iPhone, widgets, SideBackup y atajos de datos móviles originales. Licencias y atribuciones incluidas; transporte adaptado de Rzbck/isideload bajo MIT. Fuente completa en esta release y en work/watch-automatic / beta/sidestore-watch según la fase publicada.
