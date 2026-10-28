Beta personal 0.7.1 (717).

El informe real de 716 confirma un perfil y certificado válidos, pero falla Pair con código 43. Ese código agrupaba rechazos distintos; no identifica aún el motivo concreto.

El intercambio de confianza ahora sigue la separación de libimobiledevice: RootPrivateKey y HostPrivateKey permanecen únicamente en el registro local. Tampoco se envía DevicePublicKey, que no forma parte del registro de certificados enviado por esa implementación de referencia. Se conservan los certificados, HostID y SystemBUID reales. Esto es una corrección de compatibilidad y manejo de claves, no una instalación física verificada.

El diagnóstico distingue una lista cerrada de rechazos de watchOS: registro/certificado inválido, emparejamiento prohibido en esa conexión, fallo al guardar confianza, desafío de supervisión y otros estados fijos. Respuestas desconocidas siguen siendo código 43; nunca se exportan textos libres ni datos privados. No se eluden rechazos o confianza denegada.

Se mantiene el botón Instalar SideStore en el Watch, el paquete incluido, la detección automática, los IDs existentes y el SideStore completo del iPhone.

El componente nativo del Watch todavía es una prueba y no una tienda autónoma. Instalación física y renovación pendientes.
