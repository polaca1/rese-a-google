# Selección de negocios cercanos

## Comportamiento

- La distancia manda. Una aseguradora a 5 metros precede a un bar a 50 metros.
- Solo se desempata por categoría dentro de un margen pequeño de 1–4 metros, limitado por la precisión del GPS. Bares, restaurantes y tiendas preceden a oficinas como seguros y bancos.
- Se utilizan categorías reales de Google, sin adivinarlas por el nombre del negocio.
- Si dos resultados son igual de plausibles, o la precisión del GPS no permite distinguirlos, Inicio muestra una tarjeta con **dos opciones** y sus direcciones. No se selecciona ningún negocio ni aparece su botón NFC hasta elegir.
- Cuando el desempate bar/tienda frente a oficina es claro y el GPS es preciso, se selecciona la primera opción directamente.
- Otro toque en **Mi ubicación** recorre las alternativas. Tras la última, vuelve a la primera.
- La búsqueda por nombre y la selección manual conservan prioridad sobre respuestas de red tardías.

## Límites y caché

- Google Nearby consulta hasta 20 resultados en un círculo de 150 m.
- El filtro local solo conserva negocios a 45–100 m como máximo, según la precisión. No se escoge un resultado lejano simplemente porque Google lo devolvió.
- Se eliminan duplicados, geometría de calles/áreas y negocios cerrados permanentemente.
- Ubicaciones de más de 20 s o con precisión peor de 80 m esperan una señal mejor. La búsqueda por nombre y tocar el mapa siguen disponibles.
- Durante dos minutos, pulsar de nuevo en el mismo punto reutiliza la lista sin consultar otra vez a Google. Desplazarse más de 15–30 m (según precisión) o caducar la caché reinicia la búsqueda.
- Las categorías opcionales en PlaceResult son compatibles con copias anteriores y se conservan al sincronizar iPhone/Mac.

El GPS y las coordenadas de Google no identifican de forma infalible el interior, la planta o la puerta de un local. La elección de dos opciones evita presentar como seguro un caso ambiguo.

## Archivos y verificación

- `NearbyBusinesses.swift`: decodificación común, clasificación, distancias, incertidumbre y ciclo de alternativas.
- `PlacesService.swift`: calidad de la posición, peticiones, caché y estado de selección de iPhone.
- `HomeView.swift`: tarjeta minimalista de dos locales y botón Mi ubicación.
- `MacServices.swift`: conserva los mismos metadatos de Google al buscar por nombre.
- `Tests/NearbyBusinessTests.swift`: distancias, categorías, descartes, ambigüedad, caché, compatibilidad y respuesta de Google.
- `NearbyPlaceVerification.swift`: pruebas nativas de toques repetidos, elección manual, errores y respuestas tardías; capturas clara/oscura.

No se añaden llamadas de IA para decidir el negocio ni consultas de Places por cada alternativa mostrada.
