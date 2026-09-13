const baseUrl = (
  process.env.GATHER2GETHER_API_URL ??
  'https://gather2gether.pages.dev/api/v1'
).replace(/\/$/, '');

const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 10_000);

try {
  const response = await fetch(`${baseUrl}/health`, {
    headers: {Accept: 'application/json'},
    signal: controller.signal,
  });
  if (!response.ok) {
    throw new Error(`Health endpoint returned HTTP ${response.status}.`);
  }
  const payload = await response.json();
  if (
    payload?.status !== 'ok' ||
    payload?.service !== 'gather2gether-edge-api' ||
    !Number.isInteger(payload?.version) ||
    payload.version < 2
  ) {
    throw new Error('Health endpoint returned an unexpected contract.');
  }
  console.log(`Gather2Gether production health is OK (API v${payload.version}).`);
  const anonymous = await fetch(`${baseUrl}/events/nearby`, {signal: controller.signal});
  await anonymous.body?.cancel();
  if (anonymous.status !== 401) throw new Error('Unauthenticated event access must return HTTP 401.');
  const browser = await fetch(`${baseUrl}/events/nearby`, {
    headers: {Origin: new URL(baseUrl).origin}, signal: controller.signal,
  });
  await browser.body?.cancel();
  if (browser.status !== 403) throw new Error('Browser API access must return HTTP 403.');
  console.log('Unauthenticated and browser API access are rejected.');
  if (process.argv.includes('--beta')) {
    for (const path of ['privacy', 'terms', 'account-deletion', 'support']) {
      const page = await fetch(new URL(`/${path}`, baseUrl), {method: 'HEAD', signal: controller.signal});
      if (page.status !== 200 || !page.headers.get('content-type')?.includes('text/html')) {
        throw new Error(`The public ${path} page is not ready (HTTP ${page.status}).`);
      }
    }
    console.log('All public policy and support pages are available.');
  }
} finally {
  clearTimeout(timeout);
}
