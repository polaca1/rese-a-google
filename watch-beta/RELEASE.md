Beta personal 0.7.1 (713), independiente del proyecto oficial SideStore.

On-Device Anisette desactivado de fábrica y servidor https://mac-ani.jkcoxson.com seleccionado y habilitado. Se aplica una migración única sobre instalaciones anteriores; las preferencias que cambies después se conservan. El servidor permanece en la lista aunque no aparezca en una sincronización del catálogo comunitario. No se modifican claves, certificados, App IDs ni credenciales.

Corrige discoveryFailed después de haber detectado el Watch: los fallos al obtener cuenta, sesión/Anisette o App IDs se muestran en Cuenta Apple sin borrar la detección correcta. El diagnóstico schema 4 incluye paso, categoría fija y código numérico, sin datos privados ni errores completos del servidor.

Conserva las validaciones de 712: un perfil de familia iOS puede autorizar watchOS si coinciden App ID, cuenta y Watch, está vigente y tiene certificado. Un perfil que solo incluya el iPhone se rechaza.

Se conserva el SideStore completo de iPhone, identidad original, fuentes, Apple ID, instalación/renovación, widgets, SideBackup y atajos de datos móviles. Actualiza sin borrar SideStore y usando la misma cuenta.

El componente de watchOS 10 incluido sigue siendo una prueba nativa de instalación, apertura y servicio local. NO es todavía una tienda autónoma ni firma desde el Watch. No hay instalación física ni renovación verificadas con la cuenta gratuita del usuario.

Código completo y licencias incluidos. Transporte adaptado de Rzbck/isideload bajo MIT.
