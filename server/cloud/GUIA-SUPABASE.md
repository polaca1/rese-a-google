# Cuentas de reviewNfcGo en la nube, sin encender un PC

Usaremos **Supabase Free**. Los usuarios crearán sus cuentas desde reviewNfcGo y estas aparecerán automáticamente en tu proyecto de Supabase. Tú solo haces esta configuración una vez; los usuarios no tendrán que introducir direcciones ni configurar un servidor.

**Estado:** la conexión está preparada en la rama `accounts/supabase-free`. Todavía necesita tu proyecto y una actualización de las apps para activarse. Instalar la versión antigua no la conecta automáticamente a Supabase.

## 1. Entrar

Haz estos pasos desde Safari en el Mac: resulta más cómodo que desde el iPhone.

1. Abre <https://supabase.com/dashboard>.
2. Pulsa **Sign in with GitHub** y entra con tu cuenta.
3. Elige tu organización. Mantén el plan **Free**.

### Si aparece «You need additional permissions to create a project»

Ese aviso indica falta de permisos, no que tengas que pagar.

1. Pulsa **Cancel** y abre **Organization settings → Team**.
2. Tu cuenta debería aparecer como **Owner** si tú creaste la organización. **Administrator** también puede crear proyectos.
3. Si apareces con otro rol, crea una organización propia desde el selector de organizaciones y selecciona **Free**.
4. Si ya apareces como **Owner**, cierra sesión y vuelve a entrar con el mismo método de acceso, por ejemplo GitHub. Prueba también una ventana privada en el Mac.
5. Si el problema continúa siendo Owner, contacta con soporte de Supabase desde el dashboard y adjunta el aviso. No borres tu organización ni contrates un plan de pago para intentar arreglarlo.

Supabase documenta que las organizaciones que creas te asignan el rol Owner: <https://supabase.com/docs/guides/platform/access-control>.

## 2. Crear el proyecto

1. Pulsa **New project**.
2. Organización: la tuya.
3. Nombre: **reviewNfcGo**.
4. En **Database password**, genera una contraseña y guárdala en Contraseñas de Apple. Esta contraseña es de administración; no es la contraseña de los usuarios de la app. No la compartas.
5. Región: una región europea cercana, si está disponible.
6. Comprueba que sigue indicando **Free**, crea el proyecto y espera a que termine de prepararse.

## 3. Permitir el registro

1. Abre **Authentication → Sign In / Providers**. Según la versión del dashboard, puede aparecer como **Providers**.
2. Activa el proveedor **Email** y permite nuevos registros.
3. Para la primera puesta en marcha sin contratar un servicio de correo, desactiva **Confirm email** y guarda.

Con la confirmación desactivada se puede registrar una cuenta sin demostrar que el correo pertenece a quien la crea. Es una limitación de esta configuración inicial. Para un lanzamiento público con correos verificados, configura un proveedor de correo en **Authentication → SMTP Settings**, activa la confirmación y prepara los enlaces de confirmación y recuperación en la app.

El correo integrado de Supabase es para pruebas, tiene restricciones de destinatarios y un límite de dos correos por hora. No sirve como servicio general de correo para todos tus usuarios. Documentación: <https://supabase.com/docs/guides/auth/auth-smtp>.

## 4. Copiar solo dos datos

En la pantalla del proyecto, pulsa **Connect** o entra en **Project Settings → API** para encontrar la dirección. Las claves están en **Project Settings → API Keys**.

Necesitamos:

- **Project URL**, con este aspecto: `https://abcdefghijklmnopqrst.supabase.co`.
- **Publishable key**, que empieza por `sb_publishable_`.

La Publishable key está diseñada para incluirse en aplicaciones. **No envíes Secret key, service_role, contraseña de la base de datos ni un token de tu cuenta de Supabase.**

Pega la URL y la Publishable key en el chat. Con esos dos datos comprobaré el servicio y publicaré la actualización de iPhone y Mac con una configuración común. No necesitas instalar herramientas ni editar archivos.

## 5. Después de la actualización

1. Antes de actualizar, exporta una copia de tus datos actuales desde la app. Conserva el archivo JSON.
2. Actualiza desde la fuente de SideStore; no desinstales la app para hacerlo.
3. Crea tu cuenta en la app. Usa el mismo correo que tenías antes para conservar la relación con los datos locales de ese correo. Si no recuerdas la contraseña antigua de la cuenta local, puedes elegir una contraseña nueva para la cuenta de Supabase; son sistemas distintos.
4. En el Mac, entra con esa nueva cuenta. Para trasladar tus negocios y dinero, usa **Archivo → Importar copia del iPhone…** y selecciona el JSON.
5. En Supabase, abre **Authentication → Users**: ahí verás las cuentas creadas. Las contraseñas no se muestran en texto; el servicio gestiona su almacenamiento seguro.

## Qué se guarda y qué no

Esta conexión centraliza **las cuentas y el acceso** de todos los usuarios. Las sesiones se guardan en el llavero de cada dispositivo y se renuevan mediante Supabase.

Desde iPhone 5.4 y Mac 1.4, los negocios, visitas, inventario, movimientos y foto se sincronizan automáticamente con Supabase. El administrador debe ejecutar una sola vez `ACTIVAR-DATOS-NUBE.sql` en SQL Editor. Cada cuenta solo puede leer y modificar sus propios datos. Los usuarios de versiones antiguas deben entrar con su cuenta e importar su copia JSON si los datos ya no están en el dispositivo. Antes de desinstalar, comprueba «Guardado en la nube». Sin conexión, los cambios permanecen pendientes en el dispositivo.

## Qué ofrece el plan gratuito

Según <https://supabase.com/pricing>, el plan Free incluye 50.000 usuarios activos al mes, una base de datos de 500 MB y hasta dos proyectos activos. No tienes que dejar encendido tu PC ni tu Mac.

Los proyectos gratuitos pueden pausarse después de una semana de inactividad. No incluye una garantía de disponibilidad permanente ni copias automáticas de la base de datos. Por tanto, **gratuito no significa servicio 24/7 garantizado para siempre**. Revisa el dashboard y conserva las copias locales de tus datos; si necesitas disponibilidad garantizada, hará falta otro plan o alojamiento.

## Alternativa con tu mini PC

Si prefieres controlar el servidor en casa, hay una guía separada para instalar Debian en el RKM MK36S de 2 GB / 32 GB. No necesitas hacerlo para usar Supabase. El instalador Linux debe usarse solo cuando esté publicada su descarga verificada.
