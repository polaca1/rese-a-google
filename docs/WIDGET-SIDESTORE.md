# Widget y firma de SideStore — 6.0.5 (35)

## Problema y causa

El widget mostraba 0 € mientras Dinero mostraba 30 €, con 55 € de ingresos y 25 € de gastos. El publicador ya usaba el saldo contable real, pero el acceso al App Group dependía de ALTAppGroups en Info.plist. En el código actual de SideStore el resignado deja de añadir ese campo, aunque continúa aprovisionando un grupo con sufijo de equipo. El nombre base del proyecto deja entonces de ser suficiente para encontrar los datos compartidos.

Referencias de código público consultadas el 25 de octubre de 2026:

- https://github.com/SideStore/SideStore/blob/develop/SideStore/Core/Operations/PipelineOperations/ResignAppOperation.swift
- https://github.com/SideStore/SideStore/blob/develop/SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift
- https://github.com/altstoreio/AltStore/blob/develop/AltStore/Operations/ResignAppOperation.swift

## Cambio

Cada proceso lee los identificadores del Entitlements de su embedded.mobileprovision. Extraer el payload XML de CMS solo descubre nombres; no verifica ni concede capacidades. La autorización sigue correspondiendo al sandbox mediante containerURL(forSecurityApplicationGroupIdentifier:). Se filtran los grupos de este producto, se prioriza el perfil y se conservan ALTAppGroups y el nombre base como alternativas compatibles, sin adivinar el Team ID.

El snapshot se escribe atómicamente, con protección hasta el primer desbloqueo, antes de solicitar el refresco de WidgetKit. Al entrar en primer plano se vuelve a publicar el snapshot de la cuenta cargada sin señalar un cambio financiero nuevo a la sincronización.

Un contenedor o archivo inaccesible, ausente o corrupto genera un estado sin datos, no un supuesto saldo de cero. Una cuenta válida realmente a cero conserva su presentación numérica. Cerrar sesión sigue retirando los datos compartidos.

## Verificación

WidgetSharedStoreTests cubre perfiles con sufijo sin metadatos ALT, compatibilidad de AltStore, prioridades, perfiles defectuosos, exclusión de otros grupos y simulación independiente de app/escritor y extensión/lector sobre la misma ubicación autorizada. El saldo de 30, ingresos 55 y gastos 25 sobreviven a publicación, lectura y actualización; también se comprueban logout, cero válido, errores y ausencia de refresh tras fallos.

El simulador conserva las pruebas nativas de App Group, finanzas y renderizado y añade capturas del widget pequeño a 30 € en claro/oscuro y del estado no disponible. El CI no se presenta como una instalación realmente firmada con la cuenta personal de SideStore del usuario. La lectura de una tarjeta o una sesión OAuth no se necesitan para esta corrección.

## Actualizar

Actualizar encima de la app instalada y abrirla una vez para publicar sus datos al grupo firmado. WidgetKit decide cuándo redibujar; modo de bajo consumo y presupuesto del sistema pueden retrasarlo. Si queda una instancia antigua, quitar y volver a añadir solo el widget; no borrar la app ni los datos.
