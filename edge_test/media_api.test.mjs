import assert from 'node:assert/strict';
import test, {afterEach} from 'node:test';

import {handleApiRequest} from '../functions/api/v1/[[path]].js';

const originalFetch = globalThis.fetch;
const userId = '11111111-1111-4111-8111-111111111111';
const otherUserId = '22222222-2222-4222-8222-222222222222';
const postId = '33333333-3333-4333-8333-333333333333';
const token = '44444444-4444-4444-8444-444444444444';
const oldAvatarKey = `avatars/${userId}/55555555-5555-4555-8555-555555555555.jpg`;
const postImageKey = `posts/${userId}/66666666-6666-4666-8666-666666666666.jpg`;
const jpeg = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0x01, 0x02, 0xff, 0xd9]);

afterEach(() => {
  globalThis.fetch = originalFetch;
});

class FakeR2Bucket {
  constructor() {
    this.objects = new Map();
    this.puts = [];
    this.gets = [];
    this.deletes = [];
  }

  seed(key, bytes, customMetadata = {}) {
    this.objects.set(key, {
      bytes: Uint8Array.from(bytes),
      customMetadata: {...customMetadata},
      httpMetadata: {contentType: 'image/jpeg'},
      httpEtag: '"seed-etag"',
    });
  }

  async put(key, body, options = {}) {
    const bytes = body instanceof Uint8Array
      ? Uint8Array.from(body)
      : body instanceof ArrayBuffer
        ? new Uint8Array(body.slice(0))
        : new Uint8Array(await new Response(body).arrayBuffer());
    this.puts.push({key, bytes, options});
    this.objects.set(key, {
      bytes,
      customMetadata: {...(options.customMetadata ?? {})},
      httpMetadata: {...(options.httpMetadata ?? {})},
      httpEtag: '"fake-etag"',
    });
  }

  async get(key) {
    this.gets.push(key);
    const stored = this.objects.get(key);
    if (!stored) return null;
    const bytes = Uint8Array.from(stored.bytes);
    return {
      body: new Response(bytes).body,
      size: bytes.byteLength,
      customMetadata: {...stored.customMetadata},
      httpEtag: stored.httpEtag,
    };
  }

  async delete(key) {
    this.deletes.push(key);
    this.objects.delete(key);
  }
}

function edgeEnv(bucket) {
  return {
    SUPABASE_URL: 'https://project.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test_key_long_enough',
    ...(bucket ? {USER_MEDIA: bucket} : {}),
  };
}

function mockSupabase(rpcHandler = async () => Response.json(null)) {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const call = {url: String(url), options};
    calls.push(call);
    if (call.url.endsWith('/auth/v1/user')) return Response.json({id: userId});
    return rpcHandler(call);
  };
  return calls;
}

function mediaRequest(path, {
  bytes = jpeg,
  contentLength = bytes.byteLength,
  contentType = 'image/jpeg',
} = {}) {
  const headers = {
    Authorization: 'Bearer user-token',
    'Content-Type': contentType,
  };
  if (contentLength !== null) headers['Content-Length'] = String(contentLength);
  return new Request(`https://gather2gether.pages.dev/api/v1/${path}`, {
    method: 'POST',
    headers,
    body: bytes,
  });
}

function createPostRequest(body) {
  return new Request('https://gather2gether.pages.dev/api/v1/forum/posts', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer user-token',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      title: 'Weekend photography walk',
      body: 'Meet for a relaxed photo walk around the neighbourhood.',
      category: 'Looking for group',
      ...body,
    }),
  });
}

test('forum JPEG upload stores a private staged object and returns an opaque token', async () => {
  const bucket = new FakeR2Bucket();
  mockSupabase();

  const response = await handleApiRequest(mediaRequest('forum/media'), edgeEnv(bucket));
  const payload = await response.json();

  assert.equal(response.status, 201);
  assert.match(payload.token, /^[0-9a-f-]{36}$/i);
  assert.equal(bucket.puts.length, 1);
  assert.equal(bucket.puts[0].key, `staging/forum/${userId}/current.jpg`);
  assert.deepEqual(bucket.puts[0].bytes, jpeg);
  assert.deepEqual(bucket.puts[0].options.customMetadata, {
    owner: userId,
    purpose: 'forum-staging',
    token: payload.token,
  });
  assert.equal(bucket.puts[0].options.httpMetadata.contentType, 'image/jpeg');
});

test('media upload rejects the wrong MIME type before writing to R2', async () => {
  const bucket = new FakeR2Bucket();
  const calls = mockSupabase();

  const response = await handleApiRequest(
    mediaRequest('forum/media', {contentType: 'image/png'}),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 415);
  assert.equal((await response.json()).error.code, 'jpeg_required');
  assert.equal(bucket.puts.length, 0);
  assert.equal(calls.length, 1);
});

test('media upload enforces the declared 5 MiB limit before reading the body', async () => {
  const bucket = new FakeR2Bucket();
  mockSupabase();

  const response = await handleApiRequest(
    mediaRequest('forum/media', {contentLength: 5 * 1024 * 1024 + 1}),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 413);
  assert.equal((await response.json()).error.code, 'media_too_large');
  assert.equal(bucket.puts.length, 0);
});

test('media upload validates actual length when Content-Length is understated', async () => {
  const bucket = new FakeR2Bucket();
  mockSupabase();

  const response = await handleApiRequest(
    mediaRequest('forum/media', {contentLength: 4}),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 413);
  assert.equal((await response.json()).error.code, 'media_too_large');
  assert.equal(bucket.puts.length, 0);
});

test('media upload checks JPEG start and end signatures rather than trusting MIME', async () => {
  const bucket = new FakeR2Bucket();
  mockSupabase();
  const fakeJpeg = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0xff, 0xd9]);

  const response = await handleApiRequest(
    mediaRequest('profile/avatar', {bytes: fakeJpeg}),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'invalid_media');
  assert.equal(bucket.puts.length, 0);
});

test('a new forum upload overwrites the one bounded staging object per user', async () => {
  const bucket = new FakeR2Bucket();
  mockSupabase();

  const first = await handleApiRequest(mediaRequest('forum/media'), edgeEnv(bucket));
  const firstToken = (await first.json()).token;
  const second = await handleApiRequest(mediaRequest('forum/media'), edgeEnv(bucket));
  const secondToken = (await second.json()).token;

  assert.notEqual(firstToken, secondToken);
  assert.equal(bucket.objects.size, 1);
  assert.equal(bucket.puts[0].key, `staging/forum/${userId}/current.jpg`);
  assert.equal(bucket.puts[1].key, bucket.puts[0].key);
  assert.equal(bucket.objects.get(bucket.puts[0].key).customMetadata.token, secondToken);
});

test('forum post creation moves an owned staged image and forwards place metadata', async () => {
  const bucket = new FakeR2Bucket();
  const stagingKey = `staging/forum/${userId}/current.jpg`;
  bucket.seed(stagingKey, jpeg, {owner: userId, purpose: 'forum-staging', token});
  const calls = mockSupabase(async (call) => {
    assert.match(call.url, /\/rpc\/create_forum_post$/);
    return Response.json(postId);
  });

  const response = await handleApiRequest(
    createPostRequest({
      image_token: token,
      place_name: 'Museum Island',
      place_address: 'Bodestrasse 1-3, 10178 Berlin',
    }),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 201);
  assert.equal((await response.json()).id, postId);
  const finalKey = [...bucket.objects.keys()].find((key) => key.startsWith(`posts/${userId}/`));
  assert.match(finalKey, /\.jpg$/);
  assert.equal(bucket.objects.has(stagingKey), true);
  assert.equal(bucket.objects.has(finalKey), true);
  const parameters = JSON.parse(calls[1].options.body);
  assert.deepEqual(parameters, {
    p_title: 'Weekend photography walk',
    p_body: 'Meet for a relaxed photo walk around the neighbourhood.',
    p_category: 'Looking for group',
    p_image_key: finalKey,
    p_place_name: 'Museum Island',
    p_place_address: 'Bodestrasse 1-3, 10178 Berlin',
  });
});

test('forum post creation rejects a staged image that is not owned by the caller', async () => {
  const bucket = new FakeR2Bucket();
  const stagingKey = `staging/forum/${userId}/current.jpg`;
  bucket.seed(stagingKey, jpeg, {
    owner: otherUserId,
    purpose: 'forum-staging',
    token,
  });
  const calls = mockSupabase(async () => {
    throw new Error('post RPC must not run');
  });

  const response = await handleApiRequest(
    createPostRequest({image_token: token}),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'invalid_image_token');
  assert.equal(calls.length, 1);
  assert.equal(bucket.puts.length, 0);
});

test('forum post creation rejects a stale token after the staging object is overwritten', async () => {
  const bucket = new FakeR2Bucket();
  const stagingKey = `staging/forum/${userId}/current.jpg`;
  bucket.seed(stagingKey, jpeg, {
    owner: userId,
    purpose: 'forum-staging',
    token: '77777777-7777-4777-8777-777777777777',
  });
  const calls = mockSupabase(async () => {
    throw new Error('post RPC must not run');
  });

  const response = await handleApiRequest(
    createPostRequest({image_token: token}),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'invalid_image_token');
  assert.equal(calls.length, 1);
  assert.equal(bucket.puts.length, 0);
});

test('forum post creation requires place name and address as a pair', async () => {
  const bucket = new FakeR2Bucket();
  const calls = mockSupabase(async () => {
    throw new Error('post RPC must not run');
  });

  const response = await handleApiRequest(
    createPostRequest({place_name: 'Museum Island'}),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'invalid_parameter');
  assert.equal(calls.length, 1);
  assert.equal(bucket.gets.length, 0);
});

test('definite database rejection deletes the newly finalized post object', async () => {
  const bucket = new FakeR2Bucket();
  const stagingKey = `staging/forum/${userId}/current.jpg`;
  bucket.seed(stagingKey, jpeg, {owner: userId, purpose: 'forum-staging', token});
  mockSupabase(async () => Response.json({message: 'forum_validation'}, {status: 400}));

  const response = await handleApiRequest(
    createPostRequest({image_token: token}),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'forum_validation');
  assert.equal([...bucket.objects.keys()].some((key) => key.startsWith('posts/')), false);
  assert.equal(bucket.deletes.some((key) => key.startsWith('posts/')), true);
});

test('commit-ambiguous database failure retains the finalized post object', async () => {
  const bucket = new FakeR2Bucket();
  const stagingKey = `staging/forum/${userId}/current.jpg`;
  bucket.seed(stagingKey, jpeg, {owner: userId, purpose: 'forum-staging', token});
  mockSupabase(async () => {
    throw new Error('network response was lost');
  });

  const response = await handleApiRequest(
    createPostRequest({image_token: token}),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 503);
  assert.equal((await response.json()).error.code, 'database_unavailable');
  const finalKeys = [...bucket.objects.keys()].filter((key) => key.startsWith('posts/'));
  assert.equal(finalKeys.length, 1);
  assert.equal(bucket.deletes.includes(finalKeys[0]), false);
  assert.equal(bucket.objects.has(stagingKey), true);
});

test('forum media is authorized by RPC and streamed without exposing its R2 key', async () => {
  const bucket = new FakeR2Bucket();
  bucket.seed(postImageKey, jpeg, {owner: userId, purpose: 'forum-post'});
  const calls = mockSupabase(async (call) => {
    assert.match(call.url, /\/rpc\/get_forum_post_image_key$/);
    return Response.json(postImageKey);
  });

  const response = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/forum/posts/${postId}/media`, {
      headers: {Authorization: 'Bearer user-token'},
    }),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), 'image/jpeg');
  assert.equal(response.headers.get('cache-control'), 'private, no-store');
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), jpeg);
  assert.deepEqual(JSON.parse(calls[1].options.body), {p_post_id: postId});
  assert.deepEqual(bucket.gets, [postImageKey]);
});

test('forum media permission denial never reads from R2', async () => {
  const bucket = new FakeR2Bucket();
  mockSupabase(async () => Response.json({message: 'permission_denied'}, {status: 400}));

  const response = await handleApiRequest(
    new Request(`https://gather2gether.pages.dev/api/v1/forum/posts/${postId}/media`, {
      headers: {Authorization: 'Bearer user-token'},
    }),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 403);
  assert.equal((await response.json()).error.code, 'permission_denied');
  assert.equal(bucket.gets.length, 0);
});

test('scope=mine on the collection uses the dedicated owner-only RPC', async () => {
  const calls = mockSupabase(async () => Response.json([{id: postId}]));

  const response = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/forum/posts?scope=mine', {
      headers: {Authorization: 'Bearer user-token'},
    }),
    edgeEnv(),
  );

  assert.equal(response.status, 200);
  assert.match(calls[1].url, /\/rpc\/list_own_forum_posts$/);
});

test('profile avatar upload swaps the database reference before removing the old object', async () => {
  const bucket = new FakeR2Bucket();
  bucket.seed(oldAvatarKey, jpeg, {owner: userId, purpose: 'profile-avatar'});
  const calls = mockSupabase(async (call) => {
    assert.match(call.url, /\/rpc\/set_profile_avatar$/);
    return Response.json(oldAvatarKey);
  });

  const response = await handleApiRequest(
    mediaRequest('profile/avatar'),
    edgeEnv(bucket),
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {updated: true});
  const parameters = JSON.parse(calls[1].options.body);
  assert.match(parameters.p_image_key, new RegExp(`^avatars/${userId}/.+\\.jpg$`));
  assert.equal(bucket.objects.has(parameters.p_image_key), true);
  assert.equal(bucket.objects.has(oldAvatarKey), false);
});

test('profile avatar GET and DELETE use owner-only reference RPCs', async () => {
  const bucket = new FakeR2Bucket();
  bucket.seed(oldAvatarKey, jpeg, {owner: userId, purpose: 'profile-avatar'});
  const calls = mockSupabase(async (call) => {
    if (call.url.endsWith('/rpc/get_own_profile_avatar_image_key')) {
      return Response.json(oldAvatarKey);
    }
    if (call.url.endsWith('/rpc/set_profile_avatar')) {
      return Response.json(oldAvatarKey);
    }
    throw new Error(`Unexpected RPC: ${call.url}`);
  });

  const getResponse = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/profile/avatar', {
      headers: {Authorization: 'Bearer user-token'},
    }),
    edgeEnv(bucket),
  );
  assert.equal(getResponse.status, 200);
  assert.deepEqual(new Uint8Array(await getResponse.arrayBuffer()), jpeg);

  const deleteResponse = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/profile/avatar', {
      method: 'DELETE',
      headers: {Authorization: 'Bearer user-token'},
    }),
    edgeEnv(bucket),
  );
  assert.equal(deleteResponse.status, 200);
  assert.deepEqual(await deleteResponse.json(), {deleted: true});
  assert.equal(bucket.objects.has(oldAvatarKey), false);
  const deleteRpc = calls.find((call) => call.url.endsWith('/rpc/set_profile_avatar'));
  assert.deepEqual(JSON.parse(deleteRpc.options.body), {p_image_key: null});
});

test('only media routes require the R2 binding', async () => {
  const calls = mockSupabase(async (call) => {
    if (call.url.endsWith('/rpc/recommend_personalized_forum_posts')) {
      return Response.json([]);
    }
    if (call.url.endsWith('/rpc/list_forum_posts')) {
      return Response.json([]);
    }
    if (call.url.endsWith('/rpc/get_recommendation_preferences')) {
      return Response.json([{enabled: true, hidden_categories: [], hidden_count: 0}]);
    }
    if (call.url.endsWith('/rpc/list_hidden_recommendation_ids')) {
      return Response.json([]);
    }
    throw new Error(`Unexpected RPC: ${call.url}`);
  });

  const listResponse = await handleApiRequest(
    new Request('https://gather2gether.pages.dev/api/v1/forum/posts', {
      headers: {Authorization: 'Bearer user-token'},
    }),
    edgeEnv(),
  );
  assert.equal(listResponse.status, 200);

  const mediaResponse = await handleApiRequest(
    mediaRequest('forum/media'),
    edgeEnv(),
  );
  assert.equal(mediaResponse.status, 503);
  assert.equal((await mediaResponse.json()).error.code, 'media_not_configured');
  assert.equal(calls.filter((call) => call.url.endsWith('/auth/v1/user')).length, 2);
});
