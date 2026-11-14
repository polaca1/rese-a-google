# IPA de prueba de las pantallas adaptadas

Este destino usa directamente `ReviewNfcGoViews`, con su ciclo de vida y entrega de enlaces, y conserva los widgets. **No incorpora el contenedor Day y no es la entrega final de App Fair.**

El identificador de instalación conserva el de reviewNfcGo para facilitar una actualización con el mismo firmante. El IPA no está firmado: hay que firmarlo con SideStore/Sideloadly. Una firma o un equipo distintos pueden usar otro contenedor de datos. Verifica que los datos estén sincronizados antes de sustituir una instalación.

Desde un Mac con Xcode 26.3 y XcodeGen, ejecuta el workflow `IPA de prueba` o reproduce sus pasos. El workflow valida la estructura, versión, arquitectura de dispositivo y extensión, y publica un prerelanzamiento con checksum, sin cambiar la fuente de SideStore ni marcarlo como versión estable.
