const REVIEW_URL_BASE = "https://search.google.com/local/writereview?placeid=";
const DEFAULT_CENTER = { lat: 40.4168, lng: -3.7038 };

const state = {
  map: null,
  AdvancedMarkerElement: null,
  Place: null,
  SearchNearbyRankPreference: null,
  autocomplete: null,
  userPosition: null,
  userAccuracy: null,
  userMarker: null,
  selectedMarker: null,
  selectedPlace: null,
  requestSerial: 0,
};

const els = {
  map: document.querySelector("#map"),
  locationTitle: document.querySelector("#locationTitle"),
  locationText: document.querySelector("#locationText"),
  locateBtn: document.querySelector("#locateBtn"),
  autocompleteMount: document.querySelector("#autocompleteMount"),
  selectionSubtitle: document.querySelector("#selectionSubtitle"),
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
  showToast.timeout = window.setTimeout(() => els.toast.classList.remove("visible"), 2200);
}

function setLocationStatus(title, text) {
  els.locationTitle.textContent = title;
  els.locationText.textContent = text;
}

function loadGoogleMaps() {
  return new Promise((resolve, reject) => {
    const key = window.APP_CONFIG?.GOOGLE_MAPS_API_KEY?.trim();

    if (!key || key === "PEGA_AQUI_TU_API_KEY") {
      reject(new Error("Falta la API key de Google Maps en config.js."));
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
      clickableIcons: true,
      gestureHandling: "greedy",
    });

    state.map.addListener("click", async (event) => {
      event.stop?.();

      if (event.placeId) {
        await selectPlaceById(event.placeId, event.latLng);
        return;
      }

      if (!event.latLng) return;
      const point = { lat: event.latLng.lat(), lng: event.latLng.lng() };
      await selectNearestPlace(point, { source: "map" });
    });

    setupAutocomplete();
    bindButtons();
    requestUserLocation();
  } catch (error) {
    console.error(error);
    setLocationStatus("Configuración pendiente", error.message);
    els.selectedEmpty.textContent = error.message;
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
      "Toca un negocio en el mapa o búscalo por nombre."
    );
    return;
  }

  setLocationStatus("Buscando tu ubicación…", "Acepta el permiso de ubicación del navegador.");
  els.selectionSubtitle.textContent = "Buscando el establecimiento más cercano…";

  navigator.geolocation.getCurrentPosition(
    async (position) => {
      const center = {
        lat: position.coords.latitude,
        lng: position.coords.longitude,
      };

      state.userPosition = center;
      state.userAccuracy = position.coords.accuracy;
      state.map.setCenter(center);
      state.map.setZoom(18);
      renderUserMarker(center);
      updateAutocompleteBias(center);

      setLocationStatus(
        "Ubicación encontrada",
        `Precisión aproximada: ${Math.round(position.coords.accuracy)} m. Seleccionando el negocio más cercano…`
      );

      await selectNearestPlace(center, { source: "geolocation" });
    },
    (error) => {
      const messages = {
        1: "Has bloqueado el permiso de ubicación.",
        2: "No se ha podido obtener tu posición.",
        3: "La ubicación ha tardado demasiado en responder.",
      };

      setLocationStatus(
        "No hemos podido usar tu ubicación",
        `${messages[error.code] || "Error de geolocalización."} Toca un negocio en el mapa o búscalo por nombre.`
      );
      els.selectionSubtitle.textContent = "Selecciona un negocio directamente en el mapa.";
      state.map.setCenter(DEFAULT_CENTER);
      state.map.setZoom(6);
    },
    { enableHighAccuracy: true, timeout: 12000, maximumAge: 10000 }
  );
}

function makeUserDot() {
  const dot = document.createElement("div");
  dot.className = "user-dot";
  dot.title = "Tu ubicación";
  return dot;
}

function makeSelectedPin() {
  const pin = document.createElement("div");
  pin.className = "selected-pin";
  pin.innerHTML = '<span aria-hidden="true">✓</span>';
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

function renderSelectedMarker(place) {
  if (!place?.location) return;

  if (!state.selectedMarker) {
    state.selectedMarker = new state.AdvancedMarkerElement({
      map: state.map,
      position: place.location,
      content: makeSelectedPin(),
      title: place.displayName || "Negocio seleccionado",
      zIndex: 110,
    });
  } else {
    state.selectedMarker.map = state.map;
    state.selectedMarker.position = place.location;
    state.selectedMarker.title = place.displayName || "Negocio seleccionado";
  }
}

async function selectNearestPlace(center, { source = "map" } = {}) {
  if (!state.Place || !state.SearchNearbyRankPreference) return;

  const serial = ++state.requestSerial;
  els.selectedEmpty.textContent = "Buscando el negocio más cercano…";
  els.selectionSubtitle.textContent =
    source === "geolocation"
      ? "Buscando el establecimiento más cercano a tu ubicación…"
      : "Buscando el establecimiento más cercano al punto que has tocado…";

  try {
    const radius = source === "geolocation"
      ? Math.max(45, Math.min(120, Math.round((state.userAccuracy || 30) * 2)))
      : 80;

    const { places } = await state.Place.searchNearby({
      fields: ["id", "displayName", "formattedAddress", "location"],
      locationRestriction: { center, radius },
      maxResultCount: 1,
      rankPreference: state.SearchNearbyRankPreference.DISTANCE,
      language: "es",
      region: "es",
    });

    if (serial !== state.requestSerial) return;

    const place = (places || []).find((item) => item?.id && item?.location);
    if (!place) {
      els.selectedContent.classList.add("hidden");
      els.selectedEmpty.classList.remove("hidden");
      els.selectedEmpty.textContent = "No encontramos un negocio en ese punto. Toca directamente su nombre o icono en el mapa.";
      els.selectionSubtitle.textContent = "Toca el negocio exacto en el mapa o búscalo por nombre.";
      return;
    }

    selectPlace(place, { panMap: source !== "geolocation" });
    els.selectionSubtitle.textContent =
      source === "geolocation"
        ? "Este es el negocio más cercano detectado. Toca otro en el mapa si no es correcto."
        : "Has seleccionado el negocio más cercano al punto marcado.";
  } catch (error) {
    console.error(error);
    els.selectedContent.classList.add("hidden");
    els.selectedEmpty.classList.remove("hidden");
    els.selectedEmpty.textContent = "No se pudo completar la búsqueda. Toca directamente un negocio visible en el mapa.";
    els.selectionSubtitle.textContent = "Puedes seleccionar un negocio directamente en el mapa.";
  }
}

async function selectPlaceById(placeId, clickedLatLng) {
  if (!placeId) return;

  const serial = ++state.requestSerial;
  els.selectionSubtitle.textContent = "Cargando el negocio que has tocado…";

  try {
    const place = new state.Place({ id: placeId });
    await place.fetchFields({
      fields: ["id", "displayName", "formattedAddress", "location", "viewport"],
    });

    if (serial !== state.requestSerial) return;
    selectPlace(place, { panMap: true });
    els.selectionSubtitle.textContent = "Negocio seleccionado directamente en el mapa.";
  } catch (error) {
    console.error(error);
    if (clickedLatLng) {
      const point = { lat: clickedLatLng.lat(), lng: clickedLatLng.lng() };
      await selectNearestPlace(point, { source: "map" });
    } else {
      showToast("No se pudo cargar ese negocio");
    }
  }
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

  renderSelectedMarker(place);

  if (panMap && place.location) {
    state.map.panTo(place.location);
    if ((state.map.getZoom() || 0) < 17) state.map.setZoom(17);
  }
}

function setupAutocomplete() {
  const { PlaceAutocompleteElement } = google.maps.places;
  state.autocomplete = new PlaceAutocompleteElement();
  state.autocomplete.placeholder = "Buscar un negocio por nombre";
  els.autocompleteMount.replaceChildren(state.autocomplete);

  state.autocomplete.addEventListener("gmp-select", async ({ placePrediction }) => {
    try {
      const place = placePrediction.toPlace();
      await place.fetchFields({
        fields: ["id", "displayName", "formattedAddress", "location", "viewport"],
      });

      if (!place.id) {
        showToast("Google no ha devuelto un Place ID para ese resultado");
        return;
      }

      if (place.viewport) state.map.fitBounds(place.viewport, 55);
      else if (place.location) {
        state.map.setCenter(place.location);
        state.map.setZoom(18);
      }

      selectPlace(place, { panMap: false });
      els.selectionSubtitle.textContent = "Negocio seleccionado desde el buscador.";
    } catch (error) {
      console.error(error);
      showToast("No se pudo cargar ese negocio");
    }
  });
}

function updateAutocompleteBias(center) {
  if (!state.autocomplete || !center) return;
  state.autocomplete.locationBias = { center, radius: 5000 };
}

function getReviewUrl() {
  return state.selectedPlace?.id ? `${REVIEW_URL_BASE}${state.selectedPlace.id}` : "";
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

init();
