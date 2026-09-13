const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const FIREBASE_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

export default {
  async scheduled(_controller, env, context) {
    context.waitUntil(
      deliverPushBatch(env).then((result) => {
        console.log(JSON.stringify({event: 'push_batch_complete', ...result}));
      }).catch((error) => {
        console.error(JSON.stringify({
          event: 'push_batch_failed',
          error: error instanceof Error ? error.message : 'unknown_error',
        }));
        throw error;
      }),
    );
  },

  async fetch(_request, env) {
    if (env.REMOTE_PUSH_ENABLED !== 'true') {
      return Response.json({status: 'disabled', service: 'gather2gether-push'});
    }
    try {
      assertEnvironment(env);
      return Response.json({status: 'ok', service: 'gather2gether-push'});
    } catch (_) {
      return Response.json({status: 'misconfigured'}, {status: 503});
    }
  },
};

export async function deliverPushBatch(env, dependencies = {}) {
  if (env.REMOTE_PUSH_ENABLED !== 'true') {
    return {claimed: 0, delivered: 0, disabled: true};
  }
  assertEnvironment(env);
  const rpc = dependencies.rpc ?? ((name, parameters) =>
    supabaseRpc(env, name, parameters));
  await rpc('enqueue_due_push_reminders', {});
  const deliveries = await rpc('claim_push_delivery_batch', {p_limit: 50});
  if (!Array.isArray(deliveries)) {
    throw new Error('The push outbox returned invalid data.');
  }
  const validDeliveries = deliveries.map(validateDelivery);
  if (validDeliveries.length === 0) return {claimed: 0, delivered: 0};

  const getAccessToken = dependencies.getAccessToken ?? (() =>
    googleAccessToken(env));
  let accessToken;
  try {
    accessToken = await getAccessToken();
  } catch (_) {
    await Promise.allSettled(validDeliveries.map((delivery) =>
      rpc('fail_push_delivery', {
        p_delivery_id: delivery.delivery_id,
        p_error: 'firebase_authentication_unavailable',
        p_retryable: true,
        p_disable_device: false,
      })
    ));
    return {claimed: validDeliveries.length, delivered: 0};
  }

  const send = dependencies.send ?? ((delivery) =>
    sendFirebaseMessage(env, accessToken, delivery));
  const results = await Promise.all(validDeliveries.map(async (delivery) => {
    try {
      const result = await send(delivery);
      if (result.ok) {
        await rpc('complete_push_delivery', {
          p_delivery_id: delivery.delivery_id,
        });
        return true;
      }
      await rpc('fail_push_delivery', {
        p_delivery_id: delivery.delivery_id,
        p_error: result.error,
        p_retryable: result.retryable,
        p_disable_device: result.disableDevice,
      });
      return false;
    } catch (_) {
      await rpc('fail_push_delivery', {
        p_delivery_id: delivery.delivery_id,
        p_error: 'firebase_request_unavailable',
        p_retryable: true,
        p_disable_device: false,
      });
      return false;
    }
  }));

  return {
    claimed: validDeliveries.length,
    delivered: results.filter(Boolean).length,
  };
}

async function sendFirebaseMessage(env, accessToken, delivery) {
  const collapseId = `notification-${delivery.delivery_id}`;
  const data = {delivery_id: String(delivery.delivery_id)};
  if (delivery.event_id !== null) data.event_id = delivery.event_id;
  let response;
  try {
    response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: delivery.device_token,
            notification: {title: delivery.title, body: delivery.body},
            data,
            android: {collapse_key: collapseId},
            apns: {headers: {'apns-collapse-id': collapseId}},
          },
        }),
        signal: AbortSignal.timeout(15000),
      },
    );
  } catch (_) {
    return {
      ok: false,
      error: 'firebase_request_unavailable',
      retryable: true,
      disableDevice: false,
    };
  }
  if (response.ok) {
    await response.body?.cancel();
    return {ok: true};
  }

  const payload = await safeJson(response);
  const providerCode = firebaseErrorCode(payload);
  const disableDevice = providerCode === 'UNREGISTERED';
  const retryable = !disableDevice && (
    response.status === 401 || response.status === 403 || response.status === 429 ||
    response.status >= 500 ||
    ['INTERNAL', 'UNAVAILABLE', 'QUOTA_EXCEEDED'].includes(providerCode)
  );
  return {
    ok: false,
    error: providerCode === null
      ? `firebase_http_${response.status}`
      : `firebase_${providerCode.toLowerCase()}`,
    retryable,
    disableDevice,
  };
}

async function googleAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(new TextEncoder().encode(JSON.stringify({
    alg: 'RS256',
    typ: 'JWT',
  })));
  const claim = base64Url(new TextEncoder().encode(JSON.stringify({
    iss: env.FIREBASE_SERVICE_ACCOUNT_EMAIL,
    sub: env.FIREBASE_SERVICE_ACCOUNT_EMAIL,
    aud: GOOGLE_TOKEN_URL,
    scope: FIREBASE_SCOPE,
    iat: now,
    exp: now + 3600,
  })));
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemBytes(env.FIREBASE_PRIVATE_KEY),
    {name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256'},
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${base64Url(new Uint8Array(signature))}`;
  const response = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
    signal: AbortSignal.timeout(15000),
  });
  const payload = await safeJson(response);
  if (
    !response.ok || typeof payload?.access_token !== 'string' ||
    payload.access_token.length < 20
  ) {
    throw new Error('Firebase authentication failed.');
  }
  return payload.access_token;
}

async function supabaseRpc(env, functionName, parameters) {
  const response = await fetch(
    `${env.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/rpc/${functionName}`,
    {
      method: 'POST',
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(parameters),
      signal: AbortSignal.timeout(15000),
    },
  );
  const payload = await safeJson(response);
  if (!response.ok) throw new Error(`Push outbox RPC failed (${response.status}).`);
  return payload;
}

function validateDelivery(value) {
  if (
    !value || Array.isArray(value) || typeof value !== 'object' ||
    !Number.isSafeInteger(value.delivery_id) || value.delivery_id < 1 ||
    typeof value.device_token !== 'string' ||
    value.device_token.length < 20 || value.device_token.length > 4096 ||
    !['android', 'ios'].includes(value.device_platform) ||
    typeof value.title !== 'string' || value.title.length < 1 || value.title.length > 120 ||
    typeof value.body !== 'string' || value.body.length < 1 || value.body.length > 1000 ||
    (value.event_id !== null && (
      typeof value.event_id !== 'string' || !UUID_PATTERN.test(value.event_id)
    ))
  ) {
    throw new Error('The push outbox returned an invalid delivery.');
  }
  return value;
}

function assertEnvironment(env) {
  let supabase;
  try {
    supabase = new URL(env.SUPABASE_URL);
  } catch (_) {
    throw new Error('SUPABASE_URL is invalid.');
  }
  if (supabase.protocol !== 'https:' || !supabase.hostname.endsWith('.supabase.co')) {
    throw new Error('SUPABASE_URL is invalid.');
  }
  if (
    typeof env.SUPABASE_SERVICE_ROLE_KEY !== 'string' ||
    env.SUPABASE_SERVICE_ROLE_KEY.length < 40 ||
    typeof env.FIREBASE_PROJECT_ID !== 'string' ||
    !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(env.FIREBASE_PROJECT_ID) ||
    /^(replace-with|your-)/.test(env.FIREBASE_PROJECT_ID) ||
    typeof env.FIREBASE_SERVICE_ACCOUNT_EMAIL !== 'string' ||
    !env.FIREBASE_SERVICE_ACCOUNT_EMAIL.endsWith('.iam.gserviceaccount.com') ||
    typeof env.FIREBASE_PRIVATE_KEY !== 'string' ||
    !env.FIREBASE_PRIVATE_KEY.includes('PRIVATE KEY')
  ) {
    throw new Error('Push dispatcher configuration is invalid.');
  }
}

function pemBytes(value) {
  const normalized = value.replace(/\\n/g, '\n');
  const encoded = normalized
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');
  const binary = atob(encoded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function base64Url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function safeJson(response) {
  try {
    return await response.json();
  } catch (_) {
    return null;
  }
}

function firebaseErrorCode(payload) {
  const details = payload?.error?.details;
  if (!Array.isArray(details)) return null;
  for (const detail of details) {
    if (typeof detail?.errorCode === 'string') return detail.errorCode;
  }
  return null;
}
