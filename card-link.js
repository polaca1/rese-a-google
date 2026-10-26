'use strict';

(async () => {
  const message = document.getElementById('message');
  const anchor = document.getElementById('destination');
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  async function fetchJSON(url, options = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 10000);
    try {
      const response = await fetch(url, { ...options, signal: controller.signal, cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer' });
      if (!response.ok) throw new Error('unavailable');
      return await response.json();
    } finally { clearTimeout(timer); }
  }
  function requestID() {
    if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    const hex = [...bytes].map(x => x.toString(16).padStart(2, '0')).join('');
    return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join('-');
  }
  try {
    const token = new URL(location.href).searchParams.get('id');
    if (!uuid.test(token || '')) throw new Error('invalid');
    const config = await fetchJSON('https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore/accounts-server.json');
    if (config.provider !== 'supabase' || !/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(config.serverURL) || !/^sb_publishable_[A-Za-z0-9_-]+$/.test(config.publishableKey)) throw new Error('configuration');
    const headers = { apikey: config.publishableKey, 'Content-Type': 'application/json' };
    const endpoint = config.serverURL + '/rest/v1/rpc/';
    let target;
    try {
      target = await fetchJSON(endpoint + 'reviewnfcgo_open_card', {
        method: 'POST', headers, body: JSON.stringify({ p_token: token, p_request_id: requestID() })
      });
    } catch {
      // Existing cards keep working during rollout or if counting is unavailable.
      // The legacy resolver still checks active=true; never bypass a paused card.
      target = await fetchJSON(endpoint + 'reviewnfcgo_link_destination', {
        method: 'POST', headers, body: JSON.stringify({ p_token: token })
      });
    }
    if (target === null) throw new Error('inactive');
    if (typeof target !== 'string' || target.length > 2048 || /\s/.test(target)) throw new Error('invalid');
    const url = new URL(target);
    if (url.protocol !== 'https:' || url.username || url.password || url.port) throw new Error('invalid');
    if (url.origin === location.origin && url.pathname === location.pathname) throw new Error('invalid');
    anchor.href = url.href; anchor.hidden = false;
    message.textContent = 'Tu enlace está listo.';
    location.replace(url.href);
  } catch (error) {
    anchor.hidden = true; anchor.removeAttribute('href');
    message.textContent = error.message === 'inactive'
      ? 'Esta tarjeta está desactivada o su enlace ya no está disponible.'
      : error.message === 'invalid'
        ? 'El enlace de esta tarjeta no es válido. Contacta con quien te la entregó.'
        : 'No se pudo abrir la tarjeta. Comprueba tu conexión y vuelve a intentarlo.';
  }
})();
