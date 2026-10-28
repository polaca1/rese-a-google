Beta personal 0.7.1 (712), independiente del proyecto oficial SideStore.

Corrige una comprobación excesiva de la build 711: un perfil de la familia iOS puede autorizar una app del Watch. Ya no se exige la etiqueta literal watchOS. Se siguen exigiendo el App ID y la cuenta exactos, el identificador del Watch en ProvisionedDevices, un perfil no caducado y certificado válido. Un perfil que solo incluya el iPhone sigue rechazándose.

El diagnóstico schema 3 distingue plataforma, coincidencia de App ID y cuenta, presencia del Watch, caducidad y certificado. Exporta solo categorías fijas y resultados booleanos, sin identificadores ni perfiles. Incluye por separado el rechazo del instalador automático. Al recuperar una instalación pendiente, valida su cuenta contra la sesión actual.

Se conserva el SideStore completo de iPhone, su identidad, Apple ID, fuentes, instalación y renovación, SideBackup, widgets y atajos de datos móviles. No crea App IDs ni revoca certificados. Actualiza sin borrar la app y usando la misma cuenta.

El componente incluido de watchOS 10 es todavía un prototipo para comprobar instalación, apertura y servicio local. NO es una tienda autónoma ni firma desde el Watch. El usuario confirmó invalidProfile en 711; no se ha verificado una instalación física ni renovación con su cuenta gratuita.

Requiere un único Watch cercano y desbloqueado, emparejamiento Idevice TCP y perfiles válidos para cada app y extensión. Las actualizaciones de esta beta se comprueban al abrir SideStore desde su propia fuente; iOS no garantiza ejecución en segundo plano.

Justificación técnica del cambio de familia de perfil y registro de un caso instalado:
https://github.com/ryakel/boomerang/wiki/iOS-Native-App#the-watch-must-be-in-the-signing-profile
Referencia Apple sobre perfiles y autorización por dispositivo:
https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles

Código completo y licencias incluidos. Transporte adaptado de Rzbck/isideload bajo MIT.
