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

test('interest search embeds the query and uses the cosine recommendation RPC', async () => {
  const calls = [];
  const embedding = Array.from({length: 384}, (_, index) => index / 384);
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/functions/v1/embed')) return Response.json({embedding});
    if (address.endsWith('/rpc/recommend_nearby_events')) {
      return Response.json([{id: eventId, title: 'Gentle forest walk'}]);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request(
      'https://gather2gether.pages.dev/api/v1/events/nearby?latitude=52.52&longitude=13.405&radius_km=10&interest=quiet%20outdoor%20activities',
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    env,
  );

  assert.equal(response.status, 200);
  assert.equal(calls.length, 3);
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    input: 'quiet outdoor activities',
  });
  const rpcBody = JSON.parse(calls[2].options.body);
  assert.match(calls[2].url, /\/rpc\/recommend_nearby_events$/);
  assert.equal(rpcBody.p_query_embedding.length, 384);
  assert.equal(rpcBody.p_limit, 30);
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

test('community interest search uses the indexed semantic feed RPC', async () => {
  const calls = [];
  const embedding = Array(384).fill(0.125);
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/functions/v1/embed')) return Response.json({embedding});
    if (address.endsWith('/rpc/recommend_forum_posts')) {
      return Response.json([{id: postId, title: 'Learn together'}]);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request(
      'https://gather2gether.pages.dev/api/v1/forum/posts?interest=people%20learning%20new%20skills',
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    env,
  );

  assert.equal(response.status, 200);
  assert.match(calls[2].url, /\/rpc\/recommend_forum_posts$/);
  assert.equal(JSON.parse(calls[2].options.body).p_query_embedding.length, 384);
});

test('profile follow endpoint derives the follower from the authenticated user', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    return Response.json(true);
  };

  const response = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/profiles/${postId}/follow`, {
      method: 'PUT',
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );

  assert.equal(response.status, 200);
  assert.match(calls[1].url, /\/rpc\/set_profile_follow$/);
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    p_profile_id: postId,
    p_following: true,
  });
  assert.deepEqual(await response.json(), {following: true});
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
    p_image_key: null,
    p_place_name: null,
    p_place_address: null,
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

test('assistant searches indexed nearby events before calling the configured model', async () => {
  const calls = [];
  const serviceCalls = [];
  const assistantEnv = {
    ...env,
    ASSISTANT_MODEL: {
      fetch: async (request) => {
        serviceCalls.push(request);
        return Response.json({answer: 'Morning Run is about 850 m away.'});
      },
    },
  };
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/begin_assistant_turn')) return Response.json(101);
    if (address.endsWith('/rpc/search_nearby_events')) {
      return Response.json([{
        id: eventId,
        title: 'Morning Run',
        category: 'Running',
        venue_name: 'City Park',
        start_at: '2099-01-01T08:00:00Z',
        distance_meters: 850,
      }]);
    }
    if (address.endsWith('/rpc/list_assistant_messages')) {
      return Response.json([{id: 101, role: 'user', content: 'Any running events near me?'}]);
    }
    if (address.endsWith('/rpc/finish_assistant_turn')) return Response.json(102);
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/assistant/chat', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: 'Any running events near me?',
        latitude: 52.52,
        longitude: 13.405,
        radius_km: 10,
      }),
    }),
    assistantEnv,
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  const searchCall = calls.find((call) => call.url.endsWith('/rpc/search_nearby_events'));
  assert.deepEqual(JSON.parse(searchCall.options.body), {
    p_latitude: 52.52,
    p_longitude: 13.405,
    p_radius_km: 10,
    p_query: 'running',
    p_limit: 8,
  });
  assert.equal(serviceCalls.length, 1);
  const modelBody = await serviceCalls[0].json();
  assert.equal(modelBody.event_search_requested, true);
  assert.equal(modelBody.location_available, true);
  assert.equal(modelBody.event_matches[0].title, 'Morning Run');
  assert.equal(payload.message.content, 'Morning Run is about 850 m away.');
  assert.equal(payload.event_matches[0].id, eventId);
});

test('assistant answers app questions without performing an event search', async () => {
  const calls = [];
  globalThis.fetch = async (url) => {
    const address = String(url);
    calls.push(address);
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/begin_assistant_turn')) return Response.json(201);
    if (address.endsWith('/rpc/list_assistant_messages')) {
      return Response.json([{id: 201, role: 'user', content: 'How do I use the app?'}]);
    }
    if (address.endsWith('/rpc/finish_assistant_turn')) return Response.json(202);
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/assistant/chat', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: 'How do I use the app?',
        latitude: null,
        longitude: null,
        radius_km: 10,
      }),
    }),
    {
      ...env,
      ASSISTANT_MODEL: {
        fetch: async () => Response.json({answer: 'Start in Discover and choose an event.'}),
      },
    },
  );

  assert.equal(response.status, 200);
  assert.equal(calls.some((url) => url.endsWith('/rpc/search_nearby_events')), false);
});

test('assistant history can be cleared only through the authenticated RPC', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    return new Response(null, {status: 204});
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/assistant/history', {
      method: 'DELETE',
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );

  assert.equal(response.status, 200);
  assert.match(calls[1].url, /\/rpc\/clear_assistant_history$/);
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
