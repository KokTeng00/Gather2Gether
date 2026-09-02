import 'jsr:@supabase/functions-js/edge-runtime.d.ts'

const model = new Supabase.ai.Session('gte-small')
const encoder = new TextEncoder()

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 })
  }
  const length = Number(request.headers.get('content-length') ?? 0)
  if (Number.isFinite(length) && length > 16 * 1024) {
    return Response.json({ error: 'request_too_large' }, { status: 413 })
  }

  let body: unknown
  try {
    body = await request.json()
  } catch {
    return Response.json({ error: 'invalid_json' }, { status: 400 })
  }
  if (!body || Array.isArray(body) || typeof body !== 'object') {
    return Response.json({ error: 'invalid_request' }, { status: 400 })
  }
  const record = body as Record<string, unknown>
  if (Object.keys(record).length !== 1 || typeof record.input !== 'string') {
    return Response.json({ error: 'invalid_request' }, { status: 400 })
  }
  const input = record.input.trim()
  if (input.length < 1 || input.length > 4000 || encoder.encode(input).length > 12 * 1024) {
    return Response.json({ error: 'invalid_input' }, { status: 400 })
  }

  try {
    const embedding = await model.run(input, {
      mean_pool: true,
      normalize: true,
    })
    if (
      !Array.isArray(embedding) ||
      embedding.length !== 384 ||
      embedding.some((value) => typeof value !== 'number' || !Number.isFinite(value))
    ) {
      return Response.json({ error: 'invalid_embedding' }, { status: 502 })
    }
    return Response.json({ embedding })
  } catch {
    return Response.json({ error: 'embedding_unavailable' }, { status: 503 })
  }
})
