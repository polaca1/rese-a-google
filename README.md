# Generador de enlace directo de reseña de Google

Web móvil que:

1. Pide la ubicación del visitante.
2. Busca los negocios más cercanos con Google Places.
3. Preselecciona el resultado más próximo.
4. Permite cambiarlo tocando un marcador, una fila de resultados o cualquier punto del mapa.
5. Incluye un buscador por nombre para elegir el establecimiento exacto.
6. Obtiene el `Place ID`.
7. Genera el enlace con este formato exacto:

```text
https://search.google.com/local/writereview?placeid=PLACE_ID
```

## Configuración

### 1. Google Cloud

Crea o usa un proyecto de Google Cloud y activa:

- Maps JavaScript API
- Places API (New)

Después crea una API key.

### 2. Pegar la API key

Abre `config.js` y sustituye:

```js
GOOGLE_MAPS_API_KEY: "PEGA_AQUI_TU_API_KEY"
```

por tu clave.

### 3. Restringir la clave

En producción, limita la clave por:

- `HTTP referrers` a tu dominio.
- Restricciones de API a `Maps JavaScript API` y `Places API (New)`.

Así una clave visible en el navegador no queda utilizable desde cualquier web.

### 4. Probar en local

La geolocalización del navegador funciona en `localhost` o por HTTPS.

Una forma rápida:

```bash
python3 -m http.server 8080
```

Después abre:

```text
http://localhost:8080
```

### 5. Subir a Vercel

Es una web estática, así que puedes arrastrar esta carpeta a un repositorio y desplegarla sin build.

## Comportamiento

- Al entrar, intenta obtener una posición precisa.
- Busca hasta 10 lugares dentro de unos 180 m y los ordena por distancia.
- El primer resultado se preselecciona.
- Al tocar un punto del mapa, ese punto pasa a ser el centro de búsqueda y se vuelve a detectar el negocio más cercano.
- El buscador permite elegir un negocio por nombre.
- Al elegir un lugar, la web muestra su Place ID y el enlace de reseña listo para copiar o abrir.

## Privacidad

La aplicación no guarda la ubicación en una base de datos. No obstante, Google Maps Platform recibe los datos de posición necesarios para representar el mapa y buscar establecimientos.
