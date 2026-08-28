const MAX_BODY_BYTES = 32 * 1024;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REPORT_REASONS = new Set([
  'spam',
  'unsafe_behaviour',
  'inappropriate_content',
  'misleading',
  'other',
]);
const FORUM_REPORT_REASONS = new Set([
  'spam',
  'harassment',
  'unsafe_behaviour',
  'personal_information',
  'inappropriate_content',
  'other',
]);
const FORUM_CATEGORIES = new Set([
  'General',
  'Looking for group',
  'Local tips',
  'Event ideas',
  'Safety',
]);
const RSVP_STATUSES = new Set(['joined', 'tentative', 'cancelled']);

class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export async function onRequest(context) {
  return handleApiRequest(context.request, context.env);
}

export async function handleApiRequest(request, env) {
  const requestId = crypto.randomUUID();
  const cors = {};

  try {
    if (request.headers.get('Origin')) {
      throw new ApiError(403, 'browser_not_supported', 'Browser access is not supported.');
    }
    if (request.method === 'OPTIONS') {
      throw new ApiError(405, 'method_not_allowed', 'Method is not allowed.');
    }

    const url = new URL(request.url);
    const segments = routeSegments(url.pathname);

    if (request.method === 'GET' && segments.length === 1 && segments[0] === 'health') {
      return jsonResponse(
        {status: 'ok', service: 'gather2gether-edge-api', version: 1},
        200,
        requestId,
        cors,
      );
    }

    assertEnvironment(env);
    const identity = await authenticate(request, env);

    if (request.method === 'GET' && segments.join('/') === 'forum/posts') {
      const posts = await supabaseRpc(
        env,
        identity.authorization,
        'list_forum_posts',
        {p_limit: 30, p_before: null},
      );
      if (!Array.isArray(posts)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid forum data.');
      }
      return jsonResponse({data: posts}, 200, requestId, cors);
    }

    if (request.method === 'POST' && segments.join('/') === 'forum/posts') {
      const input = validateCreateForumPost(await jsonBody(request));
      const postId = await supabaseRpc(
        env,
        identity.authorization,
        'create_forum_post',
        input,
      );
      if (typeof postId !== 'string' || !UUID_PATTERN.test(postId)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid post identifier.');
      }
      return jsonResponse({id: postId}, 201, requestId, cors);
    }

    if (segments.length >= 3 && segments[0] === 'forum' && segments[1] === 'posts') {
      const postId = uuidParameter(segments[2], 'post_id');

      if (request.method === 'GET' && segments.length === 3) {
        const rows = await supabaseRpc(
          env,
          identity.authorization,
          'get_forum_post',
          {p_post_id: postId},
        );
        if (!Array.isArray(rows) || rows.length === 0) {
          throw new ApiError(404, 'forum_post_not_found', 'Discussion was not found.');
        }
        return jsonResponse({data: rows[0]}, 200, requestId, cors);
      }

      if (request.method === 'GET' && segments.length === 4 && segments[3] === 'comments') {
        const comments = await supabaseRpc(
          env,
          identity.authorization,
          'get_forum_comments',
          {p_post_id: postId, p_limit: 100},
        );
        if (!Array.isArray(comments)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid comment data.');
        }
        return jsonResponse({data: comments}, 200, requestId, cors);
      }

      if (request.method === 'POST' && segments.length === 4 && segments[3] === 'comments') {
        const body = await jsonBody(request);
        exactKeys(body, ['body']);
        const commentBody = stringParameter(body.body, 'body', 1, 1200);
        const commentId = await supabaseRpc(
          env,
          identity.authorization,
          'create_forum_comment',
          {p_post_id: postId, p_body: commentBody},
        );
        if (typeof commentId !== 'string' || !UUID_PATTERN.test(commentId)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid comment identifier.');
        }
        return jsonResponse({id: commentId}, 201, requestId, cors);
      }

      if (request.method === 'POST' && segments.length === 4 && segments[3] === 'report') {
        const reason = validateForumReport(await jsonBody(request));
        await supabaseRpc(
          env,
          identity.authorization,
          'report_forum_post',
          {p_post_id: postId, p_reason: reason},
        );
        return jsonResponse({submitted: true}, 201, requestId, cors);
      }
    }

    if (
      request.method === 'POST' &&
      segments.length === 4 &&
      segments[0] === 'forum' &&
      segments[1] === 'comments' &&
      segments[3] === 'report'
    ) {
      const commentId = uuidParameter(segments[2], 'comment_id');
      const reason = validateForumReport(await jsonBody(request));
      await supabaseRpc(
        env,
        identity.authorization,
        'report_forum_comment',
        {p_comment_id: commentId, p_reason: reason},
      );
      return jsonResponse({submitted: true}, 201, requestId, cors);
    }

    if (request.method === 'GET' && segments.join('/') === 'events/nearby') {
      const latitude = numberParameter(url.searchParams.get('latitude'), 'latitude', -90, 90);
      const longitude = numberParameter(url.searchParams.get('longitude'), 'longitude', -180, 180);
      const radiusKm = numberParameter(url.searchParams.get('radius_km'), 'radius_km', 1, 100);
      const events = await supabaseRpc(
        env,
        identity.authorization,
        'nearby_events',
        {
          p_latitude: latitude,
          p_longitude: longitude,
          p_radius_km: radiusKm,
        },
      );
      return jsonResponse({data: events}, 200, requestId, cors);
    }

    if (request.method === 'POST' && segments.join('/') === 'events') {
      const input = validateCreateEvent(await jsonBody(request));
      const eventId = await supabaseRpc(
        env,
        identity.authorization,
        'create_event',
        input,
      );
      if (typeof eventId !== 'string' || !UUID_PATTERN.test(eventId)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid event identifier.');
      }
      return jsonResponse({id: eventId}, 201, requestId, cors);
    }

    if (segments.length >= 2 && segments[0] === 'events') {
      const eventId = uuidParameter(segments[1], 'event_id');

      if (request.method === 'GET' && segments.length === 2) {
        const rows = await supabaseRpc(
          env,
          identity.authorization,
          'get_event_details',
          {p_event_id: eventId},
        );
        if (!Array.isArray(rows) || rows.length === 0) {
          throw new ApiError(404, 'event_not_found', 'Event was not found.');
        }
        return jsonResponse({data: rows[0]}, 200, requestId, cors);
      }

      if (request.method === 'PUT' && segments.length === 3 && segments[2] === 'rsvp') {
        const body = await jsonBody(request);
        exactKeys(body, ['status']);
        if (typeof body.status !== 'string' || !RSVP_STATUSES.has(body.status)) {
          throw new ApiError(400, 'invalid_rsvp_status', 'RSVP status is invalid.');
        }
        const status = await supabaseRpc(
          env,
          identity.authorization,
          'set_event_rsvp',
          {p_event_id: eventId, p_status: body.status},
        );
        return jsonResponse({status}, 200, requestId, cors);
      }

      if (request.method === 'POST' && segments.length === 3 && segments[2] === 'report') {
        const body = await jsonBody(request);
        exactKeys(body, ['reason']);
        if (typeof body.reason !== 'string' || !REPORT_REASONS.has(body.reason)) {
          throw new ApiError(400, 'invalid_report_reason', 'Report reason is invalid.');
        }
        await insertReport(env, identity, eventId, body.reason);
        return jsonResponse({submitted: true}, 201, requestId, cors);
      }
    }

    throw new ApiError(404, 'route_not_found', 'API route was not found.');
  } catch (error) {
    const apiError = error instanceof ApiError
      ? error
      : new ApiError(500, 'internal_error', 'The edge API could not process the request.');
    return jsonResponse(
      {error: {code: apiError.code, message: apiError.message}},
      apiError.status,
      requestId,
      cors,
    );
  }
}

function routeSegments(pathname) {
  const prefix = '/api/v1/';
  if (!pathname.startsWith(prefix)) {
    throw new ApiError(404, 'route_not_found', 'API route was not found.');
  }
  return pathname.slice(prefix.length).split('/').filter(Boolean);
}

function assertEnvironment(env) {
  let url;
  try {
    url = new URL(env.SUPABASE_URL);
  } catch (_) {
    throw new ApiError(503, 'edge_not_configured', 'The edge API is not configured.');
  }
  if (url.protocol !== 'https:' || !url.hostname.endsWith('.supabase.co')) {
    throw new ApiError(503, 'edge_not_configured', 'The edge API is not configured.');
  }
  if (typeof env.SUPABASE_PUBLISHABLE_KEY !== 'string' || env.SUPABASE_PUBLISHABLE_KEY.length < 20) {
    throw new ApiError(503, 'edge_not_configured', 'The edge API is not configured.');
  }
}

async function authenticate(request, env) {
  const authorization = request.headers.get('Authorization') ?? '';
  if (!/^Bearer\s+\S+$/.test(authorization)) {
    throw new ApiError(401, 'authentication_required', 'Sign in is required.');
  }

  let response;
  try {
    response = await fetch(`${trimSlash(env.SUPABASE_URL)}/auth/v1/user`, {
      headers: {
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        Authorization: authorization,
      },
    });
  } catch (_) {
    throw new ApiError(503, 'authentication_unavailable', 'Authentication is temporarily unavailable.');
  }

  if (!response.ok) {
    throw new ApiError(401, 'invalid_session', 'Your session is invalid or expired.');
  }
  const user = await response.json();
  if (!user || typeof user.id !== 'string' || !UUID_PATTERN.test(user.id)) {
    throw new ApiError(401, 'invalid_session', 'Your session is invalid or expired.');
  }
  return {authorization, userId: user.id};
}

async function supabaseRpc(env, authorization, functionName, parameters) {
  let response;
  try {
    response = await fetch(
      `${trimSlash(env.SUPABASE_URL)}/rest/v1/rpc/${functionName}`,
      {
        method: 'POST',
        headers: supabaseHeaders(env, authorization),
        body: JSON.stringify(parameters),
      },
    );
  } catch (_) {
    throw new ApiError(503, 'database_unavailable', 'The database is temporarily unavailable.');
  }
  return parseSupabaseResponse(response);
}

async function insertReport(env, identity, eventId, reason) {
  let response;
  try {
    response = await fetch(`${trimSlash(env.SUPABASE_URL)}/rest/v1/reports`, {
      method: 'POST',
      headers: {
        ...supabaseHeaders(env, identity.authorization),
        Prefer: 'return=minimal',
      },
      body: JSON.stringify({
        reporter_id: identity.userId,
        event_id: eventId,
        reason,
      }),
    });
  } catch (_) {
    throw new ApiError(503, 'database_unavailable', 'The database is temporarily unavailable.');
  }
  await parseSupabaseResponse(response);
}

async function parseSupabaseResponse(response) {
  const text = await response.text();
  let payload = null;
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch (_) {
      if (response.ok) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid response.');
      }
    }
  }
  if (!response.ok) throw mappedSupabaseError(response.status, payload);
  return payload;
}

function mappedSupabaseError(status, payload) {
  const backendMessage = typeof payload?.message === 'string' ? payload.message : '';
  const known = {
    authentication_required: [401, 'authentication_required', 'Sign in is required.'],
    event_validation: [400, 'event_validation', 'Event details are invalid.'],
    invalid_rsvp_status: [400, 'invalid_rsvp_status', 'RSVP status is invalid.'],
    event_unavailable: [409, 'event_unavailable', 'This event is unavailable.'],
    event_started: [409, 'event_started', 'This event has already started.'],
    event_full: [409, 'event_full', 'This event is full.'],
    forum_validation: [400, 'forum_validation', 'Discussion content is invalid.'],
    forum_rate_limited: [429, 'forum_rate_limited', 'You are posting too quickly. Please wait and try again.'],
    forum_post_unavailable: [404, 'forum_post_not_found', 'Discussion was not found.'],
    forum_comment_unavailable: [404, 'forum_comment_not_found', 'Comment was not found.'],
    forum_post_locked: [409, 'forum_post_locked', 'This discussion is locked.'],
    invalid_report_reason: [400, 'invalid_report_reason', 'Report reason is invalid.'],
    cannot_report_own_content: [400, 'cannot_report_own_content', 'You cannot report your own content.'],
    permission_denied: [403, 'permission_denied', 'You do not have permission for this action.'],
  };
  const match = known[backendMessage];
  if (match) return new ApiError(...match);
  if (status === 401) return new ApiError(401, 'invalid_session', 'Your session is invalid or expired.');
  if (status === 403) return new ApiError(403, 'permission_denied', 'You do not have permission for this action.');
  return new ApiError(502, 'database_rejected_request', 'The database rejected the request.');
}

async function jsonBody(request) {
  const contentLength = Number(request.headers.get('Content-Length') ?? 0);
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    throw new ApiError(413, 'request_too_large', 'Request body is too large.');
  }
  if (!(request.headers.get('Content-Type') ?? '').toLowerCase().includes('application/json')) {
    throw new ApiError(415, 'json_required', 'Content-Type must be application/json.');
  }
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) {
    throw new ApiError(413, 'request_too_large', 'Request body is too large.');
  }
  try {
    const body = JSON.parse(text);
    if (!body || Array.isArray(body) || typeof body !== 'object') throw new Error();
    return body;
  } catch (_) {
    throw new ApiError(400, 'invalid_json', 'Request body must be a JSON object.');
  }
}

function validateCreateEvent(body) {
  const fields = [
    'title',
    'description',
    'category',
    'venue_name',
    'address',
    'latitude',
    'longitude',
    'start_at',
    'end_at',
    'max_participants',
  ];
  exactKeys(body, fields);

  const title = stringParameter(body.title, 'title', 3, 120);
  const description = stringParameter(body.description, 'description', 1, 2000);
  const category = stringParameter(body.category, 'category', 2, 60);
  const venueName = stringParameter(body.venue_name, 'venue_name', 2, 160);
  const address = stringParameter(body.address, 'address', 3, 300);
  const latitude = numberParameter(body.latitude, 'latitude', -90, 90);
  const longitude = numberParameter(body.longitude, 'longitude', -180, 180);
  const maxParticipants = integerParameter(body.max_participants, 'max_participants', 2, 500);
  const startAt = dateParameter(body.start_at, 'start_at');
  const endAt = dateParameter(body.end_at, 'end_at');
  if (startAt.getTime() <= Date.now() || endAt.getTime() <= startAt.getTime()) {
    throw new ApiError(400, 'event_validation', 'Event times are invalid.');
  }

  return {
    p_title: title,
    p_description: description,
    p_category: category,
    p_venue_name: venueName,
    p_address: address,
    p_latitude: latitude,
    p_longitude: longitude,
    p_start_at: startAt.toISOString(),
    p_end_at: endAt.toISOString(),
    p_max_participants: maxParticipants,
  };
}

function validateCreateForumPost(body) {
  exactKeys(body, ['title', 'body', 'category']);
  const title = stringParameter(body.title, 'title', 5, 120);
  const postBody = stringParameter(body.body, 'body', 10, 4000);
  const category = stringParameter(body.category, 'category', 1, 40);
  if (!FORUM_CATEGORIES.has(category)) {
    throw new ApiError(400, 'forum_validation', 'Discussion category is invalid.');
  }
  return {p_title: title, p_body: postBody, p_category: category};
}

function validateForumReport(body) {
  exactKeys(body, ['reason']);
  if (typeof body.reason !== 'string' || !FORUM_REPORT_REASONS.has(body.reason)) {
    throw new ApiError(400, 'invalid_report_reason', 'Report reason is invalid.');
  }
  return body.reason;
}

function exactKeys(value, expected) {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
    throw new ApiError(400, 'unexpected_fields', 'Request contains missing or unexpected fields.');
  }
}

function stringParameter(value, name, minimum, maximum) {
  if (typeof value !== 'string') {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  const trimmed = value.trim();
  if (trimmed.length < minimum || trimmed.length > maximum) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return trimmed;
}

function numberParameter(value, name, minimum, maximum) {
  const parsed = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(parsed) || parsed < minimum || parsed > maximum) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return parsed;
}

function integerParameter(value, name, minimum, maximum) {
  const parsed = numberParameter(value, name, minimum, maximum);
  if (!Number.isInteger(parsed)) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return parsed;
}

function uuidParameter(value, name) {
  if (typeof value !== 'string' || !UUID_PATTERN.test(value)) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return value;
}

function dateParameter(value, name) {
  if (typeof value !== 'string') {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return parsed;
}

function supabaseHeaders(env, authorization) {
  return {
    apikey: env.SUPABASE_PUBLISHABLE_KEY,
    Authorization: authorization,
    'Content-Type': 'application/json',
  };
}

function trimSlash(value) {
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

function responseHeaders(requestId, cors) {
  return {
    ...cors,
    'Cache-Control': 'no-store',
    'Content-Type': 'application/json; charset=utf-8',
    'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff',
    'X-Request-Id': requestId,
  };
}

function jsonResponse(payload, status, requestId, cors) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: responseHeaders(requestId, cors),
  });
}
