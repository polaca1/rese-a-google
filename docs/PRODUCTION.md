# Revisión de distribución

Referencia: [Prepare for app distribution](https://help.apple.com/xcode/mac/current/en.lproj/dev91fe7130a.html), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data) y [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy).

## Cambios aplicados

- Separación de entrada, pantallas, datos y servicios; ninguna migración del formato de las cuentas o del dinero.
- Autocompletado de credenciales, avance entre campos y envío desde el teclado de iPhone. Validación de correo, nombre y contraseña antes de enviar; no se impiden contraseñas antiguas cortas al iniciar sesión.
- Campos y cambios de modo bloqueados durante el acceso; contraseña retirada tras finalizar el intento y al cambiar de modo.
- Iconos decorativos de campos ocultos a VoiceOver y etiquetas explícitas; se conservan controles y tamaños de texto del sistema.
- Guardado automático sin paneles ni acciones manuales, manteniendo avisos de errores y conflictos. Salir con un guardado sin confirmar requiere reconocer el aviso.
- Declaración de privacidad actualizada a los datos reales sincronizados e incluida también en Mac. No se declara seguimiento.
- Control obligatorio del paquete: versiones y callback, extensión de widgets, mínimo macOS 14, transporte seguro, privacidad y ausencia de rutas de prueba o claves de servidor.
- Documentación actualizada a Supabase; las instrucciones antiguas no se presentan al usuario.

## Alcance real

Distribución prevista: SideStore en iPhone y descarga directa en Mac. Los paquetes pasan pruebas de dominio, verificaciones nativas y controles de publicación en GitHub Actions. El flujo prueba renovación, recuperación al reinstalar, cuentas normales/Google, guardado automático, desconexiones y conflictos con transportes aislados. La comprobación de conectividad utiliza además el servicio Supabase real sin crear cuentas.

Una sesión Google real en el Mac del usuario y una tarjeta NFC física requieren comprobación en sus dispositivos. Mac usa firma ad hoc; notarizar necesita Developer ID. Esta revisión no equivale a una aprobación para App Store: esa distribución requiere su proceso de firma, revisión, gestión de eliminación de cuentas y declaraciones correspondientes.

Las reglas privadas de Supabase y las revisiones se conservan. No se introducen tokens administrativos, secretos OAuth ni datos personales en los informes de verificación.
