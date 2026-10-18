/* No SDK, analytics, stored sessions or administrator credentials. Tokens stay in memory. */
'use strict';
(() => {
  const canonicalURL = 'https://polaca1.github.io/rese-a-google/reset-password.html';
  const origin = 'https://tmcccadamceaboyjwxlx.supabase.co';
  const requestForm = document.getElementById('request-form');
  const passwordForm = document.getElementById('password-form');
  const status = document.getElementById('status');
  const restart = document.getElementById('restart');
  const title = document.getElementById('title');
  const description = document.getElementById('description');
  const fragment = new URLSearchParams(location.hash.slice(1));
  // Remove credentials before any network requests. Never retain the refresh token.
  history.replaceState(null, '', location.pathname);
  let accessToken = fragment.get('type') === 'recovery' && fragment.getAll('access_token').length === 1
    ? fragment.get('access_token') : null;
  const invalidLink = fragment.has('error') || fragment.has('error_code') || (fragment.size > 0 && !accessToken);
  fragment.delete('access_token'); fragment.delete('refresh_token');
  let configuration;
  let busy = false;
  let lastSent = 0;

  function setBusy(value) {
    busy = value;
    document.querySelectorAll('input, button').forEach(control => { control.disabled = value; });
  }
  function expired() {
    accessToken = null;
    requestForm.hidden = true;
    passwordForm.hidden = true;
    restart.hidden = false;
    status.textContent = 'El enlace ha caducado o no es válido. Pide uno nuevo para recuperar tu contraseña.';
  }
  async function api(path, body, token) {
    if (!configuration) {
      const response = await fetch('accounts-server.json', { cache: 'no-store', credentials: 'omit', redirect: 'error', signal: AbortSignal.timeout(15000) });
      if (!response.ok) throw Error('network');
      const value = await response.json();
      if (value.schema !== 1 || value.provider !== 'supabase' || value.serverURL !== origin
          || !/^sb_publishable_[A-Za-z0-9_-]{16,1024}$/.test(value.publishableKey || '')) throw Error('configuration');
      configuration = value;
    }
    const headers = { 'Content-Type': 'application/json', apikey: configuration.publishableKey };
    if (token) headers.Authorization = 'Bearer ' + token;
    const response = await fetch(origin + '/auth/v1/' + path, {
      method: token ? 'PUT' : 'POST', headers, body: JSON.stringify(body),
      credentials: 'omit', cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(20000)
    });
    if (!response.ok) {
      let code = '';
      try { const value = await response.json(); code = value.code || value.error_code || ''; } catch { /* no raw server errors in UI */ }
      if (response.status === 429) throw Error('rate');
      if (token && (response.status === 401 || response.status === 403)) throw Error('expired');
      if (code === 'same_password') throw Error('same');
      if (code === 'weak_password') throw Error('weak');
      if (code === 'reauthentication_needed' || code === 'session_not_found') throw Error('expired');
      throw Error('network');
    }
    // Password update may return a user object. Do not retain or log it.
  }

  if (accessToken && accessToken.length <= 16000) {
    requestForm.hidden = true;
    passwordForm.hidden = false;
    title.textContent = 'Elige una contraseña nueva';
    description.textContent = 'Cambiar la contraseña conserva tu cuenta y tus datos. Después vuelve a la app e inicia sesión.';
  } else if (invalidLink || accessToken) { expired(); }

  requestForm.addEventListener('submit', async event => {
    event.preventDefault();
    if (busy || !requestForm.reportValidity()) return;
    const email = document.getElementById('email').value.trim().toLowerCase();
    if (Date.now() - lastSent < 60000) { status.textContent = 'Espera un minuto antes de pedir otro enlace.'; return; }
    setBusy(true); status.textContent = 'Enviando…';
    try {
      await api('recover?redirect_to=' + encodeURIComponent(canonicalURL), { email });
      lastSent = Date.now();
      status.textContent = 'Si existe una cuenta con ese correo, recibirás un enlace. Revisa también la carpeta de correo no deseado.';
    } catch (error) {
      status.textContent = error.message === 'rate' ? 'Demasiadas solicitudes. Espera unos minutos antes de volver a intentarlo.'
        : 'No se pudo enviar el enlace. Comprueba tu conexión e inténtalo de nuevo.';
    } finally { setBusy(false); }
  });

  passwordForm.addEventListener('submit', async event => {
    event.preventDefault();
    if (busy || !passwordForm.reportValidity()) return;
    const password = document.getElementById('password').value;
    const confirmation = document.getElementById('confirmation').value;
    if (password !== confirmation) { status.textContent = 'Las contraseñas no coinciden.'; return; }
    if (!accessToken) { expired(); return; }
    setBusy(true); status.textContent = 'Guardando…';
    try {
      await api('user', { password }, accessToken);
      accessToken = null;
      passwordForm.reset(); passwordForm.hidden = true;
      title.textContent = 'Contraseña actualizada';
      description.textContent = 'Vuelve a reviewNfcGo e inicia sesión con tu correo y la contraseña nueva. Tus datos siguen en tu cuenta.';
      status.textContent = '';
    } catch (error) {
      if (error.message === 'expired') { passwordForm.reset(); expired(); }
      else status.textContent = error.message === 'rate' ? 'Demasiados intentos. Espera unos minutos.'
        : error.message === 'same' ? 'Elige una contraseña diferente de la anterior.'
        : error.message === 'weak' ? 'Elige una contraseña más segura, con letras, números y símbolos.'
        : 'No se pudo guardar. Comprueba tu conexión y vuelve a intentarlo.';
    } finally { setBusy(false); }
  });
  restart.addEventListener('click', () => { location.replace(canonicalURL); });
})();
