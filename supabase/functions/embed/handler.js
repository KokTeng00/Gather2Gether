import {BodyTooLargeError, readBoundedText} from '../_shared/http-body.js';

const encoder = new TextEncoder();
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleEmbedRequest(request, env, runModel) {
  if (request.method !== 'POST') {
    return Response.json({error: 'method_not_allowed'}, {status: 405});
  }

  // A publishable key can pass the platform gate without a signed-in user.
  // Verify the session with Auth before reading the body or starting inference.
  const authorization = request.headers.get('Authorization') ?? '';
  if (authorization.length > 8192 || !/^Bearer\s+\S+$/i.test(authorization)) {
    return Response.json({error: 'authentication_required'}, {status: 401});
  }
  const apiKey = request.headers.get('apikey') || env.SUPABASE_ANON_KEY;
  if (!env.SUPABASE_URL || !apiKey) {
    return Response.json({error: 'authentication_unavailable'}, {status: 503});
  }
  try {
    const response = await fetch(`${env.SUPABASE_URL.replace(/\/$/, '')}/auth/v1/user`, {
      headers: {apikey: apiKey, Authorization: authorization},
      signal: AbortSignal.timeout(5000),
      redirect: 'error',
    });
    if (!response.ok) {
      await response.body?.cancel();
      const unavailable = response.status >= 500 || response.status === 429;
      return Response.json(
        {error: unavailable ? 'authentication_unavailable' : 'invalid_session'},
        {status: unavailable ? 503 : 401},
      );
    }
    const user = await response.json();
    if (!user || !UUID_PATTERN.test(user.id ?? '') || user.is_anonymous === true) {
      return Response.json({error: 'invalid_session'}, {status: 401});
    }
  } catch {
    return Response.json({error: 'authentication_unavailable'}, {status: 503});
  }

  let body;
  try {
    body = JSON.parse(await readBoundedText(request, 16 * 1024));
  } catch (error) {
    if (error instanceof BodyTooLargeError) {
      return Response.json({error: 'request_too_large'}, {status: 413});
    }
    return Response.json({error: 'invalid_json'}, {status: 400});
  }
  if (!body || Array.isArray(body) || typeof body !== 'object' ||
      Object.keys(body).length !== 1 || typeof body.input !== 'string') {
    return Response.json({error: 'invalid_request'}, {status: 400});
  }
  const input = body.input.trim();
  if (input.length < 1 || input.length > 4000 || encoder.encode(input).length > 12 * 1024) {
    return Response.json({error: 'invalid_input'}, {status: 400});
  }
  try {
    const embedding = await runModel(input);
    if (!Array.isArray(embedding) || embedding.length !== 384 ||
        embedding.some((value) => typeof value !== 'number' || !Number.isFinite(value))) {
      return Response.json({error: 'invalid_embedding'}, {status: 502});
    }
    return Response.json({embedding});
  } catch {
    return Response.json({error: 'embedding_unavailable'}, {status: 503});
  }
}
