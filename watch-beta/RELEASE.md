Beta personal 0.7.1 (714), independiente del proyecto oficial SideStore.

El informe de 713 del usuario demuestra que el perfil ya incluye el Watch y coincide con cuenta y App ID, pero installationFailed mezclaba firma, conexión y transferencia. Esta versión añade diagnóstico schema 5 de cada paso, códigos nativos específicos y categorías fijas de rechazos de watchOS. No incluye respuestas completas ni identificadores privados.

Comprueba que el certificado activo esté realmente incluido en el perfil antes de firmar; tener algún certificado en el perfil no bastaba. Un fallo conserva el detalle de firma, conexión, emparejamiento del Watch, apertura del instalador, transferencia o confirmación. No revoca ni crea certificados.

Evita que la cola automática comience mientras está abierta la pantalla manual o siga una operación manual/cancelada en curso. Los controles manuales esperan a una operación automática ya activa.

La selección de un ID de reviewNfcGo en la prueba manual ya no se reutiliza para SideStore Watch. El componente de SideStore busca exclusivamente un ID hijo ya existente del propio SideStore (.watch, .SideBackup o .AltWidget), mantiene su asociación con el host real y no crea ninguno.

Se conservan el SideStore completo de iPhone, identidad original, Apple ID, fuentes, widgets, SideBackup y atajos de datos móviles. Se mantiene On-Device Anisette desactivado de fábrica y https://mac-ani.jkcoxson.com como preset remoto, sin reimponerlo después de cambios posteriores del usuario.

El componente nativo de watchOS 10 sigue siendo un prototipo de instalación, apertura y servicio local. NO es una tienda autónoma ni firma desde el Watch. El usuario ha validado un perfil con su cuenta gratuita; instalación física y renovación aún no están verificadas.

Actualiza sobre SideStore sin borrar la app y usando la misma cuenta Apple. El IPA de reviewNfcGo Watch adaptado al ID .liveactivity se descarga por separado de la release reviewnfcgo-7.3.0-build39.
