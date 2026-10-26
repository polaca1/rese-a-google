# reviewNfcGo 7.0 — clientes y tarjetas actualizables

## Qué hace

Inicio mantiene su función principal. Escribir NFC prepara un enlace HTTPS fijo del cliente y abre Simply NFC. La URL que queda en la etiqueta es `link.html?id=UUID`, no el enlace directo de Google. Su destino inicial es la reseña de Google con el Place ID del negocio; después el propietario puede cambiarlo, restaurar ese destino, desactivarlo o reactivarlo desde iPhone o Mac.

La memoria de una etiqueta bloqueada no cambia. La redirección se resuelve por Internet al abrir ese enlace fijo. Una tarjeta que ya guarda Google directo no puede transformarse remotamente: requiere reescritura si es posible, o una etiqueta nueva si quedó bloqueada. Desactivar impide futuras resoluciones del enlace; no puede retirar una página que alguien ya abrió ni desactivar Google.

Cada cliente comparte un enlace entre sus tarjetas. Las estadísticas son de ese enlace, incluidas aperturas desde enlaces compartidos; no distinguen cada etiqueta física ni identifican personas únicas o reseñas publicadas.

## Usar la app

1. Selecciona el negocio en Inicio y pulsa Escribir NFC.
2. Se prepara el enlace de tu cuenta. Si ya existe, se conserva su URL y su destino actual, sin sobrescribir cambios de otro dispositivo.
3. Escribe la etiqueta con Simply NFC. Al volver confirma si se grabó; abrir el escritor no cuenta por sí solo como escritura correcta. Una preparación pendiente puede confirmarse después desde su historial.
4. En Sitios elige Todos, Clientes o Visitas. Clientes se basa en las ventas vigentes del modelo económico, incluidas tarjetas u otros productos, aunque después se programe otra visita.
5. Abre la ficha para ver el enlace confirmado, ventas, visitas y el acceso a Tarjeta y estadísticas.
6. Cambia el destino o el interruptor de actividad y pulsa Guardar. Usar la reseña de Google restaura el Place ID del negocio. El cambio se aplica en la próxima apertura del enlace; no requiere regrabar ni desbloquear NFC.
7. Mis tarjetas lista los enlaces privados del propietario y permite gestionarlos aunque ya no exista su ficha local. No crea clientes ficticios al recuperar un enlace.

Las visitas al cliente son registros explícitos del historial o llegadas existentes. No se inventan visitas por guardar un negocio, vender o abrir el enlace NFC. Una llegada que ya tiene un evento no se cuenta dos veces.

## Backend y despliegue

Migración: `server/cloud/major7/ACTIVAR-ESTADISTICAS.sql`. Es aditiva, idempotente y no modifica cuentas, contraseñas, ventas ni copias. Conserva los UUID existentes de enlaces. Se necesita acceso administrativo al proyecto Supabase para ejecutarla; la publishable key no permite modificar el esquema.

- Proyecto existente: `tmcccadamceaboyjwxlx`.
- El agente puede aplicar la migración mediante Supabase conectado y verificar permisos/funciones sin leer datos de usuarios reales.
- Alternativa manual: abrir https://supabase.com/dashboard/project/tmcccadamceaboyjwxlx/sql/new, pegar la migración y ejecutar Run una vez.
- No crear un segundo proyecto ni configurar servidor en cada instalación.
- El portal conserva la URL pública anterior: https://polaca1.github.io/rese-a-google/link.html.
- Publicar juntos `link.html`, `card-link.js` y `card-link.css` en la raíz de la rama sidestore. GitHub Pages ya debe servir esa rama. El portal nuevo usa el contador y conserva una lectura antigua sin contador como alternativa si este falla; ambos respetan la pausa.
- El marcador HTML del lector antiguo conserva la comprobación de disponibilidad de versiones anteriores de la app.

No publicar el IPA como una actualización completamente activada hasta verificar migración y portal. El workflow admite `publish=false` para compilar, ejecutar pruebas y obtener artefactos sin modificar las releases ni la fuente. Con `publish=true` publica después de todas las verificaciones. La opción de solo Mac también respeta publish.

## Privacidad y contadores

`reviewnfcgo_links` permanece bajo RLS por auth.uid(). El cliente utiliza la sesión real de AuthStore en iPhone y la sesión de Mac; no una instancia de autenticación vacía. Los cambios de destino se condicionan a la revisión leída para no pisar otro dispositivo. Un índice único impide crear dos enlaces nuevos para el mismo cliente desde dos dispositivos a la vez.

Solo el propietario puede consultar sus estadísticas. El lector público solo resuelve el destino activo de un token conocido; no devuelve usuarios, ventas, etiquetas privadas o copias.

No se guardan IP, geolocalización, cookies ni identificadores persistentes de visitantes. Hay contadores diarios permanentes y UUID de solicitud aleatorios para deduplicar reintentos durante siete días. La limpieza de esos recibos es acotada y no elimina los totales. Las aperturas no demuestran una reseña ni una visita física y pueden incluir tráfico automatizado.

El total y los últimos 7/30 días se calculan en el servidor. La gráfica usa días UTC. Los errores de red o permisos no se muestran como cero aperturas. No hay histórico inventado anterior a la activación.

El manifiesto de privacidad incluye interacción del producto para funcionalidad y analítica del enlace, asociada a la cuenta del propietario; no se activa tracking entre apps ni identificación de visitantes.

## Formato de cuenta y versiones

VisitRecord añade una lista opcional de escrituras con URL fija, destino inicial, fecha y estado preparada/confirmada/cancelada. Las copias antiguas sin esa lista siguen decodificándose y no se les atribuyen escrituras imaginarias. Confirmar no modifica dinero ni stock. La sesión y los datos siguen guardándose automáticamente.

Se recomienda actualizar iPhone a 7.0 y Mac a 3.0: una versión antigua puede ignorar y no conservar metadatos nuevos al volver a guardar una copia completa. Los destinos y contadores remotos no dependen de que la app permanezca abierta.

## Validación

- PostgreSQL real aislado: migración repetible, enlaces existentes, pausa, cambios sin cambiar token, revisiones, roles, permisos, deduplicación, concurrencia y retención de totales. No se utilizan cuentas reales.
- Navegador Chromium: redirección y contador, token NFC idéntico con destinos distintos, pausa sin alternativa a Google, compatibilidad del lector anterior, configuración inválida, bucles y errores. Red simulada, sin aperturas de usuarios reales.
- Swift: datos, clientes, visitas, escrituras, compatibilidad de copias y validación de estadísticas.
- Mac nativo: peticiones autenticadas de tarjetas, creación reutilizable, conservación del destino y pausa, conflictos, lectura privada, identidad y fallos sin contadores ficticios.
- iPhone nativo: capturas de estadísticas, controles de destino, clientes, visitas e historial con fixtures aislados. No se presenta como una escritura física de etiqueta ni como cifras de producción.
- La publicación incluye las capturas de esta compilación en las dos fuentes y sus descargas se comparan por SHA-256.
