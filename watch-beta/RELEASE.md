Beta personal 0.7.1 (715), independiente del proyecto oficial SideStore.

El informe real de 714 confirmó perfil y certificado correctos, pero el instalador se detenía explícitamente con unsupportedPairing al usar RPPairing. Esta versión implementa la ruta remota; no se limita a quitar ese bloqueo.

Reutiliza el adaptador y la sesión RSD autenticados del iPhone para abrir companion_proxy y los puertos reenviados del Watch. El propio Watch realiza Pair/StartSession y proporciona su registro real para proteger la transferencia. El identificador persistente del host remoto se reutiliza para el emparejamiento del reloj; no se inventa un archivo TCP ni se convierten claves Ed25519 a certificados Lockdown. Los manejadores del túnel se toman prestados durante la llamada y siguen perteneciendo al gateway original.

Se conserva la ruta TCP, selección exacta de un único Watch, validaciones de cuenta/ID/dispositivo/certificado y confirmación DataComplete. No desinstala apps, crea App IDs ni revoca certificados. Conserva los códigos de error por paso de 714. La conexión y la aceptación del Watch por esta ruta requieren prueba física; el túnel por sí solo no demuestra instalación.

Mantiene el SideStore completo de iPhone, su identidad y actualizaciones, Apple ID, fuentes, SideBackup, widget, atajos de datos móviles y el preset Anisette solicitado. Conserva la coordinación de cola automática y pruebas manuales.

Actualiza sobre SideStore sin borrar la app y usando la misma cuenta. Usa el IPA Review ReuseID e ID .liveactivity existentes. Si aparece una solicitud de confianza en el Watch, atiéndela. La instalación y sincronización físicas siguen pendientes de verificar.

El componente SideStore de watchOS 10 continúa siendo un prototipo de apertura/servicio local: NO es una tienda autónoma ni ejecuta firma desde el reloj. Licencias y código fuente completos incluidos.
