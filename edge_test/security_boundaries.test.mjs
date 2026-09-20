import assert from 'node:assert/strict';
import test from 'node:test';

import {handleApiRequest} from '../functions/api/v1/[[path]].js';
import {handleModelRequest} from '../workers/assistant-model.js';
import {BodyTooLargeError, readBoundedText} from '../supabase/functions/_shared/http-body.js';

// Deliberately omit a trustworthy Content-Length. A rejected body must be
// cancelled as soon as it crosses the limit, before the rest is buffered.
function oversizedRequest(url, headers, chunkBytes) {
  let chunksRead = 0;
  let cancelled = false;
  const stream = new ReadableStream({
    pull(controller) {
      chunksRead += 1;
      controller.enqueue(new Uint8Array(chunkBytes).fill(32));
      if (chunksRead === 20) controller.close();
    },
    cancel() { cancelled = true; },
  });
  return {
    request: new Request(url, {method: 'POST', headers, body: stream, duplex: 'half'}),
    assertStoppedEarly() {
      assert.equal(cancelled, true, 'oversized request stream must be cancelled');
      assert.ok(chunksRead <= 4, `read ${chunksRead} chunks before rejecting`);
    },
  };
}

for (const declaredLength of [null, '2']) {
  test(`API stops oversized streamed JSON (declared length: ${declaredLength})`, async (t) => {
    const originalFetch = globalThis.fetch;
    t.after(() => { globalThis.fetch = originalFetch; });
    let calls = 0;
    globalThis.fetch = async (url) => {
      calls += 1;
      assert.match(String(url), /\/auth\/v1\/user$/);
      return Response.json({id: '11111111-1111-4111-8111-111111111111'});
    };
    const headers = {Authorization: 'Bearer test-user', 'Content-Type': 'application/json'};
    if (declaredLength !== null) headers['Content-Length'] = declaredLength;
    const body = oversizedRequest('https://app.test/api/v1/events', headers, 20 * 1024);
    const response = await handleApiRequest(body.request, {
      SUPABASE_URL: 'https://project.supabase.co',
      SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test_key_long_enough',
    });
    assert.equal(response.status, 413);
    assert.equal(calls, 1, 'oversized body must not reach a mutation RPC');
    body.assertStoppedEarly();
  });
}

test('model service stops oversized streamed JSON before accessing credentials', async () => {
  const body = oversizedRequest('https://model.test/chat', {'Content-Type': 'application/json'}, 50 * 1024);
  const response = await handleModelRequest(body.request, {
    OPENROUTER_API_KEY: {get() { assert.fail('must not read provider credentials'); }},
  });
  assert.equal(response.status, 413);
  body.assertStoppedEarly();
});

test('shared body limit counts UTF-8 bytes and preserves split characters', async () => {
  const bytes = new TextEncoder().encode('你好');
  const message = () => new Response(new ReadableStream({start(controller) {
    controller.enqueue(bytes.slice(0, 2));
    controller.enqueue(bytes.slice(2));
    controller.close();
  }}));
  assert.equal(await readBoundedText(message(), 6), '你好');
  await assert.rejects(readBoundedText(message(), 5), BodyTooLargeError);
});
