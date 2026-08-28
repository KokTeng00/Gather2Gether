import assert from 'node:assert/strict';
import test from 'node:test';

import {onRequest} from '../functions/[[path]].js';

test('non-API browser routes return a hardened 404', () => {
  const response = onRequest();

  assert.equal(response.status, 404);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('x-frame-options'), 'DENY');
});
