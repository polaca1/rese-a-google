# Activar «Continuar con Google» en reviewNfcGo

Lo configura Pablo una sola vez. Los usuarios solo tendrán que tocar el botón y elegir su cuenta. No hace falta pagar Apple Developer ni usar una API key de Google Places.

## 1. Crear el acceso en Google

1. Abre https://console.cloud.google.com/auth/overview y entra con tu cuenta de Google.
2. Arriba, selecciona tu proyecto. También puedes crear uno llamado **reviewNfcGo Login**.
3. Si aparece **Comenzar / Get started**, púlsalo. En nombre de la aplicación escribe **reviewNfcGo** y selecciona tu correo como correo de asistencia.
4. En público o audiencia, elige **Externo / External**. Introduce tu correo de contacto, acepta las condiciones y termina.
5. En el menú **Clientes / Clients**, pulsa **Crear cliente / Create client**.
6. En tipo de aplicación elige **Aplicación web / Web application**. Sí: es la opción correcta para esta app, porque Supabase realiza el intercambio con Google.
7. Nombre: **reviewNfcGo Supabase**. Deja vacío **Orígenes de JavaScript autorizados**.
8. En **URI de redireccionamiento autorizados**, pulsa **Añadir URI** y pega exactamente:

   ```text
   https://tmcccadamceaboyjwxlx.supabase.co/auth/v1/callback
   ```

9. Pulsa **Crear**. Guarda temporalmente el **ID de cliente** y el **Secreto de cliente** que muestra Google.

El ID suele terminar en `.apps.googleusercontent.com`. No es una clave que empiece por `AIza`. No necesitas acceso a Gmail, Drive, contactos o calendario: solo identificación básica, correo y perfil.

## 2. Guardarlo en Supabase

1. Abre https://supabase.com/dashboard/project/tmcccadamceaboyjwxlx/auth/providers
2. Dentro de **Authentication**, busca **Sign In / Providers** y abre **Google**.
3. Activa **Enable Sign in with Google**.
4. Pega el **ID de cliente** en **Client IDs** y el **Secreto de cliente** en **Client Secret**.
5. Deja desactivadas las opciones para omitir comprobaciones de nonce y pulsa **Save**.

El secreto se guarda exclusivamente en Supabase. No lo pegues en la app, en GitHub ni en el chat.

## 3. Permitir la vuelta a la app

1. Abre https://supabase.com/dashboard/project/tmcccadamceaboyjwxlx/auth/url-configuration
2. En **Redirect URLs**, pulsa **Add URL** y añade:

   ```text
   reviewnfcgo://auth/callback/*
   ```

3. Guarda. Conserva el asterisco final: cada intento lleva un identificador distinto. Esta dirección se pone en **Supabase**, no en Google.

## 4. Probarlo

1. En Google Auth Platform, abre **Público / Audience**. Mientras esté en **Testing**, añade tu correo de Google como **Test user**.
2. Actualiza reviewNfcGo sin desinstalar y pulsa **Continuar con Google**. Desde Perfil, elige el mismo correo de tu sesión para conservar la cuenta.
3. Para permitir el acceso a otros usuarios, en **Audience** cambia la aplicación a **Producción / Publish app**. Google puede pedir completar los datos de marca o verificar el consentimiento según tu configuración.

Si aparece **redirect_uri_mismatch**, comprueba la dirección HTTPS del paso 1. Si el navegador no vuelve a reviewNfcGo, comprueba la dirección con asterisco del paso 3. Si dice que Google aún no está disponible, revisa que hayas guardado el proveedor activado en Supabase.

## Tus negocios y tus copias

El inicio de sesión identifica tu cuenta; esta versión no sincroniza automáticamente los negocios, inventario ni operaciones. Borrar la app borra su almacenamiento local. Antes de hacerlo, entra en **Perfil → Copias de seguridad → Exportar una copia** y guárdala en Archivos o iCloud Drive.

Para recuperar la copia del 7 de octubre, entra con el mismo correo, ve a **Perfil → Copias de seguridad → Restaurar una copia**, elige tu archivo JSON y confirma **Restaurar esta copia**. No publiques ese archivo: contiene tus datos personales.
