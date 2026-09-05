import assert from 'node:assert/strict';
import test, {afterEach} from 'node:test';

import {handleModelRequest} from '../workers/assistant-model.js';

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

test('model worker resolves the account secret and uses Gemini 3.1 Flash Lite', async () => {
  let secretReads = 0;
  let modelRequest;
  globalThis.fetch = async (url, options) => {
    assert.equal(String(url), 'https://openrouter.ai/api/v1/chat/completions');
    modelRequest = JSON.parse(options.body);
    return Response.json({
      choices: [{message: {content: 'Bring water and check the event details.'}}],
    });
  };

  const response = await handleModelRequest(
    new Request('https://assistant.internal/chat', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        history: [{role: 'user', content: 'What should I bring?'}],
        event_matches: [],
        event_search_requested: false,
        location_available: false,
      }),
    }),
    {
      OPENROUTER_API_KEY: {
        get: async () => {
          secretReads += 1;
          return 'openrouter-test-key-long-enough';
        },
      },
    },
  );

  assert.equal(response.status, 200);
  assert.equal(secretReads, 1);
  assert.equal(modelRequest.model, 'google/gemini-3.1-flash-lite');
  assert.equal(modelRequest.reasoning.effort, 'minimal');
  assert.equal((await response.json()).answer, 'Bring water and check the event details.');
});

test('model worker rejects malformed service requests before reading the secret', async () => {
  let secretReads = 0;
  const response = await handleModelRequest(
    new Request('https://assistant.internal/chat', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({history: 'not-an-array'}),
    }),
    {OPENROUTER_API_KEY: {get: async () => { secretReads += 1; }}},
  );

  assert.equal(response.status, 400);
  assert.equal(secretReads, 0);
});

test('model worker uses Voyage reranking without sending internal candidate identifiers', async () => {
  let modelRequest;
  globalThis.fetch = async (url, options) => {
    assert.equal(String(url), 'https://openrouter.ai/api/v1/rerank');
    modelRequest = JSON.parse(options.body);
    return Response.json({
      results: [
        {index: 1, relevance_score: 0.91, document: 'second'},
        {index: 0, relevance_score: 0.42, document: 'first'},
      ],
    });
  };

  const firstId = '22222222-2222-4222-8222-222222222222';
  const secondId = '33333333-3333-4333-8333-333333333333';
  const response = await handleModelRequest(
    new Request('https://assistant.internal/rerank', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        surface: 'event',
        preference_query: 'Joined hiking and viewed nature walks.',
        candidates: [
          {id: firstId, document: 'Title: Coffee meetup'},
          {id: secondId, document: 'Title: Forest hike'},
        ],
      }),
    }),
    {
      OPENROUTER_API_KEY: {
        get: async () => 'openrouter-test-key-long-enough',
      },
    },
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  assert.equal(modelRequest.model, 'voyageai/rerank-2.5');
  assert.equal(modelRequest.top_n, 2);
  assert.deepEqual(modelRequest.provider, {data_collection: 'deny'});
  assert.deepEqual(modelRequest.documents, [
    'Title: Coffee meetup',
    'Title: Forest hike',
  ]);
  assert.equal(JSON.stringify(modelRequest).includes(firstId), false);
  assert.equal(JSON.stringify(modelRequest).includes(secondId), false);
  assert.deepEqual(payload.ranking, [
    {id: secondId, score: 0.91},
    {id: firstId, score: 0.42},
  ]);
});

test('model worker rejects an incomplete rerank response', async () => {
  globalThis.fetch = async () => Response.json({
    results: [{index: 0, relevance_score: 0.8}],
  });

  const response = await handleModelRequest(
    new Request('https://assistant.internal/rerank', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        surface: 'forum_post',
        preference_query: 'Liked local photography discussions.',
        candidates: [
          {
            id: '22222222-2222-4222-8222-222222222222',
            document: 'Title: Street photography',
          },
          {
            id: '33333333-3333-4333-8333-333333333333',
            document: 'Title: Running group',
          },
        ],
      }),
    }),
    {
      OPENROUTER_API_KEY: {
        get: async () => 'openrouter-test-key-long-enough',
      },
    },
  );

  assert.equal(response.status, 502);
  assert.equal((await response.json()).error, 'invalid_provider_response');
});

test('event drafting uses a strict schema and returns only editable event fields', async () => {
  let modelRequest;
  const draft = {
    title: 'Beginner photo walk',
    description: 'A relaxed walk to practise street photography together.',
    category: 'Photography',
    beginner_friendly: true,
    event_setting: 'outdoor',
    event_language: 'English',
    age_guidance: 'all_ages',
    what_to_bring: 'A phone or camera',
  };
  globalThis.fetch = async (_url, options) => {
    modelRequest = JSON.parse(options.body);
    return Response.json({
      choices: [{message: {content: JSON.stringify(draft)}}],
    });
  };

  const response = await handleModelRequest(
    new Request('https://assistant.internal/event-draft', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        prompt: 'A welcoming photo walk for beginners near the river',
        locale: 'en-DE',
      }),
    }),
    {
      OPENROUTER_API_KEY: {
        get: async () => 'openrouter-test-key-long-enough',
      },
    },
  );

  assert.equal(response.status, 200);
  assert.equal(modelRequest.response_format.type, 'json_schema');
  assert.equal(modelRequest.response_format.json_schema.strict, true);
  assert.deepEqual(modelRequest.provider, {
    require_parameters: true,
    data_collection: 'deny',
  });
  assert.deepEqual(await response.json(), draft);
  assert.equal(JSON.stringify(modelRequest).includes('Do not invent a venue'), true);
});

test('translation and summaries reject malformed model output', async () => {
  globalThis.fetch = async () => Response.json({
    choices: [{message: {content: JSON.stringify({unexpected: true})}}],
  });
  const secret = {
    OPENROUTER_API_KEY: {
      get: async () => 'openrouter-test-key-long-enough',
    },
  };

  const translation = await handleModelRequest(
    new Request('https://assistant.internal/translate', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({text: 'Meet at the park.', target_language: 'German'}),
    }),
    secret,
  );
  const summary = await handleModelRequest(
    new Request('https://assistant.internal/summarize', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({messages: ['Alex: At 10?', 'Maya: Yes, by the gate.']}),
    }),
    secret,
  );

  assert.equal(translation.status, 502);
  assert.equal(summary.status, 502);
});

test('event quality and natural filters use strict bounded schemas', async () => {
  const modelRequests = [];
  globalThis.fetch = async (_url, options) => {
    const request = JSON.parse(options.body);
    modelRequests.push(request);
    const name = request.response_format.json_schema.name;
    const content = name === 'event_quality'
      ? {
          ready: false,
          issues: [{
            field: 'what_to_bring',
            severity: 'warning',
            message: 'Explain whether participants need to bring equipment.',
          }],
        }
      : {
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
        };
    return Response.json({choices: [{message: {content: JSON.stringify(content)}}]});
  };
  const secret = {
    OPENROUTER_API_KEY: {
      get: async () => 'openrouter-test-key-long-enough',
    },
  };

  const quality = await handleModelRequest(
    new Request('https://assistant.internal/event-quality', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        event: {
          title: 'Photo walk',
          description: 'A relaxed community photo walk.',
          category: 'Photography',
          venue_name: 'River gate',
          address: 'River Street, Mannheim',
          start_at: '2099-01-01T10:00:00Z',
          end_at: '2099-01-01T12:00:00Z',
          max_participants: 12,
          what_to_bring: '',
        },
      }),
    }),
    secret,
  );
  const filters = await handleModelRequest(
    new Request('https://assistant.internal/event-filters', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        query: 'Beginner photography this weekend, outdoors in the morning',
        locale: 'en-DE',
      }),
    }),
    secret,
  );

  assert.equal(quality.status, 200);
  assert.equal(filters.status, 200);
  assert.equal(modelRequests.length, 2);
  for (const request of modelRequests) {
    assert.equal(request.response_format.type, 'json_schema');
    assert.equal(request.response_format.json_schema.strict, true);
    assert.deepEqual(request.provider, {
      require_parameters: true,
      data_collection: 'deny',
    });
  }
  assert.equal((await quality.json()).ready, false);
  assert.equal((await filters.json()).radius_km, 25);
});

test('moderation triage rejects duplicate report priorities', async () => {
  const reportId = '22222222-2222-4222-8222-222222222222';
  globalThis.fetch = async () => Response.json({
    choices: [{message: {content: JSON.stringify({
      priorities: [
        {report_id: reportId, priority: 'high', reason: 'First copy.'},
        {report_id: reportId, priority: 'low', reason: 'Duplicate copy.'},
      ],
    })}}],
  });

  const response = await handleModelRequest(
    new Request('https://assistant.internal/moderation-triage', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        reports: [
          {
            report_id: reportId,
            kind: 'forum_post',
            reason: 'unsafe_behaviour',
            title: 'Reported discussion',
            excerpt: 'A short report excerpt.',
          },
          {
            report_id: '33333333-3333-4333-8333-333333333333',
            kind: 'forum_comment',
            reason: 'harassment',
            title: 'Reported reply',
            excerpt: 'Another short excerpt.',
          },
        ],
      }),
    }),
    {
      OPENROUTER_API_KEY: {
        get: async () => 'openrouter-test-key-long-enough',
      },
    },
  );

  assert.equal(response.status, 502);
  assert.equal((await response.json()).error, 'invalid_provider_response');
});
