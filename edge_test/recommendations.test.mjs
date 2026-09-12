import assert from 'node:assert/strict';
import test, {afterEach} from 'node:test';
import {handleApiRequest} from '../functions/api/v1/[[path]].js';

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });
const ids = [1, 2, 3].map(n => `a0000000-0000-4000-8000-00000000000${n}`);
const env = {
  SUPABASE_URL: 'https://project.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test_key_long_enough',
};

function mockFeed({eligible = false, enabled = true, scores, hidden = []} = {}) {
  const calls = [];
  let modelCalls = 0;
  globalThis.fetch = async (url, options = {}) => {
    const rpc = String(url).split('/').at(-1);
    const body = options.body ? JSON.parse(options.body) : null;
    calls.push({rpc, body});
    if (rpc === 'user') return Response.json({id: ids[2]});
    if (rpc === 'get_recommendation_preferences') {
      return Response.json([{enabled, hidden_categories: [], hidden_count: hidden.length}]);
    }
    if (rpc === 'list_hidden_recommendation_ids') return Response.json(hidden);
    if (rpc === 'discover_event_plans') return Response.json(ids.map((id, index) => ({
      id, title: ['Camera walk', 'Coffee meetup', 'Running group'][index],
      category: ['Photography', 'Coffee', 'Running'][index],
      description: 'A nearby event.',
      recommendation_reason: index === 0 ? 'Matches your interest in Photography' : 'Upcoming near you',
    })));
    if (rpc === 'get_ai_recommendation_state') return Response.json({
      eligible, cache_key: 'abcdef0123456789abcdef0123456789',
      preference_query: eligible ? 'Action: saved | Category: Photography | Camera walk' : null,
      ranked_ids: null,
    });
    if (rpc === 'claim_ai_recommendation_rerank') return Response.json(true);
    throw new Error(`Unexpected RPC: ${rpc}`);
  };
  return {
    calls,
    modelCalls: () => modelCalls,
    model: {fetch: async () => {
      modelCalls += 1;
      return Response.json({ranking: ids.map((id, i) => ({id, score: scores[i]}))});
    }},
  };
}

async function feed(model, extra = '') {
  const response = await handleApiRequest(new Request(
    `https://gather2gether.pages.dev/api/v1/events/nearby?planning=1&latitude=52.52&longitude=13.405&radius_km=10${extra}`,
    {headers: {Authorization: 'Bearer test-token'}},
  ), {...env, ASSISTANT_MODEL: model});
  assert.equal(response.status, 200);
  return (await response.json()).data;
}

test('first-visit mobile discovery uses interest ranking and preserves its factual reason without AI', async () => {
  const mock = mockFeed();
  const data = await feed(mock.model);
  assert.deepEqual(data.map(row => row.id), ids);
  assert.equal(data[0].recommendation_reason, 'Matches your interest in Photography');
  assert.equal(mock.modelCalls(), 0);
  assert.equal(mock.calls.some(call => call.rpc === 'discover_event_plans'), true);
});

test('date and accessibility filters use the same first-visit recommendation path', async () => {
  const mock = mockFeed();
  await feed(mock.model, '&start_from=2099-01-01T00%3A00%3A00Z&wheelchair_accessible_only=true');
  const {body} = mock.calls.find(call => call.rpc === 'discover_event_plans');
  assert.equal(body.p_filters.start_from, '2099-01-01T00:00:00.000Z');
  assert.equal(body.p_filters.wheelchair_accessible_only, true);
  assert.equal(mock.modelCalls(), 0);
});

test('nearly tied AI scores preserve the interest-based ordering', async () => {
  const mock = mockFeed({eligible: true, scores: [0.5, 0.501, 0.502]});
  assert.deepEqual((await feed(mock.model)).map(row => row.id), ids);
  assert.equal(mock.modelCalls(), 1);
});

test('one deliberate choice can invoke AI while the base ranking retains majority influence', async () => {
  const mock = mockFeed({eligible: true, scores: [0, 0, 1]});
  const data = await feed(mock.model);
  assert.equal(mock.modelCalls(), 1);
  // The last candidate has maximum model relevance but cannot displace the
  // strongest first-visit match solely on that one signal.
  assert.equal(data[0].id, ids[0]);
});

test('opt-out skips model state and does not show a personalization explanation', async () => {
  const mock = mockFeed({enabled: false});
  const data = await feed(mock.model);
  assert.equal(data[0].recommendation_reason, 'Near your chosen area');
  assert.equal(mock.calls.some(call => call.rpc === 'get_ai_recommendation_state'), false);
});

test('dismissed content is removed before model eligibility is checked', async () => {
  const mock = mockFeed({hidden: [ids[0]]});
  const data = await feed(mock.model);
  assert.deepEqual(data.map(row => row.id), ids.slice(1));
  assert.deepEqual(mock.calls.find(call => call.rpc === 'get_ai_recommendation_state').body.p_candidate_ids, ids.slice(1));
});
