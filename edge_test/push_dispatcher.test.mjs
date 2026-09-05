import assert from 'node:assert/strict';
import test, {afterEach} from 'node:test';

import {deliverPushBatch} from '../workers/push-dispatcher.js';

const originalFetch = globalThis.fetch;
const env = {
  SUPABASE_URL: 'https://project.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'service-role-key-that-is-long-enough-for-validation',
  FIREBASE_PROJECT_ID: 'gather2gether-test',
  FIREBASE_SERVICE_ACCOUNT_EMAIL:
    'push@gather2gether-test.iam.gserviceaccount.com',
  FIREBASE_PRIVATE_KEY: '-----BEGIN PRIVATE KEY-----\nunused\n-----END PRIVATE KEY-----',
};
const eventId = '22222222-2222-4222-8222-222222222222';
const delivery = {
  delivery_id: 42,
  device_token: 'fcm-device-token-with-enough-entropy',
  device_platform: 'android',
  title: 'You have a place',
  body: 'A place opened and you are now going.',
  event_id: eventId,
  attempt: 1,
};

afterEach(() => {
  globalThis.fetch = originalFetch;
});

test('dispatcher sends a claimed notification and acknowledges it', async () => {
  const rpcCalls = [];
  let firebaseBody;
  globalThis.fetch = async (url, options = {}) => {
    assert.match(String(url), /fcm\.googleapis\.com\/v1\/projects\/gather2gether-test/);
    firebaseBody = JSON.parse(options.body);
    return Response.json({name: 'projects/test/messages/1'});
  };
  const rpc = async (name, parameters) => {
    rpcCalls.push({name, parameters});
    if (name === 'claim_push_delivery_batch') return [delivery];
    return true;
  };

  const result = await deliverPushBatch(env, {
    rpc,
    getAccessToken: async () => 'google-access-token-that-is-long-enough',
  });

  assert.deepEqual(result, {claimed: 1, delivered: 1});
  assert.deepEqual(rpcCalls, [
    {name: 'enqueue_due_push_reminders', parameters: {}},
    {name: 'claim_push_delivery_batch', parameters: {p_limit: 50}},
    {name: 'complete_push_delivery', parameters: {p_delivery_id: 42}},
  ]);
  assert.equal(firebaseBody.message.token, delivery.device_token);
  assert.deepEqual(firebaseBody.message.data, {
    delivery_id: '42',
    event_id: eventId,
  });
  assert.equal(firebaseBody.message.android.collapse_key, 'notification-42');
});

test('dispatcher disables an FCM token reported as unregistered', async () => {
  const rpcCalls = [];
  globalThis.fetch = async () => Response.json(
    {
      error: {
        details: [{errorCode: 'UNREGISTERED'}],
      },
    },
    {status: 404},
  );
  const rpc = async (name, parameters) => {
    rpcCalls.push({name, parameters});
    if (name === 'claim_push_delivery_batch') return [delivery];
    return true;
  };

  const result = await deliverPushBatch(env, {
    rpc,
    getAccessToken: async () => 'google-access-token-that-is-long-enough',
  });

  assert.deepEqual(result, {claimed: 1, delivered: 0});
  assert.deepEqual(rpcCalls[2], {
    name: 'fail_push_delivery',
    parameters: {
      p_delivery_id: 42,
      p_error: 'firebase_unregistered',
      p_retryable: false,
      p_disable_device: true,
    },
  });
});

test('dispatcher releases claimed work when Firebase authentication is down', async () => {
  const rpcCalls = [];
  const rpc = async (name, parameters) => {
    rpcCalls.push({name, parameters});
    if (name === 'claim_push_delivery_batch') return [delivery];
    return true;
  };

  const result = await deliverPushBatch(env, {
    rpc,
    getAccessToken: async () => {
      throw new Error('provider unavailable');
    },
  });

  assert.deepEqual(result, {claimed: 1, delivered: 0});
  assert.deepEqual(rpcCalls[2], {
    name: 'fail_push_delivery',
    parameters: {
      p_delivery_id: 42,
      p_error: 'firebase_authentication_unavailable',
      p_retryable: true,
      p_disable_device: false,
    },
  });
});
