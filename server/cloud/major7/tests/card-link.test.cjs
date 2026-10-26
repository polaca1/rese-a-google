const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require('playwright');
const base = 'https://polaca1.github.io/rese-a-google/';
const origin = 'https://tmcccadamceaboyjwxlx.supabase.co';
const id = '33333333-3333-4333-8333-333333333333';
const google = 'https://search.google.com/local/writereview?placeid=place-test';
let browser;
before(async () => { browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium', args: ['--no-sandbox'] }); });
after(async () => { await browser?.close(); });

async function setup(t, options = {}) {
  const page = await browser.newPage();
  t.after(() => page.close());
  const calls = [], errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', async route => {
    const request = route.request(), url = new URL(request.url());
    if (url.origin === origin) {
      const body = request.postDataJSON();
      calls.push({ url, method: request.method(), headers: request.headers(), body });
      const legacy = url.pathname.endsWith('reviewnfcgo_link_destination');
      const target = typeof options.target === 'function' ? options.target() : options.target === undefined ? google : options.target;
      return route.fulfill({ status: legacy ? (options.legacyStatus || 200) : (options.status || 200), contentType: 'application/json', body: JSON.stringify(target) });
    }
    if (url.host === 'raw.githubusercontent.com') {
      return route.fulfill({ contentType: 'application/json', body: JSON.stringify({ schema: 1, provider: 'supabase', serverURL: options.configOrigin || origin, publishableKey: 'sb_publishable_testonly0123456789' }) });
    }
    if (url.origin === new URL(base).origin && /^(link\.html|card-link\.(js|css))$/.test(path.basename(url.pathname))) {
      const name = path.basename(url.pathname);
      return route.fulfill({ contentType: name.endsWith('.js') ? 'text/javascript' : name.endsWith('.css') ? 'text/css' : 'text/html', body: await fs.readFile(path.join(__dirname, '..', name)) });
    }
    return route.fulfill({ contentType: 'text/html', body: '<title>Destino de prueba</title><p>Destino de prueba</p>' });
  });
  await page.goto(base + 'link.html?id=' + (options.token || id));
  return { page, calls, errors };
}
async function message(page, text) {
  await page.waitForFunction(text => document.querySelector('#message')?.textContent.includes(text), text);
}

test('Records one anonymous opening and redirects to the Place ID destination', async t => {
  const { page, calls, errors } = await setup(t);
  await page.waitForURL(google);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url.pathname, '/rest/v1/rpc/reviewnfcgo_open_card');
  assert.equal(calls[0].body.p_token, id);
  assert.match(calls[0].body.p_request_id, /^[0-9a-f-]{36}$/i);
  assert.equal(calls[0].headers.authorization, undefined);
  assert.equal(calls[0].headers.cookie, undefined);
  assert.equal(calls[0].headers.referer, undefined);
  assert.deepEqual(errors, []);
});
test('A paused card never falls back to Google or the legacy resolver', async t => {
  const { page, calls } = await setup(t, { target: null });
  await message(page, 'desactivada');
  assert.equal(calls.length, 1);
  assert.equal(new URL(page.url()).searchParams.get('id'), id);
  assert.equal(await page.locator('#destination').isVisible(), false);
  assert.deepEqual(await page.evaluate(() => [localStorage.length, sessionStorage.length]), [0, 0]);
});
test('The identical NFC URL follows remote destination changes and deactivation', async t => {
  let target = google;
  const { page, calls } = await setup(t, { target: () => target });
  await page.waitForURL(google);
  const physicalTag = base + 'link.html?id=' + id;
  target = 'https://example.org/new-destination';
  await page.goto(physicalTag); await page.waitForURL(target);
  target = null;
  await page.goto(physicalTag); await message(page, 'desactivada');
  assert.equal(calls.length, 3);
  assert.ok(calls.every(call => call.body.p_token === id));
  assert.equal(new Set(calls.map(call => call.body.p_request_id)).size, 3);
});
test('Previously written cards continue to resolve while the counter is being activated', async t => {
  const { page, calls } = await setup(t, { status: 404 });
  await page.waitForURL(google);
  assert.equal(calls.length, 2);
  assert.equal(calls[1].url.pathname, '/rest/v1/rpc/reviewnfcgo_link_destination');
  assert.deepEqual(calls[1].body, { p_token: id });
});
test('Invalid token is rejected before reading configuration or calling the database', async t => {
  const { page, calls } = await setup(t, { token: 'not-a-token' });
  await message(page, 'no es válido'); assert.equal(calls.length, 0);
});
test('Untrusted configuration is not used', async t => {
  const { page, calls } = await setup(t, { configOrigin: 'https://untrusted.example.org' });
  await message(page, 'No se pudo abrir'); assert.equal(calls.length, 0);
});
test('Dangerous URLs and redirect loops never become a destination link', async t => {
  for (const target of ['javascript:alert(1)', 'http://example.org', 'https://name:secret@example.org', 'https://example.org:444/path', base + 'link.html?id=' + id]) {
    const { page } = await setup(t, { target });
    await message(page, 'no es válido');
    assert.equal(await page.locator('#destination').getAttribute('href'), null);
  }
});
test('A network/service error is distinguished from a deliberately paused link', async t => {
  const { page } = await setup(t, { status: 503, legacyStatus: 503 });
  await message(page, 'Comprueba tu conexión');
  assert.equal(await page.locator('#destination').isVisible(), false);
});
