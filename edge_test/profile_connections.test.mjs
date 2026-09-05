import assert from 'node:assert/strict';
import test, {afterEach} from 'node:test';
import {handleApiRequest} from '../functions/api/v1/[[path]].js';

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });
const owner = '11111111-1111-4111-8111-111111111111';
const visitor = '22222222-2222-4222-8222-222222222222';
const env = {SUPABASE_URL: 'https://project.supabase.co', SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test_key_long_enough'};
function mock(viewer, rows = []) {
  const calls = [];
  globalThis.fetch = async (url, options) => {
    if (String(url).endsWith('/auth/v1/user')) return Response.json({id: viewer});
    assert.ok(String(url).endsWith('/rpc/list_profile_connections'));
    calls.push(JSON.parse(options.body));
    return Response.json(rows);
  };
  return calls;
}
function request(path) {
  return handleApiRequest(new Request(`https://gather2gether.pages.dev/api/v1/${path}`, {headers: {Authorization: 'Bearer test-token'}}), env);
}

for (const kind of ['followers', 'following']) {
  test(`${kind}: owner may search using a username or display name`, async () => {
    const calls = mock(owner);
    for (const query of ['@tokki', 'Maya Chen']) {
      const response = await request(`profiles/me/${kind}?query=${encodeURIComponent(query)}`);
      assert.equal(response.status, 200);
      assert.equal((await response.json()).can_search, true);
      assert.equal(calls.at(-1).p_profile_id, owner);
      assert.equal(calls.at(-1).p_kind, kind);
      assert.equal(calls.at(-1).p_query, query);
    }
  });

  test(`${kind}: visitors can browse but cannot submit a search`, async () => {
    const calls = mock(visitor);
    const browse = await request(`profiles/${owner}/${kind}`);
    assert.equal(browse.status, 200);
    assert.equal((await browse.json()).can_search, false);
    const search = await request(`profiles/${owner}/${kind}?query=tokki`);
    assert.equal(search.status, 403);
    assert.equal((await search.json()).error.code, 'connection_search_owner_only');
    assert.equal(calls.length, 1);
  });
}

test('pagination keeps database microseconds and fetches one lookahead row', async () => {
  const rows = Array.from({length: 31}, (_, i) => ({
    id: `33333333-3333-4333-8333-${String(i).padStart(12, '0')}`,
    display_name: `Member ${i}`, username: `member_${i}`,
    followed_at: '2026-09-05T14:00:00.123456+00:00',
  }));
  const calls = mock(visitor, rows);
  const response = await request(`profiles/${owner}/followers`);
  const payload = await response.json();
  assert.equal(payload.data.length, 30);
  const cursor = JSON.parse(payload.next_cursor);
  assert.equal(cursor.id, rows[29].id);
  assert.equal(cursor.created_at, rows[29].followed_at);
  await request(`profiles/${owner}/followers?cursor=${encodeURIComponent(payload.next_cursor)}`);
  assert.equal(calls[1].p_before_created_at, rows[29].followed_at);
  assert.equal(calls[1].p_before_id, rows[29].id);
  assert.equal(calls[1].p_limit, 31);
});

test('invalid cursors and oversized searches do not reach the database', async () => {
  const calls = mock(owner);
  for (const suffix of ['cursor=garbage', 'cursor=null', `query=${'x'.repeat(81)}`]) {
    assert.equal((await request(`profiles/me/followers?${suffix}`)).status, 400);
  }
  assert.equal(calls.length, 0);
});

test('database owner checks remain a forbidden response', async () => {
  globalThis.fetch = async (url) => String(url).endsWith('/auth/v1/user')
    ? Response.json({id: owner})
    : Response.json({code: '42501', message: 'connection_search_owner_only'}, {status: 403});
  const response = await request('profiles/me/followers?query=tokki');
  assert.equal(response.status, 403);
});
