import assert from 'node:assert/strict';
import test, {afterEach} from 'node:test';

import {handleApiRequest} from '../functions/api/v1/[[path]].js';

const originalFetch = globalThis.fetch;
const env = {
  SUPABASE_URL: 'https://project.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test_key_long_enough',
  GEOAPIFY_API_KEY: 'geoapify_test_key_long_enough',
};
const userId = '11111111-1111-4111-8111-111111111111';
const eventId = '22222222-2222-4222-8222-222222222222';
const eventId2 = '55555555-5555-4555-8555-555555555555';
const eventId3 = '66666666-6666-4666-8666-666666666666';
const postId = '33333333-3333-4333-8333-333333333333';
const postId2 = '77777777-7777-4777-8777-777777777777';
const commentId = '44444444-4444-4444-8444-444444444444';
const searchId = '88888888-8888-4888-8888-888888888888';

afterEach(() => {
  globalThis.fetch = originalFetch;
});

function recommendationControlResponse(address) {
  if (address.endsWith('/rpc/get_recommendation_preferences')) {
    return Response.json([{
      enabled: true,
      hidden_categories: [],
      hidden_count: 0,
    }]);
  }
  if (address.endsWith('/rpc/list_hidden_recommendation_ids')) {
    return Response.json([]);
  }
  return null;
}

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

test('push device registration forwards only validated device details', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) {
      return Response.json({id: userId});
    }
    return Response.json(searchId);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/push/devices', {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        token: 'fcm-device-token-with-enough-entropy',
        platform: 'android',
        locale: 'en-GB',
      }),
    }),
    env,
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json().then(({registered}) => registered), true);
  assert.match(calls[1].url, /\/rest\/v1\/rpc\/register_push_device$/);
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    p_token: 'fcm-device-token-with-enough-entropy',
    p_platform: 'android',
    p_locale: 'en-GB',
  });
});

test('push device removal is scoped through the authenticated RPC', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) {
      return Response.json({id: userId});
    }
    return Response.json(true);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/push/devices', {
      method: 'DELETE',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({token: 'fcm-device-token-with-enough-entropy'}),
    }),
    env,
  );

  assert.equal(response.status, 200);
  assert.equal((await response.json()).removed, true);
  assert.match(calls[1].url, /\/rest\/v1\/rpc\/unregister_push_device$/);
});

test('notification and recommendation controls use fixed member-scoped RPCs', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/update_notification_preferences')) return Response.json(true);
    if (address.endsWith('/rpc/update_recommendation_preferences')) return Response.json(true);
    if (address.endsWith('/rpc/hide_recommendation')) return Response.json(true);
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const notificationResponse = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/notification-preferences', {
      method: 'PUT',
      headers: {Authorization: 'Bearer user-token', 'Content-Type': 'application/json'},
      body: JSON.stringify({
        push_enabled: true,
        reminders_enabled: true,
        announcements_enabled: false,
        discussion_enabled: false,
        recommendations_enabled: true,
        quiet_start_minute: 1320,
        quiet_end_minute: 420,
        timezone_offset_minutes: 120,
      }),
    }),
    env,
  );
  const preferenceResponse = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/recommendations/preferences', {
      method: 'PUT',
      headers: {Authorization: 'Bearer user-token', 'Content-Type': 'application/json'},
      body: JSON.stringify({enabled: false, hidden_categories: ['Sports']}),
    }),
    env,
  );
  const hideResponse = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/recommendations/hide', {
      method: 'POST',
      headers: {Authorization: 'Bearer user-token', 'Content-Type': 'application/json'},
      body: JSON.stringify({content_kind: 'event', content_id: eventId}),
    }),
    env,
  );

  assert.deepEqual(
    [notificationResponse.status, preferenceResponse.status, hideResponse.status],
    [200, 200, 200],
  );
  const notificationCall = calls.find((call) =>
    call.url.endsWith('/rpc/update_notification_preferences')
  );
  assert.deepEqual(JSON.parse(notificationCall.options.body), {
    p_push_enabled: true,
    p_reminders_enabled: true,
    p_announcements_enabled: false,
    p_discussion_enabled: false,
    p_recommendations_enabled: true,
    p_quiet_start_minute: 1320,
    p_quiet_end_minute: 420,
    p_timezone_offset_minutes: 120,
  });
  const preferenceCall = calls.find((call) =>
    call.url.endsWith('/rpc/update_recommendation_preferences')
  );
  assert.deepEqual(JSON.parse(preferenceCall.options.body), {
    p_enabled: false,
    p_hidden_categories: ['Sports'],
  });
  const hideCall = calls.find((call) => call.url.endsWith('/rpc/hide_recommendation'));
  assert.deepEqual(JSON.parse(hideCall.options.body), {
    p_content_kind: 'event',
    p_content_id: eventId,
  });
});

test('personalization opt-out uses non-personalized event and community feeds', async () => {
  const calls = [];
  globalThis.fetch = async (url) => {
    const address = String(url);
    calls.push(address);
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/get_recommendation_preferences')) {
      return Response.json([{
        enabled: false,
        hidden_categories: ['Safety'],
        hidden_count: 0,
      }]);
    }
    if (address.endsWith('/rpc/list_hidden_recommendation_ids')) {
      return Response.json([]);
    }
    if (address.endsWith('/rpc/nearby_events')) {
      return Response.json([{id: eventId, category: 'Running', title: 'Nearby run'}]);
    }
    if (address.endsWith('/rpc/list_forum_posts')) {
      return Response.json([
        {id: postId, category: 'Safety', title: 'Hidden category'},
        {id: postId2, category: 'General', title: 'Latest discussion'},
      ]);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };
  const noModel = {
    fetch: async () => {
      throw new Error('Model reranking must not run after opt-out.');
    },
  };

  const events = await handleApiRequest(
    new Request(
      'https://gather2gether.pages.dev/api/v1/events/nearby?latitude=52.52&longitude=13.405&radius_km=10',
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    {...env, ASSISTANT_MODEL: noModel},
  );
  const forum = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/forum/posts', {
      headers: {Authorization: 'Bearer user-token'},
    }),
    {...env, ASSISTANT_MODEL: noModel},
  );

  assert.equal(events.status, 200);
  assert.equal((await events.json()).data[0].recommendation_reason, 'Near your chosen area');
  assert.equal(forum.status, 200);
  assert.deepEqual((await forum.json()).data.map((post) => post.id), [postId2]);
  assert.equal(calls.some((address) =>
    address.endsWith('/rpc/recommend_personalized_events')
  ), false);
  assert.equal(calls.some((address) =>
    address.endsWith('/rpc/recommend_personalized_forum_posts')
  ), false);
});

test('nearby endpoint uses the personalized feed with only validated RPC parameters', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) {
      return Response.json({id: userId});
    }
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
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
  assert.equal(calls.length, 4);
  const recommendationCall = calls.find((call) =>
    call.url.endsWith('/rpc/recommend_personalized_events')
  );
  assert.deepEqual(JSON.parse(recommendationCall.options.body), {
    p_latitude: 52.52,
    p_longitude: 13.405,
    p_radius_km: 10,
  });
  assert.equal(payload.data[0].id, eventId);
});

test('nearby feed cross-encoder reranks a bounded shortlist and caches the blended order', async () => {
  const calls = [];
  const tasks = [];
  let modelBody;
  const candidates = [
    {
      id: eventId,
      title: 'Coffee meetup',
      category: 'Social',
      venue_name: 'Central Cafe',
      address: 'Private test address must not leave the API',
      description: 'Meet new people over coffee.',
      start_at: '2099-01-01T10:00:00Z',
    },
    {
      id: eventId2,
      title: 'Forest hike',
      category: 'Outdoors',
      venue_name: 'Trail entrance',
      description: 'A relaxed nature walk.',
      start_at: '2099-01-02T10:00:00Z',
    },
    {
      id: eventId3,
      title: 'Board games',
      category: 'Games',
      venue_name: 'Community hall',
      description: 'Beginner-friendly games.',
      start_at: '2099-01-03T10:00:00Z',
    },
  ];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
    if (address.endsWith('/rpc/recommend_personalized_events')) {
      return Response.json(candidates);
    }
    if (address.endsWith('/rpc/get_ai_recommendation_state')) {
      return Response.json({
        eligible: true,
        preference_query: 'Action: joined | Category: Outdoors | Event: Hill walk',
        cache_key: '0123456789abcdef0123456789abcdef',
        ranked_ids: null,
      });
    }
    if (address.endsWith('/rpc/claim_ai_recommendation_rerank')) {
      return Response.json(true);
    }
    if (address.endsWith('/rpc/set_ai_recommendation_cache')) {
      return Response.json(true);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request(
      'https://gather2gether.pages.dev/api/v1/events/nearby?latitude=52.52&longitude=13.405&radius_km=10',
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    {
      ...env,
      ASSISTANT_MODEL: {
        fetch: async (request) => {
          modelBody = await request.json();
          return Response.json({
            ranking: [
              {id: eventId2, score: 0.99},
              {id: eventId3, score: 0.2},
              {id: eventId, score: 0.1},
            ],
          });
        },
      },
    },
    (task) => tasks.push(task),
  );
  const payload = await response.json();
  await Promise.all(tasks);

  assert.equal(response.status, 200);
  assert.deepEqual(payload.data.map((event) => event.id), [eventId2, eventId, eventId3]);
  assert.equal(modelBody.surface, 'event');
  assert.equal(modelBody.candidates.length, 3);
  assert.equal(JSON.stringify(modelBody).includes('Private test address'), false);
  const stateCall = calls.find((call) =>
    call.url.endsWith('/rpc/get_ai_recommendation_state')
  );
  assert.deepEqual(JSON.parse(stateCall.options.body), {
    p_surface: 'event',
    p_candidate_ids: [eventId, eventId2, eventId3],
  });
  const throttleCall = calls.find((call) =>
    call.url.endsWith('/rpc/claim_ai_recommendation_rerank')
  );
  assert.deepEqual(JSON.parse(throttleCall.options.body), {p_surface: 'event'});
  const cacheCall = calls.find((call) =>
    call.url.endsWith('/rpc/set_ai_recommendation_cache')
  );
  assert.deepEqual(JSON.parse(cacheCall.options.body), {
    p_surface: 'event',
    p_cache_key: '0123456789abcdef0123456789abcdef',
    p_ranked_ids: [eventId2, eventId, eventId3],
  });
});

test('nearby feed uses an exact cached rerank without calling the model', async () => {
  let modelCalls = 0;
  globalThis.fetch = async (url) => {
    const address = String(url);
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
    if (address.endsWith('/rpc/recommend_personalized_events')) {
      return Response.json([
        {id: eventId, title: 'First'},
        {id: eventId2, title: 'Second'},
      ]);
    }
    if (address.endsWith('/rpc/get_ai_recommendation_state')) {
      return Response.json({
        eligible: true,
        preference_query: 'Action: joined | Category: Outdoors',
        cache_key: '0123456789abcdef0123456789abcdef',
        ranked_ids: [eventId2, eventId],
      });
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request(
      'https://gather2gether.pages.dev/api/v1/events/nearby?latitude=52.52&longitude=13.405&radius_km=10',
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    {
      ...env,
      ASSISTANT_MODEL: {
        fetch: async () => {
          modelCalls += 1;
          throw new Error('cache should avoid the model');
        },
      },
    },
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(payload.data.map((event) => event.id), [eventId2, eventId]);
  assert.equal(modelCalls, 0);
});

test('nearby feed does not call the model again while the rerank throttle is active', async () => {
  let modelCalls = 0;
  globalThis.fetch = async (url) => {
    const address = String(url);
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
    if (address.endsWith('/rpc/recommend_personalized_events')) {
      return Response.json([
        {id: eventId, title: 'First'},
        {id: eventId2, title: 'Second'},
      ]);
    }
    if (address.endsWith('/rpc/get_ai_recommendation_state')) {
      return Response.json({
        eligible: true,
        preference_query: 'Action: joined | Category: Outdoors',
        cache_key: '0123456789abcdef0123456789abcdef',
        ranked_ids: null,
      });
    }
    if (address.endsWith('/rpc/claim_ai_recommendation_rerank')) {
      return Response.json(false);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request(
      'https://gather2gether.pages.dev/api/v1/events/nearby?latitude=52.52&longitude=13.405&radius_km=10',
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    {
      ...env,
      ASSISTANT_MODEL: {
        fetch: async () => {
          modelCalls += 1;
          throw new Error('throttle should avoid the model');
        },
      },
    },
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(payload.data.map((event) => event.id), [eventId, eventId2]);
  assert.equal(modelCalls, 0);
});

test('place autocomplete stays global, applies a proximity bias, and hides the provider key', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
    if (address.startsWith('https://api.geoapify.com/v1/geocode/autocomplete')) {
      return Response.json({
        results: [
          {
            place_id: '51a-place',
            name: 'Kunsthalle Mannheim',
            formatted: 'Friedrichsplatz 4, 68165 Mannheim, Germany',
            address_line1: 'Kunsthalle Mannheim',
            address_line2: 'Friedrichsplatz 4, 68165 Mannheim, Germany',
            country_code: 'de',
            lat: 49.4842,
            lon: 8.4755,
            result_type: 'amenity',
            timezone: {name: 'Europe/Berlin'},
          },
        ],
      });
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request(
      'https://gather2gether.pages.dev/api/v1/places/autocomplete?text=Kunsthalle&latitude=49.48&longitude=8.47&language=de',
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    env,
  );
  const payload = await response.json();
  const upstream = new URL(calls[1].url);

  assert.equal(response.status, 200);
  assert.equal(upstream.searchParams.get('text'), 'Kunsthalle');
  assert.equal(upstream.searchParams.get('bias'), 'proximity:8.47,49.48');
  assert.equal(upstream.searchParams.get('lang'), 'de');
  assert.equal(upstream.searchParams.get('limit'), '10');
  assert.equal(upstream.searchParams.has('filter'), false);
  assert.equal(payload.data[0].formatted_address, 'Friedrichsplatz 4, 68165 Mannheim, Germany');
  assert.equal(payload.data[0].timezone, 'Europe/Berlin');
  assert.equal(JSON.stringify(payload).includes(env.GEOAPIFY_API_KEY), false);
});

test('place autocomplete validates user input before spending provider credits', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls += 1;
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    throw new Error('place provider must not be called');
  };

  const response = await handleApiRequest(
    new Request(
      'https://gather2gether.pages.dev/api/v1/places/autocomplete?text=ab&language=english',
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    env,
  );
  const payload = await response.json();

  assert.equal(response.status, 400);
  assert.equal(payload.error.code, 'invalid_parameter');
  assert.equal(calls, 1);
});

test('place autocomplete rejects an oversized provider response', async () => {
  globalThis.fetch = async (url) => {
    const address = String(url);
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.startsWith('https://api.geoapify.com/v1/geocode/autocomplete')) {
      return new Response(JSON.stringify([{formatted: 'x'.repeat(132 * 1024)}]), {
        headers: {'Content-Type': 'application/json'},
      });
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request(
      'https://gather2gether.pages.dev/api/v1/places/autocomplete?text=Kunsthalle',
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    env,
  );
  const payload = await response.json();

  assert.equal(response.status, 502);
  assert.equal(payload.error.code, 'invalid_place_response');
});

test('event interest search uses the indexed hybrid recommendation RPC', async () => {
  const calls = [];
  const embedding = Array.from({length: 384}, (_, index) => index / 384);
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
    if (address.endsWith('/functions/v1/embed')) return Response.json({embedding});
    if (address.endsWith('/rpc/recommend_nearby_events_v2')) {
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
  assert.equal(calls.length, 5);
  const embeddingCall = calls.find((call) => call.url.endsWith('/functions/v1/embed'));
  assert.deepEqual(JSON.parse(embeddingCall.options.body), {
    input: 'quiet outdoor activities',
  });
  const hybridCall = calls.find((call) => call.url.endsWith('/rpc/recommend_nearby_events_v2'));
  const rpcBody = JSON.parse(hybridCall.options.body);
  assert.equal(rpcBody.p_query_embedding.length, 384);
  assert.equal(rpcBody.p_query, 'quiet outdoor activities');
  assert.equal(rpcBody.p_limit, 30);
});

test('event indexing embeds title, category, venue, address, and description', async () => {
  const calls = [];
  const tasks = [];
  const embedding = Array(384).fill(0.25);
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
    if (address.endsWith('/rpc/create_event_v3')) return Response.json([eventId]);
    if (address.endsWith('/functions/v1/embed')) return Response.json({embedding});
    if (address.endsWith('/rpc/set_event_embedding')) return Response.json(true);
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/events', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        title: 'Riverside yoga',
        description: 'A gentle outdoor class for beginners.',
        category: 'Fitness',
        venue_name: 'Neckar meadow',
        address: 'Josef-Braun-Ufer, Mannheim',
        latitude: 49.49,
        longitude: 8.47,
        start_at: '2099-01-01T08:00:00Z',
        end_at: '2099-01-01T09:00:00Z',
        max_participants: 20,
      }),
    }),
    env,
    (task) => tasks.push(task),
  );
  await Promise.all(tasks);

  assert.equal(response.status, 201);
  const embedCall = calls.find((call) => call.url.endsWith('/functions/v1/embed'));
  assert.deepEqual(JSON.parse(embedCall.options.body), {
    input: [
      'Title: Riverside yoga',
      'Category: Fitness',
      'Venue: Neckar meadow',
      'Address: Josef-Braun-Ufer, Mannheim',
      'Description: A gentle outdoor class for beginners.',
    ].join('\n'),
  });
  const indexCall = calls.find((call) => call.url.endsWith('/rpc/set_event_embedding'));
  assert.equal(JSON.parse(indexCall.options.body).p_embedding.length, 384);
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

test('following discovery uses the dedicated feed and applies practical filters', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
    if (address.endsWith('/rpc/list_followed_nearby_events')) {
      return Response.json([
        {
          id: eventId,
          organizer_id: postId,
          category: 'Games',
          start_at: '2099-01-03T18:00:00Z',
          joined_count: 4,
          max_participants: 10,
        },
        {
          id: eventId2,
          organizer_id: postId2,
          category: 'Fitness',
          start_at: '2099-01-03T18:00:00Z',
          joined_count: 3,
          max_participants: 10,
        },
      ]);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request(
      'https://gather2gether.pages.dev/api/v1/events/nearby' +
        '?latitude=52.52&longitude=13.405&radius_km=10&interest=games' +
        '&category=Games&start_from=2099-01-03T00%3A00%3A00Z' +
        '&start_before=2099-01-04T00%3A00%3A00Z&time_filter=evening' +
        '&spots_only=true&following_only=true&timezone_offset_minutes=60',
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    env,
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(payload.data.map((event) => event.id), [eventId]);
  const followedCall = calls.find((call) =>
    call.url.endsWith('/rpc/list_followed_nearby_events')
  );
  assert.deepEqual(JSON.parse(followedCall.options.body), {
    p_latitude: 52.52,
    p_longitude: 13.405,
    p_radius_km: 10,
    p_query: 'games',
  });
  assert.equal(calls.some((call) => call.url.endsWith('/functions/v1/embed')), false);
});

test('saved event searches persist only validated discovery settings', async () => {
  let rpcBody;
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/create_saved_event_search')) {
      rpcBody = JSON.parse(options.body);
      return Response.json(searchId);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/event-searches', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: 'Weekend games',
        interest: 'board games',
        radius_km: 10,
        category: 'Games',
        date_filter: 'weekend',
        time_filter: 'evening',
        timezone_offset_minutes: 60,
        spots_only: true,
        following_only: false,
      }),
    }),
    env,
  );

  assert.equal(response.status, 201);
  assert.deepEqual(rpcBody, {
    p_name: 'Weekend games',
    p_interest: 'board games',
    p_radius_km: 10,
    p_category: 'Games',
    p_date_filter: 'weekend',
    p_time_filter: 'evening',
    p_timezone_offset_minutes: 60,
    p_spots_only: true,
    p_following_only: false,
    p_beginner_friendly_only: false,
    p_wheelchair_accessible_only: false,
    p_event_setting: 'any',
    p_event_language: '',
    p_age_guidance: 'any',
    p_alerts_enabled: true,
  });
});

test('practical event filters are applied through a bounded detail RPC', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
    if (address.endsWith('/rpc/recommend_personalized_events')) {
      return Response.json([
        {id: eventId, title: 'Indoor games'},
        {id: eventId2, title: 'Accessible park walk'},
      ]);
    }
    if (address.endsWith('/rpc/filter_event_ids_by_details')) {
      return Response.json([eventId2]);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request(
      'https://gather2gether.pages.dev/api/v1/events/nearby' +
        '?latitude=52.52&longitude=13.405&radius_km=10' +
        '&beginner_friendly_only=true&wheelchair_accessible_only=true' +
        '&event_setting=outdoor&event_language=English&age_guidance=all_ages',
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    env,
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(payload.data.map((event) => event.id), [eventId2]);
  const detailFilterCall = calls.find((call) =>
    call.url.endsWith('/rpc/filter_event_ids_by_details')
  );
  assert.deepEqual(JSON.parse(detailFilterCall.options.body), {
    p_event_ids: [eventId, eventId2],
    p_beginner_friendly_only: true,
    p_wheelchair_accessible_only: true,
    p_event_setting: 'outdoor',
    p_event_language: 'English',
    p_age_guidance: 'all_ages',
  });
});

test('saved searches can be renamed, replaced, paused, and resumed', async () => {
  let rpcBody;
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/update_saved_event_search')) {
      rpcBody = JSON.parse(options.body);
      return Response.json(true);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/event-searches/${searchId}`, {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: 'Accessible walks',
        interest: 'walking',
        radius_km: 25,
        category: null,
        date_filter: 'any',
        time_filter: 'morning',
        timezone_offset_minutes: 60,
        spots_only: true,
        following_only: false,
        beginner_friendly_only: true,
        wheelchair_accessible_only: true,
        event_setting: 'outdoor',
        event_language: 'English',
        age_guidance: 'all_ages',
        alerts_enabled: false,
      }),
    }),
    env,
  );

  assert.equal(response.status, 200);
  assert.equal(rpcBody.p_search_id, searchId);
  assert.equal(rpcBody.p_alerts_enabled, false);
  assert.equal(rpcBody.p_wheelchair_accessible_only, true);
  assert.equal(rpcBody.p_name, 'Accessible walks');
});

test('search alerts list through the authenticated collection route', async () => {
  globalThis.fetch = async (url) => {
    const address = String(url);
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/list_saved_event_searches')) {
      return Response.json([{id: searchId, name: 'Weekend games'}]);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/event-searches', {
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(payload.data, [{id: searchId, name: 'Weekend games'}]);
});

test('attendee privacy, discussion muting, and RSVP confirmation use fixed RPCs', async () => {
  const rpcNames = [];
  globalThis.fetch = async (url) => {
    const address = String(url);
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    const rpcName = address.split('/rpc/')[1];
    rpcNames.push(rpcName);
    if (rpcName === 'list_event_attendees_v2') return Response.json([]);
    if (rpcName === 'set_event_attendee_visibility') return Response.json(true);
    if (rpcName === 'set_event_discussion_notifications') return Response.json(false);
    if (rpcName === 'request_event_rsvp_reconfirmation_v2') {
      return Response.json('2098-12-31T18:00:00Z');
    }
    if (rpcName === 'confirm_event_rsvp') return Response.json('2099-01-01T00:00:00Z');
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const requests = [
    new Request(
      `https://gather2gether.pages.dev/api/v1/events/${eventId}/attendees`,
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    new Request(
      `https://gather2gether.pages.dev/api/v1/events/${eventId}/attendees/visibility`,
      {
        method: 'PUT',
        headers: {Authorization: 'Bearer user-token', 'Content-Type': 'application/json'},
        body: JSON.stringify({visible: true}),
      },
    ),
    new Request(
      `https://gather2gether.pages.dev/api/v1/events/${eventId}/discussion-notifications`,
      {
        method: 'PUT',
        headers: {Authorization: 'Bearer user-token', 'Content-Type': 'application/json'},
        body: JSON.stringify({enabled: false}),
      },
    ),
    new Request(
      `https://gather2gether.pages.dev/api/v1/events/${eventId}/reconfirmation/request`,
      {method: 'POST', headers: {Authorization: 'Bearer user-token'}},
    ),
    new Request(
      `https://gather2gether.pages.dev/api/v1/events/${eventId}/reconfirmation/confirm`,
      {method: 'POST', headers: {Authorization: 'Bearer user-token'}},
    ),
  ];
  const responses = [];
  for (const request of requests) responses.push(await handleApiRequest(request, env));

  assert.deepEqual(responses.map((response) => response.status), [200, 200, 200, 200, 200]);
  assert.deepEqual(rpcNames, [
    'list_event_attendees_v2',
    'set_event_attendee_visibility',
    'set_event_discussion_notifications',
    'request_event_rsvp_reconfirmation_v2',
    'confirm_event_rsvp',
  ]);
});

test('host dashboard and attendance stay behind organizer RPCs', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/get_event_host_dashboard')) {
      return Response.json({joined_count: 4, attended_count: 2, no_show_count: 1});
    }
    if (address.endsWith('/rpc/set_event_attendance')) return Response.json(true);
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const dashboard = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/events/${eventId}/host-dashboard`, {
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );
  const attendance = await handleApiRequest(
    new Request(
      `https://gather2gether.pages.dev/api/v1/events/${eventId}/attendance/${postId}`,
      {
        method: 'PUT',
        headers: {Authorization: 'Bearer user-token', 'Content-Type': 'application/json'},
        body: JSON.stringify({status: 'attended'}),
      },
    ),
    env,
  );

  assert.equal(dashboard.status, 200);
  assert.equal((await dashboard.json()).data.attended_count, 2);
  assert.equal(attendance.status, 200);
  const attendanceCall = calls.find((call) => call.url.endsWith('/rpc/set_event_attendance'));
  assert.deepEqual(JSON.parse(attendanceCall.options.body), {
    p_event_id: eventId,
    p_profile_id: postId,
    p_status: 'attended',
  });
});

test('event owners manage co-hosts through username-only RPC contracts', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/list_event_cohosts')) {
      return Response.json([{
        profile_id: userId,
        display_name: 'Owner',
        username: 'owner',
        role: 'Owner',
        viewer_can_edit: true,
      }]);
    }
    if (address.endsWith('/rpc/set_event_cohost')) return Response.json(postId);
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const listed = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/events/${eventId}/cohosts`, {
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );
  const added = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/events/${eventId}/cohosts`, {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({username: '@alex_local'}),
    }),
    env,
  );

  assert.equal(listed.status, 200);
  assert.equal((await listed.json()).data[0].role, 'Owner');
  assert.equal(added.status, 200);
  const addCall = calls.find((call) => call.url.endsWith('/rpc/set_event_cohost'));
  assert.deepEqual(JSON.parse(addCall.options.body), {
    p_event_id: eventId,
    p_username: '@alex_local',
    p_enabled: true,
  });
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

test('my events uses a fixed member-scoped filter RPC', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    return Response.json([{id: eventId, title: 'Saved plan'}]);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/events/mine?filter=saved', {
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );

  assert.equal(response.status, 200);
  assert.match(calls[1].url, /\/rpc\/list_my_events_v2$/);
  assert.deepEqual(JSON.parse(calls[1].options.body), {p_filter: 'saved'});
});

test('saving and removing an event call the same state-setting RPC', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    return Response.json(true);
  };

  const saved = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/events/${eventId}/save`, {
      method: 'PUT',
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );
  const removed = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/events/${eventId}/save`, {
      method: 'DELETE',
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );

  assert.equal(saved.status, 200);
  assert.equal(removed.status, 200);
  const rpcCalls = calls.filter((call) => call.url.endsWith('/rpc/set_event_saved'));
  assert.deepEqual(JSON.parse(rpcCalls[0].options.body), {
    p_event_id: eventId,
    p_saved: true,
  });
  assert.deepEqual(JSON.parse(rpcCalls[1].options.body), {
    p_event_id: eventId,
    p_saved: false,
  });
});

test('event feedback enforces attendance and rating consistency at the edge', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls += 1;
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    throw new Error('invalid feedback must not reach the database');
  };

  const response = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/events/${eventId}/feedback`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({attended: false, rating: 5, comment: ''}),
    }),
    env,
  );

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'feedback_validation');
  assert.equal(calls, 1);
});

test('event discussion reports forward only an allow-listed reason', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    return Response.json(true);
  };

  const response = await handleApiRequest(
    new Request(
      `https://gather2gether.pages.dev/api/v1/events/${eventId}/discussion/${commentId}/report`,
      {
        method: 'POST',
        headers: {
          Authorization: 'Bearer user-token',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({reason: 'unsafe_behaviour'}),
      },
    ),
    env,
  );

  assert.equal(response.status, 201);
  assert.match(calls[1].url, /\/rpc\/report_event_discussion_message$/);
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    p_message_id: commentId,
    p_reason: 'unsafe_behaviour',
  });
});

test('forum list authenticates and uses the personalized feed RPC', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
    if (address.endsWith('/rpc/recommend_personalized_forum_posts')) {
      return Response.json([{id: postId, title: 'Weekend hiking group'}]);
    }
    if (address.endsWith('/rpc/list_forum_posts')) {
      return Response.json([{id: postId, title: 'Weekend hiking group'}]);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/forum/posts', {
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  const personalizedCall = calls.find((call) =>
    call.url.endsWith('/rpc/recommend_personalized_forum_posts')
  );
  assert.match(personalizedCall.url, /\/rest\/v1\/rpc\/recommend_personalized_forum_posts$/);
  assert.deepEqual(JSON.parse(personalizedCall.options.body), {
    p_limit: 30,
    p_before: null,
  });
  const latestCall = calls.find((call) => call.url.endsWith('/rpc/list_forum_posts'));
  assert.match(latestCall.url, /\/rest\/v1\/rpc\/list_forum_posts$/);
  assert.deepEqual(JSON.parse(latestCall.options.body), {
    p_limit: 30,
    p_before: null,
  });
  assert.equal(payload.data[0].id, postId);
});

test('community feed interleaves three recommendations with one latest post', async () => {
  const ids = Array.from(
    {length: 8},
    (_, index) => `${String(index + 10).padStart(8, '0')}-1111-4111-8111-111111111111`,
  );
  const recommended = ids.map((id, index) => ({
    id,
    title: `Recommendation ${index + 1}`,
    created_at: `2026-09-${String(index + 1).padStart(2, '0')}T12:00:00Z`,
  }));
  const latest = [...recommended].reverse();

  globalThis.fetch = async (url) => {
    const address = String(url);
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
    if (address.endsWith('/rpc/recommend_personalized_forum_posts')) {
      return Response.json(recommended);
    }
    if (address.endsWith('/rpc/list_forum_posts')) {
      return Response.json(latest);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/forum/posts', {
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(payload.data.map((post) => post.id), [
    ids[0],
    ids[1],
    ids[2],
    ids[7],
    ids[3],
    ids[4],
    ids[5],
    ids[6],
  ]);
  assert.equal(new Set(payload.data.map((post) => post.id)).size, 8);
});

test('community feed keeps its deterministic order when AI reranking is unavailable', async () => {
  let modelCalls = 0;
  const originalOrder = [
    {
      id: postId,
      title: 'Local photo walk',
      category: 'Looking for group',
      body: 'Take street photos together.',
    },
    {
      id: postId2,
      title: 'Weekend run',
      category: 'Event ideas',
      body: 'Plan an easy run in the park.',
    },
  ];
  globalThis.fetch = async (url) => {
    const address = String(url);
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
    if (address.endsWith('/rpc/recommend_personalized_forum_posts')) {
      return Response.json(originalOrder);
    }
    if (address.endsWith('/rpc/list_forum_posts')) {
      return Response.json(originalOrder);
    }
    if (address.endsWith('/rpc/get_ai_recommendation_state')) {
      return Response.json({
        eligible: true,
        preference_query: 'Action: like | Topic: Local tips | Discussion: Photo spots',
        cache_key: 'abcdef0123456789abcdef0123456789',
        ranked_ids: null,
      });
    }
    if (address.endsWith('/rpc/claim_ai_recommendation_rerank')) {
      return Response.json(true);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/forum/posts', {
      headers: {Authorization: 'Bearer user-token'},
    }),
    {
      ...env,
      ASSISTANT_MODEL: {
        fetch: async (request) => {
          modelCalls += 1;
          assert.equal(new URL(request.url).pathname, '/rerank');
          return Response.json({error: 'provider_unavailable'}, {status: 503});
        },
      },
    },
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  assert.equal(modelCalls, 1);
  assert.deepEqual(payload.data, originalOrder);
});

test('opening an event records a non-blocking de-duplicated view signal', async () => {
  const calls = [];
  const tasks = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/process_due_event_reconfirmations')) {
      return Response.json(0);
    }
    if (address.endsWith('/rpc/get_event_details_v3')) {
      return Response.json([{id: eventId, title: 'Morning Run'}]);
    }
    if (address.endsWith('/rpc/record_recommendation_view')) {
      return Response.json(true);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/events/${eventId}`, {
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
    (task) => tasks.push(task),
  );
  await Promise.all(tasks);

  assert.equal(response.status, 200);
  const detailsCall = calls.find((call) =>
    call.url.endsWith('/rpc/get_event_details_v3')
  );
  assert.deepEqual(JSON.parse(detailsCall.options.body), {
    p_event_id: eventId,
    p_via_invite: false,
  });
  const viewCall = calls.find((call) =>
    call.url.endsWith('/rpc/record_recommendation_view')
  );
  assert.deepEqual(JSON.parse(viewCall.options.body), {
    p_content_kind: 'event',
    p_content_id: eventId,
  });
});

test('invite access and bounded recurrence are explicit in the event API', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/process_due_event_reconfirmations')) {
      return Response.json(0);
    }
    if (address.endsWith('/rpc/get_event_details_v3')) {
      return Response.json([{id: eventId, event_visibility: 'unlisted'}]);
    }
    if (address.endsWith('/rpc/create_event_v3')) {
      return Response.json([eventId, eventId2, eventId3]);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const invited = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/events/${eventId}?invite=1`, {
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );
  const created = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/events', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        title: 'Monthly supper',
        description: 'Three relaxed community suppers.',
        category: 'Social',
        venue_name: 'Neighbourhood hall',
        address: 'Main street, Mannheim',
        latitude: 49.49,
        longitude: 8.47,
        start_at: '2099-01-01T18:00:00Z',
        end_at: '2099-01-01T20:00:00Z',
        max_participants: 20,
        visibility: 'unlisted',
        repeat_interval: 'monthly',
        repeat_count: 3,
      }),
    }),
    env,
  );

  assert.equal(invited.status, 200);
  const detailCall = calls.find((call) => call.url.endsWith('/rpc/get_event_details_v3'));
  assert.equal(JSON.parse(detailCall.options.body).p_via_invite, true);
  assert.equal(created.status, 201);
  assert.deepEqual((await created.json()).ids, [eventId, eventId2, eventId3]);
  const createCall = calls.find((call) => call.url.endsWith('/rpc/create_event_v3'));
  const createBody = JSON.parse(createCall.options.body);
  assert.equal(createBody.p_visibility, 'unlisted');
  assert.equal(createBody.p_repeat_interval, 'monthly');
  assert.equal(createBody.p_repeat_count, 3);
});

test('forum detail includes like state and records its view in the background', async () => {
  const calls = [];
  const tasks = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/get_forum_post')) {
      return Response.json([{id: postId, title: 'Weekend hiking group'}]);
    }
    if (address.endsWith('/rpc/get_forum_post_like_state')) {
      return Response.json({liked: true, like_count: 7});
    }
    if (address.endsWith('/rpc/record_recommendation_view')) {
      return Response.json(true);
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/forum/posts/${postId}`, {
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
    (task) => tasks.push(task),
  );
  const payload = await response.json();
  await Promise.all(tasks);

  assert.equal(response.status, 200);
  assert.equal(payload.data.liked, true);
  assert.equal(payload.data.like_count, 7);
  const viewCall = calls.find((call) =>
    call.url.endsWith('/rpc/record_recommendation_view')
  );
  assert.deepEqual(JSON.parse(viewCall.options.body), {
    p_content_kind: 'forum_post',
    p_content_id: postId,
  });
});

test('forum like endpoint forwards only the requested boolean state', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    return Response.json({liked: true, like_count: 3, changed: true});
  };

  const response = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/forum/posts/${postId}/like`, {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({liked: true}),
    }),
    env,
  );

  assert.equal(response.status, 200);
  assert.match(calls[1].url, /\/rpc\/set_forum_post_like$/);
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    p_post_id: postId,
    p_liked: true,
  });
  assert.deepEqual((await response.json()).data, {
    liked: true,
    like_count: 3,
    changed: true,
  });
});

test('community interest search uses the indexed hybrid feed RPC', async () => {
  const calls = [];
  const embedding = Array(384).fill(0.125);
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/functions/v1/embed')) return Response.json({embedding});
    const controls = recommendationControlResponse(address);
    if (controls !== null) return controls;
    if (address.endsWith('/rpc/recommend_forum_posts_v2')) {
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
  const recommendationCall = calls.find((call) =>
    call.url.endsWith('/rpc/recommend_forum_posts_v2')
  );
  assert.match(recommendationCall.url, /\/rpc\/recommend_forum_posts_v2$/);
  const rpcBody = JSON.parse(recommendationCall.options.body);
  assert.equal(rpcBody.p_query_embedding.length, 384);
  assert.equal(rpcBody.p_query, 'people learning new skills');
});

test('community indexing embeds topic, title, body, place, and address', async () => {
  const calls = [];
  const tasks = [];
  const embedding = Array(384).fill(0.5);
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/create_forum_post')) return Response.json(postId);
    if (address.endsWith('/functions/v1/embed')) return Response.json({embedding});
    if (address.endsWith('/rpc/set_forum_post_embedding')) return Response.json(true);
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/forum/posts', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        title: 'Sketching together',
        body: 'Bring a pencil and meet other local artists.',
        category: 'Looking for group',
        place_name: 'Kunsthalle Mannheim',
        place_address: 'Friedrichsplatz 4, Mannheim',
      }),
    }),
    env,
    (task) => tasks.push(task),
  );
  await Promise.all(tasks);

  assert.equal(response.status, 201);
  const embedCall = calls.find((call) => call.url.endsWith('/functions/v1/embed'));
  assert.deepEqual(JSON.parse(embedCall.options.body), {
    input: [
      'Title: Sketching together',
      'Topic: Looking for group',
      'Place: Kunsthalle Mannheim',
      'Address: Friedrichsplatz 4, Mannheim',
      'Description: Bring a pencil and meet other local artists.',
    ].join('\n'),
  });
  const indexCall = calls.find((call) =>
    call.url.endsWith('/rpc/set_forum_post_embedding')
  );
  assert.equal(JSON.parse(indexCall.options.body).p_embedding.length, 384);
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

test('profile block controls and blocked-member listing use fixed authenticated RPCs', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/list_blocked_profiles')) {
      return Response.json([{
        id: postId,
        display_name: 'Alex',
        username: 'alex_local',
        blocked_at: '2026-09-04T10:00:00Z',
      }]);
    }
    if (address.endsWith('/rpc/set_profile_block')) return Response.json(true);
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const blocked = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/profiles/${postId}/block`, {
      method: 'PUT',
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );
  const listed = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/blocks', {
      headers: {Authorization: 'Bearer user-token'},
    }),
    env,
  );

  assert.equal(blocked.status, 200);
  assert.deepEqual(await blocked.json(), {blocked: true});
  const blockCall = calls.find((call) => call.url.endsWith('/rpc/set_profile_block'));
  assert.deepEqual(JSON.parse(blockCall.options.body), {
    p_profile_id: postId,
    p_blocked: true,
  });
  assert.equal(listed.status, 200);
  assert.equal((await listed.json()).data[0].username, 'alex_local');
  assert.equal(calls.some((call) => call.url.endsWith('/rpc/list_blocked_profiles')), true);
});

test('account deletion requires an exact confirmation and cleans only owned media', async () => {
  const calls = [];
  const deletedKeys = [];
  const avatarKey = `avatars/${userId}/${eventId}.jpg`;
  const postKey = `posts/${userId}/${postId}.jpg`;
  const foreignKey = `posts/${postId}/${eventId}.jpg`;
  const deletionEnv = {
    ...env,
    USER_MEDIA: {
      get: async () => null,
      put: async () => {},
      delete: async (key) => deletedKeys.push(key),
    },
  };
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/delete_own_account')) {
      return Response.json({
        avatar_image_key: avatarKey,
        forum_image_keys: [postKey, foreignKey],
      });
    }
    throw new Error(`Unexpected fetch: ${address}`);
  };

  const rejected = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/account', {
      method: 'DELETE',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({confirmation: 'delete'}),
    }),
    deletionEnv,
  );
  assert.equal(rejected.status, 400);
  assert.equal((await rejected.json()).error.code, 'account_deletion_confirmation');

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/account', {
      method: 'DELETE',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({confirmation: 'DELETE'}),
    }),
    deletionEnv,
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {deleted: true});
  const deleteCall = calls.find((call) => call.url.endsWith('/rpc/delete_own_account'));
  assert.deepEqual(JSON.parse(deleteCall.options.body), {p_confirmation: 'DELETE'});
  assert.deepEqual(new Set(deletedKeys), new Set([
    avatarKey,
    postKey,
    `staging/forum/${userId}/current.jpg`,
    `staging/events/${userId}/current.jpg`,
  ]));
});

test('profile event history uses only the target profile and allow-listed filter', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({url: String(url), options});
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: userId});
    return Response.json([{id: eventId, title: 'Past community walk'}]);
  };

  const response = await handleApiRequest(
    new Request(
      `https://gather2gether.pages.dev/api/v1/profiles/${postId}/events?filter=past`,
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    env,
  );

  assert.equal(response.status, 200);
  assert.match(calls[1].url, /\/rpc\/list_profile_events$/);
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    p_profile_id: postId,
    p_filter: 'past',
  });
  assert.deepEqual((await response.json()).data, [
    {id: eventId, title: 'Past community walk'},
  ]);

  const invalid = await handleApiRequest(
    new Request(
      `https://gather2gether.pages.dev/api/v1/profiles/${postId}/events?filter=joined`,
      {headers: {Authorization: 'Bearer user-token'}},
    ),
    env,
  );
  assert.equal(invalid.status, 400);
  assert.equal((await invalid.json()).error.code, 'invalid_profile_event_filter');
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

test('AI drafting is rate-limited and returns a validated editable draft', async () => {
  const calls = [];
  let serviceBody;
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/claim_ai_tool_use')) return Response.json(true);
    throw new Error(`Unexpected fetch: ${address}`);
  };
  const draft = {
    title: 'Beginner photo walk',
    description: 'A relaxed practice walk.',
    category: 'Photography',
    beginner_friendly: true,
    event_setting: 'outdoor',
    event_language: 'English',
    age_guidance: 'all_ages',
    what_to_bring: 'A phone or camera',
  };

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/assistant/event-draft', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        prompt: 'A welcoming photography walk for complete beginners',
        locale: 'en-DE',
      }),
    }),
    {
      ...env,
      ASSISTANT_MODEL: {
        fetch: async (request) => {
          assert.equal(new URL(request.url).pathname, '/event-draft');
          serviceBody = await request.json();
          return Response.json(draft);
        },
      },
    },
  );

  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).draft, draft);
  const claim = calls.find((call) => call.url.endsWith('/rpc/claim_ai_tool_use'));
  assert.deepEqual(JSON.parse(claim.options.body), {p_tool: 'event_draft'});
  assert.equal(serviceBody.locale, 'en-DE');
});

test('natural filters and quality review use bounded assistant service contracts', async () => {
  const modelCalls = [];
  globalThis.fetch = async (url) => {
    const address = String(url);
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/claim_ai_tool_use')) return Response.json(true);
    throw new Error(`Unexpected fetch: ${address}`);
  };
  const assistantModel = {
    fetch: async (request) => {
      const path = new URL(request.url).pathname;
      const body = await request.json();
      modelCalls.push({path, body});
      if (path === '/event-filters') {
        return Response.json({
          interest: 'beginner photography',
          category: 'Photography',
          date_filter: 'weekend',
          time_filter: 'morning',
          spots_only: true,
          following_only: false,
          beginner_friendly_only: true,
          wheelchair_accessible_only: false,
          event_setting: 'outdoor',
          event_language: '',
          age_guidance: 'any',
          radius_km: 25,
        });
      }
      return Response.json({
        ready: true,
        issues: [{field: 'description', severity: 'info', message: 'Clear and specific.'}],
      });
    },
  };

  const filters = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/assistant/event-filters', {
      method: 'POST',
      headers: {Authorization: 'Bearer user-token', 'Content-Type': 'application/json'},
      body: JSON.stringify({
        query: 'Beginner photography outdoors this weekend',
        locale: 'en-DE',
      }),
    }),
    {...env, ASSISTANT_MODEL: assistantModel},
  );
  const quality = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/assistant/event-quality', {
      method: 'POST',
      headers: {Authorization: 'Bearer user-token', 'Content-Type': 'application/json'},
      body: JSON.stringify({
        title: 'Photo walk',
        description: 'A relaxed photo walk for neighbours.',
        category: 'Photography',
        venue_name: 'River gate',
        address: 'River Street, Mannheim',
        start_at: '2099-01-01T10:00:00Z',
        end_at: '2099-01-01T12:00:00Z',
        max_participants: 12,
        what_to_bring: 'A phone or camera',
      }),
    }),
    {...env, ASSISTANT_MODEL: assistantModel},
  );

  assert.equal(filters.status, 200);
  assert.equal((await filters.json()).filters.radius_km, 25);
  assert.equal(quality.status, 200);
  assert.equal((await quality.json()).quality.ready, true);
  assert.deepEqual(modelCalls.map((call) => call.path), ['/event-filters', '/event-quality']);
  assert.deepEqual(modelCalls[0].body, {
    query: 'Beginner photography outdoors this weekend',
    locale: 'en-DE',
  });
  assert.equal(modelCalls[1].body.event.max_participants, 12);
});

test('event translation and discussion summaries use authorized database content', async () => {
  const calls = [];
  const servicePaths = [];
  globalThis.fetch = async (url, options = {}) => {
    const address = String(url);
    calls.push({url: address, options});
    if (address.endsWith('/auth/v1/user')) return Response.json({id: userId});
    if (address.endsWith('/rpc/get_event_details_v3')) {
      return Response.json([{
        title: 'Morning Run',
        description: 'An easy social run.',
        what_to_bring: 'Water',
      }]);
    }
    if (address.endsWith('/rpc/list_event_discussion')) {
      return Response.json([
        {author_name: 'Alex', body: 'Meet by the north gate.'},
        {author_name: 'Maya', body: 'I will bring cups.'},
      ]);
    }
    if (address.endsWith('/rpc/claim_ai_tool_use')) return Response.json(true);
    throw new Error(`Unexpected fetch: ${address}`);
  };
  const toolEnv = {
    ...env,
    ASSISTANT_MODEL: {
      fetch: async (request) => {
        const path = new URL(request.url).pathname;
        servicePaths.push(path);
        if (path === '/translate') {
          const body = await request.json();
          assert.equal(body.target_language, 'German');
          assert.equal(body.text.includes('Morning Run'), true);
          return Response.json({translation: 'Titel: Morgenlauf'});
        }
        if (path === '/summarize') {
          const body = await request.json();
          assert.equal(body.messages.length, 2);
          return Response.json({
            summary: 'Meet at the north gate.',
            action_items: ['Maya brings cups.'],
          });
        }
        throw new Error(`Unexpected service path: ${path}`);
      },
    },
  };

  const translated = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/events/${eventId}/translation`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer user-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({target_language: 'German'}),
    }),
    toolEnv,
  );
  const summarized = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/events/${eventId}/discussion-summary`, {
      method: 'POST',
      headers: {Authorization: 'Bearer user-token'},
    }),
    toolEnv,
  );

  assert.equal(translated.status, 200);
  assert.equal((await translated.json()).translation, 'Titel: Morgenlauf');
  assert.equal(summarized.status, 200);
  assert.deepEqual((await summarized.json()).action_items, ['Maya brings cups.']);
  assert.deepEqual(servicePaths, ['/translate', '/summarize']);
  const claims = calls
    .filter((call) => call.url.endsWith('/rpc/claim_ai_tool_use'))
    .map((call) => JSON.parse(call.options.body).p_tool);
  assert.deepEqual(claims, ['translation', 'summary']);
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
