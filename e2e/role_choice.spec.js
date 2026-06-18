const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const baseURL = process.env.E2E_BASE_URL || 'http://127.0.0.1:8787';
const browserExecutable = process.env.E2E_BROWSER_EXECUTABLE;
const legacySwPath = path.resolve(__dirname, '../build/web/legacy-sw.js');
const legacySwSource = `
  self.addEventListener('install', event => {
    event.waitUntil(self.skipWaiting());
  });
  self.addEventListener('activate', event => {
    event.waitUntil(self.clients.claim());
  });
  self.addEventListener('fetch', event => {
    event.respondWith(fetch(event.request));
  });
`;

test.beforeAll(() => {
  fs.writeFileSync(legacySwPath, legacySwSource);
});

test.afterAll(() => {
  fs.rmSync(legacySwPath, { force: true });
});

test.use({
  baseURL,
  viewport: { width: 390, height: 844 },
  launchOptions: {
    ...(browserExecutable ? { executablePath: browserExecutable } : {}),
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  },
});

async function waitForFlutter(page) {
  await page.waitForFunction(() => !document.querySelector('#boot'), {
    timeout: 45000,
  });
  await expect(page.locator('#boot-err')).toHaveCount(0);
}

async function openRoleChoice(page) {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await waitForFlutter(page);
}

async function clickRoleButton(page, label) {
  const roleButton = page.getByRole('button', { name: label });
  if (await roleButton.count()) {
    await roleButton.click({ timeout: 5000 });
    return;
  }

  const textButton = page.getByText(label, { exact: true });
  if (await textButton.count()) {
    await textButton.click({ timeout: 5000 });
    return;
  }

  const viewport = page.viewportSize();
  const yRatio = label === 'Cliente' ? 0.625 : 0.702;
  await page.mouse.click(viewport.width * 0.5, viewport.height * yRatio);
}

test('abre a escolha Cliente/Admin e navega para cliente no celular', async ({
  page,
}) => {
  await openRoleChoice(page);

  await clickRoleButton(page, 'Cliente');

  await expect(page).toHaveURL(/\/agendamentocliente$/);
  await waitForFlutter(page);
});

test('abre a escolha Cliente/Admin e navega para admin no celular', async ({
  page,
}) => {
  await openRoleChoice(page);

  await clickRoleButton(page, 'Admin');

  await expect(page).toHaveURL(/\/admin$/);
  await waitForFlutter(page);
});

test('rotas diretas da Cloudflare SPA carregam sem tela presa no boot', async ({
  page,
}) => {
  await page.goto('/admin', { waitUntil: 'domcontentloaded' });
  await waitForFlutter(page);

  await page.goto('/agendamentocliente', { waitUntil: 'domcontentloaded' });
  await waitForFlutter(page);
});

test('fallback HTML mostra Cliente/Admin quando o Flutter nao inicializa', async ({
  page,
}) => {
  await page.route('**/main.dart.js', async (route) => {
    await route.fulfill({
      contentType: 'application/javascript',
      body: 'throw new Error("simulated flutter boot failure");',
    });
  });

  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#boot')).toBeVisible();
  await expect(page.locator('#boot .native-choice .client')).toBeVisible();
  await expect(page.locator('#boot .native-choice .admin')).toBeVisible();

  await page.locator('#boot .native-choice .admin').click();
  await expect(page).toHaveURL(/\/admin$/);
});

test('Instagram WebView fica no fallback HTML e nao inicia Flutter', async ({
  browser,
}) => {
  const context = await browser.newContext({
    baseURL,
    viewport: { width: 390, height: 844 },
    userAgent:
      'Mozilla/5.0 (Linux; Android 14; Instagram WebView) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Version/4.0 Chrome/124.0.0.0 Mobile Safari/537.36 Instagram 335.0.0.0',
  });
  const page = await context.newPage();
  let requestedFlutterEntrypoint = false;
  page.on('request', (request) => {
    if (request.url().includes('/main.dart.js')) {
      requestedFlutterEntrypoint = true;
    }
  });

  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#boot')).toBeVisible();
  await expect(page.locator('#boot .native-choice .client')).toBeVisible();
  await expect(page.locator('#boot .native-choice .admin')).toBeVisible();
  await expect(page.locator('#boot .native-choice .iab-note')).toBeVisible();
  await expect(page.locator('#boot .sp')).toBeHidden();
  await expect(page.locator('#boot .msg')).toBeHidden();
  await page.waitForTimeout(2500);
  expect(requestedFlutterEntrypoint).toBe(false);
  await expect(page.locator('#boot')).toBeVisible();
  await expect(page.locator('#boot .native-choice .client')).toBeVisible();
  await expect(page.locator('#boot .native-choice .admin')).toBeVisible();
  await expect(page.locator('#boot .msg')).toBeHidden();
  const externalUrl = await page.evaluate(() =>
    window.__bootExternalUrl('/agendamentocliente')
  );
  expect(externalUrl).toContain('intent://');
  await context.close();
});

test('recupera navegador com service worker e cache antigos', async ({
  page,
}) => {
  await openRoleChoice(page);
  await page.evaluate(async () => {
    const registration = await navigator.serviceWorker.register('/legacy-sw.js');
    await navigator.serviceWorker.ready;
    await registration.update();

    const cache = await caches.open('legacy-flutter-cache');
    await cache.put(
      '/main.dart.js',
      new Response('throw new Error("stale cache");', {
        headers: { 'content-type': 'application/javascript' },
      })
    );

    sessionStorage.removeItem('tdb-sw-cleaned-v2');
  });

  await page.reload({ waitUntil: 'domcontentloaded' });
  await waitForFlutter(page);

  await expect
    .poll(async () =>
      page.evaluate(async () => {
        const registrations = await navigator.serviceWorker.getRegistrations();
        const cacheKeys = await caches.keys();
        return {
          registrations: registrations.length,
          hasLegacyCache: cacheKeys.includes('legacy-flutter-cache'),
        };
      })
    )
    .toEqual({ registrations: 0, hasLegacyCache: false });
});

test('carrega mesmo quando WebGL nao esta disponivel', async ({ browser }) => {
  const context = await browser.newContext({
    baseURL,
    viewport: { width: 390, height: 844 },
  });
  await context.addInitScript(() => {
    const originalGetContext = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function patchedGetContext(
      type,
      ...args
    ) {
      if (String(type).startsWith('webgl')) {
        return null;
      }
      return originalGetContext.call(this, type, ...args);
    };
  });

  const page = await context.newPage();
  await openRoleChoice(page);
  await clickRoleButton(page, 'Admin');
  await expect(page).toHaveURL(/\/admin$/);
  await context.close();
});

test('sessao antiga corrompida no navegador nao bloqueia a tela inicial', async ({
  browser,
}) => {
  const context = await browser.newContext({
    baseURL,
    viewport: { width: 390, height: 844 },
  });
  await context.addInitScript(() => {
    localStorage.setItem('sb-uebvtbgvsyzbyzdilren-auth-token', '{broken-json');
  });

  const page = await context.newPage();
  await openRoleChoice(page);
  await clickRoleButton(page, 'Cliente');
  await expect(page).toHaveURL(/\/agendamentocliente$/);
  await context.close();
});
