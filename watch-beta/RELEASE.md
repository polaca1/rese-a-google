Beta personal e independiente basada en la app completa de SideStore. No es una versión oficial ni está respaldada por sus mantenedores.

REUTILIZA EL IDENTIFICADOR DE SIDESTORE: se instala sobre el SideStore actual con la misma cuenta Apple. No borrar la app antes de actualizar ni cambiar su bundle ID al firmar. Conserva los IDs del host y extensiones. No ocupa una cuarta app activa. Reinstalar la versión oficial con la misma identidad permite volver a la base; no se ha probado esta transición en el dispositivo del usuario.

Conserva login Apple ID, fuentes, instalación, refirma, autorrenovación y los atajos existentes para datos móviles. No requiere cambiar los nombres TurnOffData y TurnOnData si ya funcionan. Las preferencias de datos móviles están en Settings → User Customizations → Cellular Refresh.

En Settings, el icono del reloj abre pruebas reales de detección y perfil. «Probar perfil con ID de SideStore» busca el identificador ya registrado de la instalación actual: nunca crea App IDs ni revoca certificados. Puede registrar el Watch como dispositivo de desarrollo y solicitar un perfil con el indicador watchos. El resultado se acepta solo si declara watchOS y corresponde al ID, equipo y reloj correctos. Reutilizar un ID iOS no garantiza que Apple entregue un perfil válido de watchOS.

ESTA PRIMERA BETA NO INCLUYE UNA TIENDA NATIVA NI REFIRMA AUTÓNOMA EN EL WATCH. La instalación y renovación del reloj siguen pendientes. Es una herramienta de diagnóstico en iPhone para estudiar esa vía; todavía no cumple el objetivo final del usuario.

El ZIP incluye fuente, licencia, atribuciones y parches de dependencias. Ninguna credencial ni archivo de emparejamiento forma parte del código distribuido.
