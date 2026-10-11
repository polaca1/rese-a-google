# Organización del proyecto

Guías utilizadas: [App organization](https://developer.apple.com/documentation/swiftui/app-organization), [Model data](https://developer.apple.com/documentation/swiftui/model-data) y [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines). Se mantiene una app SwiftUI nativa, con navegación propia de iPhone y Mac y modelos compartidos.

## Responsabilidades

| Capa | Archivos | Responsabilidad |
| --- | --- | --- |
| Entrada y navegación iPhone | ReviewNfcGoApp, ContentView | Crear dependencias, ciclo de vida y rutas principales |
| Cuenta iPhone | AuthStore, AuthView, ProfileView | Presentar acceso, cuenta y acciones; delegar en el servicio |
| Datos iPhone | AppStore | Operaciones, persistencia y señales de cambios por cuenta |
| Negocio compartido | VisitRecord, MoneyLedger, BusinessTools, VisitScheduling | Validaciones, céntimos, stock y datos compatibles entre dispositivos |
| Acceso compartido | RemoteAuth, GoogleSignIn | Supabase, PKCE, renovación y Keychain |
| Guardado compartido | CloudBackup | Leer antes de escribir, revisiones, conflictos y reintentos |
| Avisos de guardado | CloudStatusView | Solo errores o conflictos que requieren atención |
| Servicios iPhone | PlacesService, ExternalActions, ReminderServices | Ubicación, búsqueda, mapas, NFC y notificaciones |
| Pantallas iPhone | HomeView, NativeMapView, RecordViews, ReminderViews, MoneyView, BusinessWorkspaceViews | Interacción y presentación por función |
| Apariencia iPhone | AppAppearance | Materiales y controles reutilizables |
| Mac | MacApp, MacStore, MacServices, MacDashboardViews, MacEditors | Ventanas, menús, tablas, operaciones y persistencia nativos |
| Verificación | Tests, *Verification | Ejercitar operaciones y flujos; las rutas de simulación quedan fuera de Release |

ContentView pasa de 2.550 a 129 líneas. CloudBackup no contiene vistas. Se evita añadir capas o dependencias que no resuelvan un problema real.

## Contratos que se conservan

- Cada modificación confirmada en el almacén comunica `didChange`; el guardado se agrupa durante 800 ms y reintenta también periódicamente.
- Una instalación vacía descarga primero la cuenta y no sustituye datos remotos por un estado vacío.
- La identidad autenticada determina qué cuenta puede leerse o escribirse. Un correo introducido en un JSON no concede acceso a otra cuenta.
- La actualización usa la revisión esperada; nunca fuerza una sobrescritura de cambios concurrentes. Ambos estados se conservan internamente antes de una resolución.
- Cambiar de cuenta desconecta tareas anteriores antes de conectar los datos de la siguiente.
- Las operaciones monetarias usan céntimos y los presupuestos convertidos no pueden venderse dos veces.
- El servicio conserva la validación de certificados y el servidor valida el token; usar la duración relativa de una sesión nueva no omite autenticación.

## Interfaz de producción

Inicio conserva el mapa. Perfil y Ajustes muestran la cuenta y las funciones necesarias, sin paneles de nube, copias manuales ni créditos de desarrollo. Guardar normalmente no requiere una acción del usuario. Un error o conflicto se comunica con lenguaje de producto, sin presentar servidores ni configuración técnica.
