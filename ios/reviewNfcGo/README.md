# reviewNfcGo 2.9 — Liquid Glass

- Botones nativos `.glass` y `.glassProminent`, controles segmentados, navegación y pestañas de iOS 26.
- Icono con relieve: variante normal azul y variante oscura negra seleccionada por el modo de iconos de iOS. Logo de la interfaz con variantes clara/oscura.
- Tocar un recordatorio o una Live Activity abre la ficha del negocio. Se conserva la ruta durante el inicio de sesión; los negocios eliminados o de otra cuenta muestran un aviso.
- En iOS 26, al guardar una visita futura se solicita una Live Activity programada para visita − 5 horas mediante `Activity.request(..., style: .standard, alertConfiguration: ..., start: ...)`. iOS conserva la solicitud pendiente e inicia la actividad sin necesitar el proceso de la app abierto. Reprogramar, vender, desactivar o borrar cancela la solicitud anterior. Dentro de las cinco horas se inicia inmediatamente.
- Se mantienen los avisos locales y el comportamiento compatible en iOS 16–18. El inicio programado con la app cerrada requiere iOS 26 y permiso para Actividades en directo. Las actividades pendientes cuentan para el límite del sistema.

## Compilar el IPA para AltStore / SideStore

macOS con Xcode 26 o posterior:

```sh
export GOOGLE_PLACES_API_KEY='tu clave de Google Places'
bash Scripts/build-ipa.sh
```

El script comprueba la planificación y las rutas, compila Release para iPhone, verifica la extensión y empaqueta `build/reviewNfcGo-2.9-LiquidGlass-AltStore.ipa`. AltStore o SideStore firma ambos ejecutables con la cuenta del usuario al instalar; no es un IPA firmado para distribución App Store.

El proyecto mantiene el identificador original y las claves de datos. No hay que borrar la app anterior para actualizarla. Para que AltStore conserve los datos también debe conservarse el mismo equipo y el identificador con el que se instaló la versión anterior.

La clave se incorpora al Info.plist del binario durante la compilación y se restaura el archivo fuente al terminar. El archivo del repositorio no contiene la clave.

## Comprobación en iPhone

1. En iOS 26, guarda una visita para dentro de más de cinco horas. Para una visita a las 18:00, iOS programará el inicio de la actividad a las 13:00.
2. Cierra la app antes de las 13:00 y comprueba el inicio y la cuenta atrás con Actividades en directo autorizadas.
3. Toca la actividad en la pantalla bloqueada o Dynamic Island: debe abrir la ficha del negocio correspondiente.
4. Toca un aviso configurable o automático: debe abrir la misma ficha. Las acciones Apple Maps y Google Maps conservan sus destinos.
5. Cambia la fecha, desactiva el recordatorio, vende o elimina el negocio: comprueba que se cancela la programación anterior.
6. Cambia la apariencia de los iconos de Inicio entre Claro y Oscuro: debe cambiar el icono, independientemente del tema de la interfaz de la app.

La hora de inicio la gestiona ActivityKit y puede rechazar nuevas solicitudes por permisos o límites. La retirada de la actividad al llegar a la cita sigue siendo tarea del código de la app cuando puede ejecutarse; `staleDate` marca el final de vigencia y la cuenta atrás no se hace negativa.

Referencias: [Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Live Activities programadas](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:start:)), [iconos adaptativos](https://developer.apple.com/documentation/xcode/configuring-your-app-icon).

## Verificación de esta versión

En Swift 6.2.1: 57 comprobaciones de planificación y concurrencia y 15 de rutas correctas. Sintaxis de los archivos Swift de app y widget comprobada. La compilación de iPhone y la comprobación visual se ejecutan por separado con Xcode 26.2 en GitHub Actions; consulta el resultado del flujo para la compilación de la versión que estés usando.

## Versión 3.0: tarjetas vendidas

En Ficha → Editar se selecciona la cantidad de tarjetas vendidas. La ganancia es editable, con un máximo de 50 € por tarjeta. Reducir la cantidad ajusta la ganancia al límite nuevo. Los registros anteriores se conservan e infieren la cantidad mínima de tarjetas necesaria para mantener sus ganancias; los negocios vendidos tienen al menos una tarjeta. El crédito «Desarrollado por Pablo Cancho Flores» aparece en Perfil.

## Versión 3.1: historial de avisos

La campana superior de Avisos abre el historial persistente de notificaciones y Live Activities, separado por cuenta. Se incluyen las pruebas, los avisos de T−5h y cada programación, entrega confirmada, apertura, finalización o cancelación. Se recuperan las notificaciones conservadas por iOS y las actividades disponibles. Los mensajes que iOS ya retiró antes de esta actualización no son recuperables. Si pasó la hora prevista pero no hay confirmación, se muestra «Entrega sin confirmar»; una programación no se presenta como una entrega. Cada entrada conserva los estados y el nombre del negocio aunque se elimine su ficha.

## Versión 3.2: enfoque automático del mapa

Cada búsqueda y selección de negocio centra y acerca el mapa al marcador, incluso al buscar el mismo sitio otra vez. La primera ubicación válida centra el mapa automáticamente; «Mi ubicación» vuelve a centrarlo y activa el seguimiento nativo. Las nuevas posiciones GPS no interrumpen la vista de un negocio buscado. Las respuestas de búsquedas anteriores no sustituyen una selección más reciente.

## Versión 3.3: vuelo animado del mapa

Buscar un negocio o pulsar «Mi ubicación» aleja suavemente el mapa durante 0,65 s, viaja al destino durante 1 s y se acerca durante 0,65 s. El nivel de alejamiento se calcula con la distancia proyectada y las dimensiones visibles: el recorrido ocupa como máximo el 70 % del ancho o alto del mapa. Se recorre el camino corto al cruzar el meridiano 180°. Una selección nueva sustituye el vuelo desde la cámara actual; arrastrar o pellizcar lo cancela. El seguimiento GPS comienza al terminar el vuelo. Se respeta «Reducir movimiento».
