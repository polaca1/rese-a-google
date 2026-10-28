Beta personal 0.7.1 (718).

El Watch del usuario rechazó el registro Lockdown de 717 con InvalidPairRecord (código 51); el perfil de firma y el certificado activo son válidos.

Se añade una cadena de certificados dedicada al Watch: raíz autofirmada y certificados de anfitrión y dispositivo firmados por esa raíz; las hojas no son CA. Claves de raíz y anfitrión separadas, nombres vacíos coherentes, extensiones BasicConstraints/KeyUsage/SKI y vigencia según las convenciones de libimobiledevice/pymobiledevice3. El generador anterior usaba Profile::Root para todas las piezas e identificaba el emisor del dispositivo de forma incoherente. Se elimina ese defecto para los nuevos intentos del Watch; no se cambia el emparejamiento del iPhone ni los certificados de firma de apps.

Las pruebas verifican las firmas X.509 reales, la vinculación con las claves, las restricciones CA/hojas y los rechazos de certificados modificados, firmante incorrecto y claves inválidas. Se ejecuta el generador real de producción.

Se conservan la protección local de claves, reintentos limitados, diagnóstico, botón sin IP/IPA y App IDs existentes. No se revocan certificados ni se crean IDs.

Pendiente la instalación física y renovación en el reloj del usuario. El componente nativo del Watch sigue siendo una prueba, no una tienda autónoma.
