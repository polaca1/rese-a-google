Versión personal de recuperación 0.7.1 (719).

Incluye la corrección preparada tras el rechazo InvalidPairRecord de 718. Usa identidades HostID y SystemBUID propias y persistentes para el Watch, conserva las claves antes de solicitar confianza y reutiliza exactamente el registro tras una interrupción o un nuevo intento. No cambia el emparejamiento del iPhone ni crea App IDs.

La pantalla principal tiene un solo botón: Instalar SideStore en el Watch. Resuelve el reloj, el ID secundario existente de SideStore, el perfil y el paquete incluido sin introducir IP, escoger App ID ni importar un IPA. La confirmación Confiar de watchOS, si aparece, requiere al usuario.

El código había pasado 98 pruebas, comprobaciones criptográficas y de intercambio y compilación real de iPhone y watchOS 10. Esta publicación empaqueta esa corrección, que no estaba en el IPA 718. La compilación no demuestra instalación física en el reloj del usuario; sigue pendiente verificar que resuelve su rechazo. No se presenta como versión definitiva ni como instalación físicamente verificada.

Se conserva el SideStore completo de iPhone. El componente del Watch incluido sigue siendo una prueba nativa de apertura y servicio local, no una tienda autónoma ni un motor de firma en watchOS. La renovación física tampoco está verificada.

Actualizar sobre SideStore sin borrar y con la misma cuenta Apple. Mantener el Watch desbloqueado y cerca; abrir Apple Watch y pulsar Instalar SideStore en el Watch. Las fuentes automáticas no se actualizan con este candidato antes de validar el resultado físico.
