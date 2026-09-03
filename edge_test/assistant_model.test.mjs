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
