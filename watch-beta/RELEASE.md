Beta personal 0.7.1 (716), independiente del proyecto oficial SideStore.

El diagnóstico real de 715 llegó al Watch y mostró «Confiar», pero falló en Pair (código 13). No demuestra instalación ni incompatibilidad de la cuenta gratuita.

Nuevo botón «Instalar SideStore en el Watch»: detecta, elige únicamente un ID secundario ya existente de SideStore, prepara el perfil, firma el paquete incluido y lo envía. No hay que importar un IPA ni escribir una IP. El intento automático al abrir sigue disponible; los trabajos manuales no se solapan.

El emparejamiento prepara una sola identidad criptográfica y la conserva al repetir el mismo intercambio tras una desconexión de transporte (máximo dos reconexiones). No reintenta una denegación de confianza ni un rechazo del protocolo. Guarda únicamente el registro aceptado del Watch, separado por reloj e identidad, en Application Support privado, con protección del dispositivo, permisos restringidos y exclusión de copias de seguridad. Reutiliza ese registro en siguientes sesiones. No desinstala apps ni crea App IDs o certificados.

El diagnóstico distingue confianza rechazada, reloj bloqueado, respuesta no admitida, desconexión y preparación del registro; nunca exporta claves, perfiles, identificadores ni respuestas completas.

Se conserva el SideStore completo de iPhone, fuente y actualización, widgets, SideBackup, anisette remoto predeterminado y atajos de datos móviles. El componente nativo de watchOS 10 incluido sigue siendo una prueba de apertura/servicio local: no es todavía una tienda autónoma ni ejecuta firma desde el reloj.

Instalación física y renovación pendientes de prueba en el reloj del usuario. No se presenta esta beta como definitiva.
