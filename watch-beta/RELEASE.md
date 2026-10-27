Build 708 — instalación experimental desde el iPhone al Watch.

Añade Elegir IPA y Firmar e instalar. Acepta un IPA con una sola app watchOS, sin extensiones, valida y acota el archivo antes de extraerlo, solicita un perfil con el App ID ya registrado de esa app y reutiliza el certificado activo. No crea App IDs ni revoca certificados. Debe haber un único Watch enlazado y un emparejamiento TCP.

El envío utiliza companion_proxy → lockdown → streaming_zip_conduit. No elimina primero la instalación anterior. Solo declara la instalación completada tras DataComplete de watchOS. Esta vía sigue necesitando prueba física con la cuenta del usuario; Apple puede rechazar el perfil. La cuenta del usuario falló en el perfil con 706; 707/708 muestran paso y código para resolverlo.

La app sigue ejecutándose en el iPhone. No incluye tienda autónoma ni autorrenovación dentro del Watch. Tampoco instala un IPA arbitrario de iPhone como si fuera watchOS. No garantiza compatibilidad de las cuentas gratuitas.

Actualiza sobre SideStore con la misma cuenta Apple, sin borrar la app. Variante personal independiente basada en SideStore; código completo, licencias y atribuciones en la rama beta/sidestore-watch y ZIP de fuentes de la release.
