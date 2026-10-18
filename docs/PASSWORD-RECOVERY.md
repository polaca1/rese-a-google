# Recuperación de contraseña

El botón de iPhone y Mac abre una página HTTPS compartida. No requiere que el usuario tenga una sesión abierta, no crea otra cuenta y no modifica las copias ni el identificador del usuario.

## Configuración única del propietario

1. Publicar los tres archivos de `server/cloud/password-reset/` en la raíz de la rama `sidestore`, junto a `accounts-server.json`.
2. En Supabase → Authentication → URL Configuration → Redirect URLs, añadir **exactamente**:
   `https://polaca1.github.io/rese-a-google/reset-password.html`
3. Guardar. Conservar las otras redirecciones de Google. No es necesario cambiar Site URL.
4. En Authentication → Email Templates → Reset Password, conservar el enlace `{{ .ConfirmationURL }}`. La plantilla estándar verifica el enlace y redirige a la página con la sesión de recuperación en el fragmento.
5. Probar con una cuenta propia: enviar correo desde la página, abrirlo, cambiar contraseña, entrar desde la app y comprobar que aparecen los mismos datos. Un correo de recuperación real solo se envía cuando el usuario lo solicita.

El servicio recibe `POST /auth/v1/recover?redirect_to=…`. Solo la persona que abre el correo obtiene el token; la página usa `PUT /auth/v1/user` para cambiar la contraseña. No se usan secretos administrativos ni contraseñas de Google. Para Google se conserva su botón de acceso habitual.

## Seguridad y límites

- La clave publishable es pública; las tablas mantienen sus reglas privadas.
- El fragmento se elimina de la URL antes de cualquier petición. No se guarda la sesión, ni el token de renovación, ni la contraseña en almacenamiento del navegador.
- Sin scripts externos ni analítica; política de contenido restringida al proyecto y sin envío de referrer.
- El envío tiene respuesta genérica y límites de frecuencia; los errores no revelan si existe un correo.
- Enlaces caducados, contraseñas diferentes y errores de conexión tienen recuperación visible.
- El proveedor de correo predeterminado de Supabase tiene restricciones de destinatarios y cuotas. Para recuperar cuentas de todos los usuarios, configurar SMTP propio en Authentication → Email → SMTP Settings y comprobar la entrega. No se puede garantizar correo de producción solo con el proveedor de prueba.
- Referencias: https://supabase.com/docs/guides/auth/passwords#resetting-a-password y https://supabase.com/docs/guides/auth/auth-smtp.

## Verificación local

`node --test server/cloud/password-reset/tests/reset-password.test.cjs`

Las pruebas usan navegador y red simulada: no envían correos ni cambian contraseñas reales.
