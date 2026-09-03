import assert from 'node:assert/strict';
import test from 'node:test';

import {onRequest} from '../functions/[[path]].js';

test('non-API browser routes return a hardened 404', () => {
  const response = onRequest();

  assert.equal(response.status, 404);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('x-frame-options'), 'DENY');
});

test('invite links provide a hardened app handoff without exposing event data', async () => {
  const eventId = '22222222-2222-4222-8222-222222222222';
  const response = onRequest({
    request: new Request(`https://gather2gether.pages.dev/invite/${eventId}`),
  });
  const body = await response.text();

  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /^text\/html/);
  assert.equal(response.headers.get('x-frame-options'), 'DENY');
  assert.match(body, new RegExp(`gather2gether://event/${eventId}`));
  assert.equal(body.includes('SUPABASE'), false);
});
