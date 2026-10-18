const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require('playwright');
const base = 'https://polaca1.github.io/rese-a-google/';
const origin = 'https://tmcccadamceaboyjwxlx.supabase.co';
let browser;
before(async () => { browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium', args: ['--no-sandbox'] }); });
after(async () => { await browser?.close(); });

async function setup(t, fragment = '', options = {}) {
  const page = await browser.newPage();
  t.after(() => page.close());
  const calls = [], errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', async route => {
    const request = route.request(), url = new URL(request.url());
    if (url.origin === origin) {
      calls.push({ url, method: request.method(), headers: request.headers(), body: request.postDataJSON() });
      return route.fulfill({ status: options.status || 200, contentType: 'application/json', body: JSON.stringify(options.response || {}) });
    }
    if (url.href === base + 'accounts-server.json') {
      return route.fulfill({ contentType: 'application/json', body: JSON.stringify({ schema: 1, provider: 'supabase', serverURL: options.configOrigin || origin, publishableKey: 'sb_publishable_testonly0123456789' }) });
    }
    if (url.origin === new URL(base).origin && /^reset-password\.(html|js|css)$/.test(path.basename(url.pathname))) {
      const name = path.basename(url.pathname);
      return route.fulfill({ contentType: name.endsWith('.js') ? 'text/javascript' : name.endsWith('.css') ? 'text/css' : 'text/html', body: await fs.readFile(path.join(__dirname, '..', name)) });
    }
    throw Error('Unexpected network request: ' + url.origin + url.pathname);
  });
  await page.goto(base + 'reset-password.html' + fragment);
  await page.waitForFunction(() => document.querySelector('#request-form').onsubmit !== undefined && !location.hash);
  return { page, calls, errors };
}
async function expectText(page, selector, text) {
  await page.waitForFunction(({ selector, text }) => document.querySelector(selector).textContent.includes(text), { selector, text });
}

test('Requests recovery with a normalized email, fixed HTTPS return and no authenticated session', async t => {
  const { page, calls, errors } = await setup(t);
  await page.locator('#email').fill('PABLO@example.com');
  await page.locator('#request-form button').click();
  await expectText(page, '#status', 'Si existe una cuenta');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url.pathname, '/auth/v1/recover');
  assert.equal(calls[0].url.searchParams.get('redirect_to'), base + 'reset-password.html');
  assert.equal(calls[0].method, 'POST');
  assert.deepEqual(calls[0].body, { email: 'pablo@example.com' });
  assert.equal(calls[0].headers.authorization, undefined);
  await page.locator('#request-form button').click();
  await expectText(page, '#status', 'Espera un minuto');
  assert.equal(calls.length, 1);
  assert.deepEqual(errors, []);
});
test('Recovery updates the existing user, removes URL credentials and retains no session', async t => {
  const { page, calls } = await setup(t, '#type=recovery&access_token=fake-access&refresh_token=fake-refresh');
  assert.equal(page.url(), base + 'reset-password.html');
  assert.equal(await page.locator('#password-form').isVisible(), true);
  await page.locator('#password').fill('New-test-password-123');
  await page.locator('#confirmation').fill('New-test-password-123');
  await page.locator('#password-form button').click();
  await expectText(page, '#title', 'Contraseña actualizada');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url.pathname, '/auth/v1/user');
  assert.equal(calls[0].method, 'PUT');
  assert.equal(calls[0].headers.authorization, 'Bearer fake-access');
  assert.deepEqual(calls[0].body, { password: 'New-test-password-123' });
  assert.equal(await page.locator('#password').inputValue(), '');
  assert.deepEqual(await page.evaluate(() => [localStorage.length, sessionStorage.length]), [0, 0]);
});
test('Mismatched passwords never reach the API', async t => {
  const { page, calls } = await setup(t, '#type=recovery&access_token=fake-access');
  await page.locator('#password').fill('New-test-password-123');
  await page.locator('#confirmation').fill('Different-password-123');
  await page.locator('#password-form button').click();
  await expectText(page, '#status', 'no coinciden');
  assert.equal(calls.length, 0);
});
test('Expired recovery token allows a new request and clears the password', async t => {
  const { page } = await setup(t, '#type=recovery&access_token=expired-test-token', { status: 401 });
  await page.locator('#password').fill('New-test-password-123');
  await page.locator('#confirmation').fill('New-test-password-123');
  await page.locator('#password-form button').click();
  await expectText(page, '#status', 'ha caducado');
  assert.equal(await page.locator('#restart').isVisible(), true);
  assert.equal(await page.locator('#password').inputValue(), '');
});
test('Rejects non-recovery tokens and expired email links', async t => {
  for (const fragment of ['#error=access_denied&error_code=otp_expired', '#type=signup&access_token=fake-access', '#type=recovery&access_token=a&access_token=b']) {
    const { page, calls } = await setup(t, fragment);
    await expectText(page, '#status', 'ha caducado');
    assert.equal(await page.locator('#password-form').isVisible(), false);
    assert.equal(calls.length, 0);
    assert.equal(new URL(page.url()).hash, '');
  }
});
test('An untrusted configuration never receives a password or token', async t => {
  const { page, calls } = await setup(t, '#type=recovery&access_token=fake-access', { configOrigin: 'https://untrusted.example.com' });
  await page.locator('#password').fill('New-test-password-123');
  await page.locator('#confirmation').fill('New-test-password-123');
  await page.locator('#password-form button').click();
  await expectText(page, '#status', 'No se pudo guardar');
  assert.equal(calls.length, 0);
});
test('Rate limiting displays an actionable message', async t => {
  const { page } = await setup(t, '', { status: 429 });
  await page.locator('#email').fill('pablo@example.com');
  await page.locator('#request-form button').click();
  await expectText(page, '#status', 'Demasiadas solicitudes');
  assert.equal(await page.locator('#request-form button').isEnabled(), true);
});
