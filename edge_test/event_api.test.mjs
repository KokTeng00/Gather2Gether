import assert from 'node:assert/strict';
import test, {afterEach} from 'node:test';

import {handleApiRequest} from '../functions/api/v1/[[path]].js';

const originalFetch = globalThis.fetch;
const env = {
  SUPABASE_URL: 'https://project.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test_key_long_enough',
};
const userId = '11111111-1111-4111-8111-111111111111';
const eventId = '22222222-2222-4222-8222-222222222222';
const postId = '33333333-3333-4333-8333-333333333333';
const commentId = '44444444-4444-4444-8444-444444444444';

afterEach(() => {
  globalThis.fetch = originalFetch;
});

test('health endpoint runs at Cloudflare without Supabase authentication', async () => {
  globalThis.fetch = async () => {
    throw new Error('health must not call Supabase');
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/health'),
    env,
  );

  assert.equal(response.status, 200);
  assert.equal((await response.json()).service, 'gather2gether-edge-api');
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('nearby endpoint verifies the user and forwards only validated RPC parameters', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) {
      return Response.json({id: userId});
    }
    return Response.json([{id: eventId, title: 'Nearby event'}]);
  };

  const response = await handleApiRequest(
    new Request(
      'https://gather2gether.pages.dev/api/v1/events/nearby?latitude=52.52&longitude=13.405&radius_km=10',
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    env,
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  assert.equal(calls.length, 2);
  assert.match(calls[1].url, /\/rest\/v1\/rpc\/nearby_events$/);
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    p_latitude: 52.52,
    p_longitude: 13.405,
    p_radius_km: 10,
  });
  assert.equal(payload.data[0].id, eventId);
});

test('create endpoint rejects unexpected fields before calling the database', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls += 1;
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    throw new Error('database must not be called');
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/events', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({unexpected: true}),
    }),
    env,
  );
  const payload = await response.json();

  assert.equal(response.status, 400);
  assert.equal(payload.error.code, 'unexpected_fields');
  assert.equal(calls, 1);
});

test('RSVP endpoint maps database capacity failures to a safe conflict', async () => {
  globalThis.fetch = async (url) => {
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    return Response.json({message: 'event_full', code: 'P0001'}, {status: 400});
  };

  const response = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/events/${eventId}/rsvp`, {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({status: 'joined'}),
    }),
    env,
  );
  const payload = await response.json();

  assert.equal(response.status, 409);
  assert.equal(payload.error.code, 'event_full');
  assert.equal(payload.error.message, 'This event is full.');
});

test('forum list authenticates and uses the restricted list RPC', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    return Response.json([{id: postId, title: 'Weekend hiking group'}]);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/forum/posts', {
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  assert.match(calls[1].url, /\/rest\/v1\/rpc\/list_forum_posts$/);
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    p_limit: 30,
    p_before: null,
  });
  assert.equal(payload.data[0].id, postId);
});

test('forum post creation forwards normalized, allow-listed fields', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    return Response.json(postId);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/forum/posts', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        title: '  Weekend hiking group  ',
        body: '  Who wants to explore a local trail this weekend?  ',
        category: 'Looking for group',
      }),
    }),
    env,
  );

  assert.equal(response.status, 201);
  assert.equal((await response.json()).id, postId);
  assert.match(calls[1].url, /\/rest\/v1\/rpc\/create_forum_post$/);
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    p_title: 'Weekend hiking group',
    p_body: 'Who wants to explore a local trail this weekend?',
    p_category: 'Looking for group',
  });
});

test('forum comment endpoint rejects unexpected fields before its RPC', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls += 1;
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    throw new Error('comment RPC must not be called');
  };

  const response = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/forum/posts/${postId}/comments`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({body: 'Count me in!', author_id: userId}),
    }),
    env,
  );

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'unexpected_fields');
  assert.equal(calls, 1);
});

test('forum database rate limits become a safe 429 response', async () => {
  globalThis.fetch = async (url) => {
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    return Response.json({message: 'forum_rate_limited'}, {status: 400});
  };

  const response = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/forum/posts/${postId}/comments`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({body: 'Count me in!'}),
    }),
    env,
  );

  assert.equal(response.status, 429);
  assert.equal((await response.json()).error.code, 'forum_rate_limited');
});

test('forum comment report uses a fixed reason and target RPC', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    return new Response(null, {status: 204});
  };

  const response = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/forum/comments/${commentId}/report`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({reason: 'harassment'}),
    }),
    env,
  );

  assert.equal(response.status, 201);
  assert.match(calls[1].url, /\/rest\/v1\/rpc\/report_forum_comment$/);
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    p_comment_id: commentId,
    p_reason: 'harassment',
  });
});

test('browser-origin requests are rejected for the mobile-only API', async () => {
  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/events', {
      method: 'OPTIONS',
      headers: {Origin: 'http://localhost:53123'},
    }),
    env,
  );

  assert.equal(response.status, 403);
  assert.equal((await response.json()).error.code, 'browser_not_supported');
  assert.equal(response.headers.get('access-control-allow-origin'), null);
});
