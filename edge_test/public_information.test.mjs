import assert from 'node:assert/strict';
import test from 'node:test';
import {onRequest} from '../functions/[[path]].js';

const env = {APP_OPERATOR_NAME: 'Test operator', SUPPORT_EMAIL: 'support@example.test'};
for (const path of ['/privacy', '/terms', '/account-deletion', '/support']) {
  test(`${path} is accessible before login with real contact configuration`, async () => {
    const response = onRequest({request: new Request(`https://app.test${path}`, {
      headers: {Origin: 'https://app.test'},
    }), env});
    assert.equal(response.status, 200);
    const html = await response.text();
    assert.match(html, /support@example.test/);
    assert.match(html, /Test operator/);
    assert.equal(response.headers.get('x-frame-options'), 'DENY');
  });
}
test('missing contact details never publish a misleading completed policy', async () => {
  const response = onRequest({request: new Request('https://app.test/privacy')});
  assert.equal(response.status, 503);
  assert.doesNotMatch(await response.text(), /SUPPORT_EMAIL|APP_OPERATOR/);
});
test('operator text is escaped and HEAD has no response body', async () => {
  const response = onRequest({request: new Request('https://app.test/support'),
    env: {...env, APP_OPERATOR_NAME: '<script>alert(1)</script>'}});
  assert.doesNotMatch(await response.text(), /<script>/);
  const head = onRequest({request: new Request('https://app.test/privacy', {method: 'HEAD'}), env});
  assert.equal(head.status, 200);
  assert.equal(await head.text(), '');
});
