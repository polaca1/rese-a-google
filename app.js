const REVIEW_URL_BASE = "https://search.google.com/local/writereview?placeid=";
const DEFAULT_CENTER = { lat: 40.4168, lng: -3.7038 };

const state = {
  map: null,
  AdvancedMarkerElement: null,
  Place: null,
  SearchNearbyRankPreference: null,
  autocomplete: null,
  userPosition: null,
  searchCenter: null,
  userMarker: null,
  searchMarker: null,
  placeMarkers: [],
  places: [],
  selectedPlace: null,
  requestSerial: 0,
};

const els = {
  map: document.querySelector("#map"),
  locationTitle: document.querySelector("#locationTitle"),
  locationText: document.querySelector("#locationText"),
  locateBtn: document.querySelector("#locateBtn"),
  autocompleteMount: document.querySelector("#autocompleteMount"),
  nearbyList: document.querySelector("#nearbyList"),
  nearbySubtitle: document.querySelector("#nearbySubtitle"),
  selectedEmpty: document.querySelector("#selectedEmpty"),
  selectedContent: document.querySelector("#selectedContent"),
  selectedName: document.querySelector("#selectedName"),
  selectedAddress: document.querySelector("#selectedAddress"),
  placeIdField: document.querySelector("#placeIdField"),
  reviewUrlField: document.querySelector("#reviewUrlField"),
  copyPlaceIdBtn: document.querySelector("#copyPlaceIdBtn"),
  copyUrlBtn: document.querySelector("#copyUrlBtn"),
  copyMainBtn: document.querySelector("#copyMainBtn"),
  openReviewBtn: document.querySelector("#openReviewBtn"),
  toast: document.querySelector("#toast"),
};

function showToast(message) {
  els.toast.textContent = message;
  els.toast.classList.add("visible");
  window.clearTimeout(showToast.timeout);
  showToast.timeout = window.setTimeout(() => {
    els.toast.classList.remove("visible");
  }, 2200);
}

function setLocationStatus(title, text) {
  els.locationTitle.textContent = title;
  els.locationText.textContent = text;
}

function loadGoogleMaps() {
  return new Promise((resolve, reject) => {
    const key = window.APP_CONFIG?.GOOGLE_MAPS_API_KEY?.trim();

    if (!key || key === "PEGA_AQUI_TU_API_KEY") {
      reject(
        new Error(
          "Falta la API key. Abre config.js y pega una clave con Maps JavaScript API y Places API (New)."
        )
      );
      return;
    }

    const callbackName = "__reviewLinkGoogleMapsReady";
    window[callbackName] = () => {
      delete window[callbackName];
      resolve();
    };

    const script = document.createElement("script");
    script.async = true;
    script.defer = true;
    script.src =
      "https://maps.googleapis.com/maps/api/js" +
      `?key=${encodeURIComponent(key)}` +
      "&v=weekly" +
      "&libraries=places,marker" +
      "&loading=async" +
      `&callback=${callbackName}`;

    script.onerror = () => reject(new Error("No se pudo cargar Google Maps."));
    document.head.appendChild(script);
  });
}

async function init() {
  try {
    await loadGoogleMaps();

    const [{ Map }, { AdvancedMarkerElement }, placesLib] = await Promise.all([
      google.maps.importLibrary("maps"),
      google.maps.importLibrary("marker"),
      google.maps.importLibrary("places"),
    ]);

    state.AdvancedMarkerElement = AdvancedMarkerElement;
    state.Place = placesLib.Place;
    state.SearchNearbyRankPreference = placesLib.SearchNearbyRankPreference;

    state.map = new Map(els.map, {
      center: DEFAULT_CENTER,
      zoom: 6,
      mapId: "DEMO_MAP_ID",
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false,
      clickableIcons: false,
      gestureHandling: "greedy",
    });

    state.map.addListener("click", (event) => {
      if (!event.latLng) return;
      const center = {
        lat: event.latLng.lat(),
        lng: event.latLng.lng(),
      };
      setSearchCenter(center, true);
      searchNearby(center, { autoSelect: true, source: "map" });
    });

    setupAutocomplete();
    bindButtons();
    requestUserLocation();
  } catch (error) {
    console.error(error);
    setLocationStatus("Configuración pendiente", error.message);
    els.nearbyList.innerHTML = `
      <div class="empty-state">
        ${escapeHtml(error.message)}
      </div>
    `;
  }
}

function bindButtons() {
  els.locateBtn.addEventListener("click", requestUserLocation);

  els.copyPlaceIdBtn.addEventListener("click", () => {
    if (state.selectedPlace?.id) copyText(state.selectedPlace.id, "Place ID copiado");
  });

  const copyReviewLink = () => {
    const url = getReviewUrl();
    if (url) copyText(url, "Enlace de reseña copiado");
  };

  els.copyUrlBtn.addEventListener("click", copyReviewLink);
  els.copyMainBtn.addEventListener("click", copyReviewLink);

  els.openReviewBtn.addEventListener("click", () => {
    const url = getReviewUrl();
    if (url) window.open(url, "_blank", "noopener,noreferrer");
  });
}

function requestUserLocation() {
  if (!navigator.geolocation) {
    setLocationStatus(
      "Este navegador no ofrece geolocalización",
      "Puedes buscar el negocio por nombre o tocar su zona en el mapa."
    );
    return;
  }

  setLocationStatus("Buscando tu ubicación…", "Acepta el permiso de ubicación del navegador.");

  navigator.geolocation.getCurrentPosition(
    (position) => {
      const center = {
        lat: position.coords.latitude,
        lng: position.coords.longitude,
      };

      state.userPosition = center;
      state.map.setCenter(center);
      state.map.setZoom(18);

      renderUserMarker(center);
      setSearchCenter(center, false);
      updateAutocompleteBias(center);

      setLocationStatus(
        "Ubicación encontrada",
        `Precisión aproximada: ${Math.round(position.coords.accuracy)} m. Buscando negocios cercanos…`
      );

      searchNearby(center, { autoSelect: true, source: "geolocation" });
    },
    (error) => {
      const messages = {
        1: "Has bloqueado el permiso de ubicación.",
        2: "No se ha podido obtener tu posición.",
        3: "La ubicación ha tardado demasiado en responder.",
      };

      setLocationStatus(
        "No hemos podido usar tu ubicación",
        `${messages[error.code] || "Error de geolocalización."} Puedes buscar el negocio por nombre o tocar el mapa.`
      );

      state.map.setCenter(DEFAULT_CENTER);
      state.map.setZoom(6);
    },
    {
      enableHighAccuracy: true,
      timeout: 12000,
      maximumAge: 15000,
    }
  );
}

function makeUserDot() {
  const dot = document.createElement("div");
  dot.className = "user-dot";
  dot.title = "Tu ubicación";
  return dot;
}

function makeSearchPin() {
  const pin = document.createElement("div");
  pin.className = "search-pin";
  pin.innerHTML = "<span>+</span>";
  pin.title = "Punto de búsqueda";
  return pin;
}

function renderUserMarker(position) {
  if (!state.userMarker) {
    state.userMarker = new state.AdvancedMarkerElement({
      map: state.map,
      position,
      content: makeUserDot(),
      title: "Tu ubicación",
      zIndex: 100,
    });
  } else {
    state.userMarker.position = position;
  }
}

function setSearchCenter(position, showMarker) {
  state.searchCenter = position;
  updateAutocompleteBias(position);

  if (!showMarker) {
    if (state.searchMarker) state.searchMarker.map = null;
    state.searchMarker = null;
    return;
  }

  if (!state.searchMarker) {
    state.searchMarker = new state.AdvancedMarkerElement({
      map: state.map,
      position,
      content: makeSearchPin(),
      title: "Buscar negocios aquí",
      zIndex: 90,
    });
  } else {
    state.searchMarker.map = state.map;
    state.searchMarker.position = position;
  }
}

async function searchNearby(center, { autoSelect = false, source = "manual" } = {}) {
  if (!state.Place || !state.SearchNearbyRankPreference) return;

  const serial = ++state.requestSerial;
  els.nearbySubtitle.textContent = "Buscando los sitios más próximos…";
  els.nearbyList.innerHTML = `<div class="empty-state">Buscando negocios cercanos…</div>`;

  try {
    const request = {
      fields: [
        "id",
        "displayName",
        "formattedAddress",
        "location",
        "primaryType",
        "googleMapsURI",
      ],
      locationRestriction: {
        center,
        radius: 180,
      },
      maxResultCount: 10,
      rankPreference: state.SearchNearbyRankPreference.DISTANCE,
      language: "es",
    };

    const { places } = await state.Place.searchNearby(request);

    if (serial !== state.requestSerial) return;

    state.places = (places || []).filter((place) => place.location && place.id);
    renderPlaces(center);

    if (!state.places.length) {
      els.nearbySubtitle.textContent = "No se han encontrado sitios en este punto.";
      return;
    }

    const sourceCopy =
      source === "geolocation"
        ? "Ordenados por distancia desde tu ubicación."
        : "Ordenados por distancia desde el punto que has marcado.";

    els.nearbySubtitle.textContent = sourceCopy;

    if (autoSelect) {
      selectPlace(state.places[0], { panMap: false });
    }
  } catch (error) {
    console.error(error);
    els.nearbySubtitle.textContent = "No se ha podido completar la búsqueda.";
    els.nearbyList.innerHTML = `
      <div class="empty-state">
        Google Places devolvió un error. Revisa que Places API (New) esté activada y que la clave tenga permisos.
      </div>
    `;
  }
}

function renderPlaces(origin) {
  clearPlaceMarkers();

  if (!state.places.length) {
    els.nearbyList.innerHTML = `
      <div class="empty-state">
        No hay resultados. Prueba a tocar un punto más exacto del mapa o busca el nombre del negocio.
      </div>
    `;
    return;
  }

  els.nearbyList.innerHTML = "";

  state.places.forEach((place, index) => {
    const marker = new state.AdvancedMarkerElement({
      map: state.map,
      position: place.location,
      title: place.displayName || "Negocio",
      gmpClickable: true,
    });

    marker.addEventListener("gmp-click", () => {
      selectPlace(place, { panMap: true });
    });

    state.placeMarkers.push({ marker, placeId: place.id });

    const distance = distanceInMeters(origin, {
      lat: place.location.lat(),
      lng: place.location.lng(),
    });

    const row = document.createElement("button");
    row.type = "button";
    row.className = "place-row";
    row.dataset.placeId = place.id;
    row.innerHTML = `
      <span class="place-index">${index + 1}</span>
      <span class="place-copy">
        <strong>${escapeHtml(place.displayName || "Sin nombre")}</strong>
        <span>${escapeHtml(place.formattedAddress || "Dirección no disponible")}</span>
      </span>
      <span class="place-distance">${formatDistance(distance)}</span>
    `;

    row.addEventListener("click", () => {
      selectPlace(place, { panMap: true });
    });

    els.nearbyList.appendChild(row);
  });
}

function clearPlaceMarkers() {
  for (const item of state.placeMarkers) {
    item.marker.map = null;
  }
  state.placeMarkers = [];
}

function selectPlace(place, { panMap = true } = {}) {
  if (!place?.id) {
    showToast("Ese resultado no tiene un Place ID válido");
    return;
  }

  state.selectedPlace = place;

  els.selectedEmpty.classList.add("hidden");
  els.selectedContent.classList.remove("hidden");

  els.selectedName.textContent = place.displayName || "Negocio sin nombre";
  els.selectedAddress.textContent = place.formattedAddress || "Dirección no disponible";
  els.placeIdField.value = place.id;
  els.reviewUrlField.value = getReviewUrl();

  document.querySelectorAll(".place-row").forEach((row) => {
    row.classList.toggle("selected", row.dataset.placeId === place.id);
  });

  if (panMap && place.location) {
    state.map.panTo(place.location);
    if ((state.map.getZoom() || 0) < 17) state.map.setZoom(17);
  }
}

function setupAutocomplete() {
  const { PlaceAutocompleteElement } = google.maps.places;

  state.autocomplete = new PlaceAutocompleteElement();
  state.autocomplete.placeholder = "Buscar bar, restaurante, tienda, clínica…";
  els.autocompleteMount.replaceChildren(state.autocomplete);

  state.autocomplete.addEventListener("gmp-select", async ({ placePrediction }) => {
    try {
      const place = placePrediction.toPlace();

      await place.fetchFields({
        fields: [
          "id",
          "displayName",
          "formattedAddress",
          "location",
          "viewport",
          "googleMapsURI",
        ],
      });

      if (!place.id) {
        showToast("Google no ha devuelto un Place ID para ese resultado");
        return;
      }

      if (place.viewport) {
        state.map.fitBounds(place.viewport, 70);
      } else if (place.location) {
        state.map.setCenter(place.location);
        state.map.setZoom(18);
      }

      selectPlace(place, { panMap: false });

      if (place.location) {
        const point = {
          lat: place.location.lat(),
          lng: place.location.lng(),
        };
        setSearchCenter(point, true);
        await searchNearby(point, { autoSelect: false, source: "search" });
        selectPlace(place, { panMap: false });
      }
    } catch (error) {
      console.error(error);
      showToast("No se pudo cargar ese negocio");
    }
  });
}

function updateAutocompleteBias(center) {
  if (!state.autocomplete || !center) return;
  state.autocomplete.locationBias = {
    center,
    radius: 5000,
  };
}

function getReviewUrl() {
  return state.selectedPlace?.id
    ? `${REVIEW_URL_BASE}${state.selectedPlace.id}`
    : "";
}

async function copyText(text, successMessage) {
  if (!text) return;

  try {
    await navigator.clipboard.writeText(text);
    showToast(successMessage);
  } catch {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand("copy");
    textarea.remove();
    showToast(successMessage);
  }
}

function distanceInMeters(a, b) {
  const earthRadius = 6371000;
  const toRad = (deg) => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);

  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;

  return 2 * earthRadius * Math.asin(Math.sqrt(h));
}

function formatDistance(meters) {
  if (!Number.isFinite(meters)) return "";
  if (meters < 1000) return `${Math.max(1, Math.round(meters))} m`;
  return `${(meters / 1000).toFixed(1)} km`;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

init();
