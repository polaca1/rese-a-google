# Generador de enlace directo de reseña de Google

Versión simplificada para móvil:

- Solicita la ubicación del usuario.
- Busca **solo el establecimiento más cercano** y lo selecciona automáticamente.
- El mapa muestra **un único marcador propio**, el del negocio seleccionado.
- Si la detección no acierta, el usuario puede tocar directamente un POI de Google Maps para seleccionarlo.
- Si toca una zona vacía, se selecciona el negocio más cercano a ese punto.
- También existe un buscador por nombre como alternativa.
- Genera el enlace `https://search.google.com/local/writereview?placeid=PLACE_ID`.
- Diseño adaptado a iPhone y pantallas estrechas, con `safe-area`, `svh/dvh` y protección contra desbordamiento horizontal.

La API key de prueba facilitada está en `config.js`.
