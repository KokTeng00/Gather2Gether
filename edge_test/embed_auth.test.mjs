import assert from 'node:assert/strict';
import test from 'node:test';
import {handleEmbedRequest} from '../supabase/functions/embed/handler.js';

const env = {SUPABASE_URL: 'https://project.supabase.co'};
const user = {id: '11111111-1111-4111-8111-111111111111', is_anonymous: false};
const headers = {apikey: 'sb_publishable_test', Authorization: 'Bearer user-session'};
const noModel = () => assert.fail('unauthorized or invalid input must not run inference');
const request = (overrides = {}) => new Request('https://project.supabase.co/functions/v1/embed', {
  method: 'POST', headers, body: JSON.stringify({input: 'security verification'}), ...overrides,
});

function mockFetch(t, implementation) {
  const original = globalThis.fetch;
  globalThis.fetch = implementation;
  t.after(() => { globalThis.fetch = original; });
}

test('public API key alone cannot invoke embedding or consume its request body', async (t) => {
  mockFetch(t, () => assert.fail('missing session must not call Auth'));
  const req = request({headers: {apikey: headers.apikey}});
  const response = await handleEmbedRequest(req, env, noModel);
  assert.equal(response.status, 401);
  assert.equal(req.bodyUsed, false);
});

test('forged and expired sessions are rejected using Auth, without inference', async (t) => {
  mockFetch(t, async (url, options) => {
    assert.equal(url, `${env.SUPABASE_URL}/auth/v1/user`);
    assert.equal(options.headers.Authorization, headers.Authorization);
    assert.equal(options.headers.apikey, headers.apikey);
    assert.equal(options.redirect, 'error');
    return Response.json({error: 'invalid JWT'}, {status: 401});
  });
  assert.equal((await handleEmbedRequest(request(), env, noModel)).status, 401);
});

for (const identity of [{}, {id: 'not-a-user'}, {...user, is_anonymous: true}]) {
  test(`Auth response cannot grant access to ${JSON.stringify(identity)}`, async (t) => {
    mockFetch(t, async () => Response.json(identity));
    assert.equal((await handleEmbedRequest(request(), env, noModel)).status, 401);
  });
}

for (const failure of [429, 503, 'network']) {
  test(`Auth failure ${failure} fails closed with a retryable error`, async (t) => {
    mockFetch(t, async () => {
      if (failure === 'network') throw new Error('network unavailable');
      return new Response('', {status: failure});
    });
    assert.equal((await handleEmbedRequest(request(), env, noModel)).status, 503);
  });
}

test('authenticated callers preserve the 384-dimension embedding contract', async (t) => {
  mockFetch(t, async () => Response.json(user));
  const embedding = Array(384).fill(0.125);
  let calls = 0;
  const response = await handleEmbedRequest(request(), env, async (input) => {
    calls += 1;
    assert.equal(input, 'security verification');
    return embedding;
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {embedding});
  assert.equal(calls, 1);
});

test('authenticated oversized streams stop early before inference', async (t) => {
  mockFetch(t, async () => Response.json(user));
  let chunks = 0;
  let cancelled = false;
  const body = new ReadableStream({
    pull(controller) { chunks += 1; controller.enqueue(new Uint8Array(9000)); },
    cancel() { cancelled = true; },
  });
  const response = await handleEmbedRequest(request({body, duplex: 'half'}), env, noModel);
  assert.equal(response.status, 413);
  assert.equal(cancelled, true);
  assert.ok(chunks <= 4);
});

test('invalid input and invalid model output preserve error boundaries', async (t) => {
  mockFetch(t, async () => Response.json(user));
  assert.equal((await handleEmbedRequest(request({body: '{'}), env, noModel)).status, 400);
  assert.equal((await handleEmbedRequest(request({body: JSON.stringify({input: ''})}), env, noModel)).status, 400);
  assert.equal((await handleEmbedRequest(request(), env, async () => [0.1])).status, 502);
});
