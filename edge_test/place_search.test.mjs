import assert from 'node:assert/strict';
import {afterEach, test} from 'node:test';
import {handleApiRequest} from '../functions/api/v1/[[path]].js';

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });
const env = {
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'test-publishable-key-long-enough',
  GEOAPIFY_API_KEY: 'test-geoapify-key-long-enough',
};
const hall = {
  place_id: 'university-hall',
  name: 'Sporthalle der Universität',
  formatted: 'Sporthalle der Universität, Theodor-Heuss-Anlage 15, 68165 Mannheim, Deutschland',
  address_line1: 'Sporthalle der Universität',
  address_line2: 'Theodor-Heuss-Anlage 15, 68165 Mannheim, Deutschland',
  city: 'Mannheim',
  lat: 49.4785265,
  lon: 8.4992394,
  result_type: 'amenity',
  rank: {confidence: 0.9},
};
const unrelated = {
  place_id: 'unrelated-hall',
  name: 'Lilli-Gräber-Halle',
  formatted: 'Lilli-Gräber-Halle, Saarburger Ring 49, Mannheim, Deutschland',
  city: 'Mannheim', lat: 49.4415873, lon: 8.5704001,
  result_type: 'amenity', rank: {confidence: 0},
};

function provider(autocomplete, forward) {
  const calls = [];
  globalThis.fetch = async (input, options) => {
    const url = new URL(input);
    if (url.pathname === '/auth/v1/user') {
      return Response.json({id: '11111111-1111-4111-8111-111111111111'});
    }
    assert.equal(url.hostname, 'api.geoapify.com');
    calls.push({url, options});
    if (url.pathname.endsWith('/autocomplete')) return Response.json({results: autocomplete});
    assert.equal(url.pathname, '/v1/geocode/search');
    return forward instanceof Response ? forward : Response.json({results: forward});
  };
  return calls;
}

async function search(text = 'Mannheim UniSport Halle') {
  const url = new URL('https://gather2gether.pages.dev/api/v1/places/autocomplete');
  url.search = new URLSearchParams({text, latitude: '37.77', longitude: '-122.42', language: 'en'});
  const response = await handleApiRequest(new Request(url, {
    headers: {Authorization: 'Bearer test-user'},
  }), env);
  assert.equal(response.status, 200);
  return response.json();
}

test('a campus hall alias resolves its actual venue and address within the typed city', async () => {
  const wrongCity = {...hall, place_id: 'wrong-city', city: 'Bonn',
    name: 'Uni-Sporthalle', formatted: 'Uni-Sporthalle, Bonn, Deutschland', rank: {confidence: 1}};
  const calls = provider([unrelated], [wrongCity, hall]);
  const result = await search();
  assert.deepEqual(result.data.map((place) => place.id), ['university-hall']);
  assert.equal(result.data[0].latitude, 49.4785265);
  assert.equal(result.data[0].longitude, 8.4992394);
  assert.match(result.data[0].formatted_address, /Theodor-Heuss-Anlage 15/);
  assert.equal(calls.length, 2);
  const query = calls[1].url.searchParams;
  assert.equal(query.get('name'), 'Sporthalle Universität');
  assert.equal(query.get('city'), 'Mannheim');
  assert.equal(query.has('text'), false);
  assert.equal(query.get('type'), 'amenity');
  assert.equal(query.has('filter'), false);
  assert.equal(query.get('lang'), 'en');
  assert.equal(calls[0].options.signal, calls[1].options.signal);
  assert.equal(JSON.stringify(result).includes(env.GEOAPIFY_API_KEY), false);
});

test('fallback also works with no initial suggestions and preserves a zero-confidence exact name', async () => {
  const calls = provider([], [{...hall, rank: {confidence: 0}}]);
  const result = await search();
  assert.equal(result.data[0].id, hall.place_id);
  assert.equal(calls[1].url.searchParams.get('text'), 'Mannheim Sporthalle Universität');
  assert.equal(calls[1].url.searchParams.has('name'), false);
});

test('a strong name match uses only autocomplete', async () => {
  const calls = provider([hall], []);
  const result = await search('Sporthalle der Universität Mannheim');
  assert.equal(result.data.length, 1);
  assert.equal(calls.length, 1);
});

test('unrelated halls and city centroids are not presented as the requested venue', async () => {
  provider([unrelated], [{...unrelated, name: 'Mannheim', formatted: 'Mannheim, Deutschland',
    result_type: 'city', rank: {confidence: 1}}]);
  assert.deepEqual((await search()).data, []);
});

test('fallback failures retain useful primary suggestions', async () => {
  provider([hall], new Response(null, {status: 429}));
  const result = await search('Mannheim UniSport Halle entrance');
  assert.equal(result.data.length, 1);
  assert.equal(result.data[0].id, hall.place_id);
});

test('duplicate places from different provider indexes appear once', async () => {
  provider([hall], [{...hall, place_id: 'duplicate-index-id'}]);
  assert.equal((await search('Mannheim UniSport Halle entrance')).data.length, 1);
});
