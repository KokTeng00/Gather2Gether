const INVITE_PATH = /^\/invite\/([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\/?$/i;

export function onRequest(context) {
  const request = context?.request;
  const url = new URL(request?.url ?? 'https://gather2gether.invalid/');
  const invite = INVITE_PATH.exec(url.pathname);
  if ((request?.method ?? 'GET') === 'GET' && invite !== null) {
    const eventId = invite[1].toLowerCase();
    const appLink = `gather2gether://event/${eventId}?invite=1`;
    return new Response(`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Gather2Gether invitation</title><style>
body{margin:0;background:#f4f1e9;color:#17211b;font:16px system-ui,sans-serif;display:grid;min-height:100vh;place-items:center}
main{max-width:34rem;margin:1.5rem;padding:2rem;background:#fff;border:1px solid #d9ded8;border-radius:1.5rem;box-shadow:0 1rem 3rem #17211b18;text-align:center}
h1{font-size:2rem;margin:.2rem 0 .7rem}p{line-height:1.55;color:#536059}a{display:inline-block;margin-top:1rem;padding:.85rem 1.2rem;border-radius:999px;background:#176b45;color:white;text-decoration:none;font-weight:700}
</style></head><body><main><p>YOU’RE INVITED</p><h1>Join a free local event</h1><p>Open this invitation in Gather2Gether to see the event, save it, or join the group.</p><a href="${appLink}">Open Gather2Gether</a><p>If the app is not installed yet, keep the invitation and open it after installing.</p></main></body></html>`, {
      status: 200,
      headers: {
        'Cache-Control': 'public, max-age=300',
        'Content-Type': 'text/html; charset=utf-8',
        'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
        'Referrer-Policy': 'no-referrer',
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
      },
    });
  }
  return new Response('Not Found', {
    status: 404,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'text/plain; charset=utf-8',
      'Content-Security-Policy': "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
      'Referrer-Policy': 'no-referrer',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
      'X-Robots-Tag': 'noindex, nofollow',
    },
  });
}
