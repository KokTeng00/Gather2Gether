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
