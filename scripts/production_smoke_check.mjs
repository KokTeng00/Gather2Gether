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
} finally {
  clearTimeout(timeout);
}
