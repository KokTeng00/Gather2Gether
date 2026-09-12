const INVITE_PATH = /^\/invite\/([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\/?$/i;

const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

export function onRequest(context) {
  const request = context?.request;
  const url = new URL(request?.url ?? 'https://gather2gether.invalid/');
  const invite = INVITE_PATH.exec(url.pathname);
  if ((request?.method ?? 'GET') === 'GET' && invite !== null) {
    return invitation(invite[1].toLowerCase(), context?.env);
  }
  return new Response('Not Found', {status:404, headers:headers('text/plain; charset=utf-8')});
}

async function invitation(eventId, env) {
  let preview = null;
  if (env?.SUPABASE_URL && env?.SUPABASE_PUBLISHABLE_KEY) {
    try {
      const response = await fetch(`${env.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/rpc/get_event_invite_preview`, {
        method:'POST', headers:{apikey:env.SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'},
        body:JSON.stringify({p_event_id:eventId}), signal:AbortSignal.timeout(5000),
      });
      if (response.ok) {
        const reader = response.body?.getReader();
        if (reader) {
          const chunks=[]; let size=0;
          try {
            while (true) {
              const {value,done}=await reader.read(); if(done) break;
              size+=value.byteLength;
              if(size>16384) {await reader.cancel(); throw new Error('preview too large');}
              chunks.push(value);
            }
          } finally {reader.releaseLock();}
          const bytes=new Uint8Array(size); let offset=0;
          for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
          const data=JSON.parse(new TextDecoder().decode(bytes));
          if(data && typeof data.title==='string' && typeof data.description==='string' &&
            data.title.length<=120 && data.description.length<=2000 && Number.isFinite(Date.parse(data.start_at))) preview=data;
        }
      }
    } catch (_) { /* A private or unavailable preview still offers the app handoff. */ }
  }
  const title=preview?.title ?? 'You’re invited';
  const description=preview?.description ?? 'Open this invitation in Gather2Gether to see the event and join the group.';
  const area=typeof preview?.area==='string' ? preview.area.slice(0,120) : '';
  const offset=Number.isInteger(preview?.timezone_offset_minutes) && Math.abs(preview.timezone_offset_minutes)<=840 ? preview.timezone_offset_minutes : 0;
  const date=preview ? new Date(Date.parse(preview.start_at)+offset*60000) : null;
  const when=date ? new Intl.DateTimeFormat('en-GB',{weekday:'long',day:'numeric',month:'long',hour:'2-digit',minute:'2-digit',timeZone:'UTC'}).format(date) : '';
  const zone=offset===0?'UTC':`UTC${offset<0?'−':'+'}${String(Math.floor(Math.abs(offset)/60)).padStart(2,'0')}:${String(Math.abs(offset)%60).padStart(2,'0')}`;
  return new Response(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)} · Gather2Gether</title><meta name="description" content="${escapeHtml(description.slice(0,180))}">
<meta property="og:title" content="${escapeHtml(title)}"><meta property="og:description" content="${escapeHtml(description.slice(0,180))}"><meta property="og:type" content="website">
<style>
*{box-sizing:border-box}body{margin:0;background:#f8f8f5;color:#202a25;font:16px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;line-height:1.6}main{max-width:580px;margin:0 auto;padding:40px 24px 64px}.brand{font-size:17px;font-weight:650;letter-spacing:-.4px;margin-bottom:64px;color:#285f46}.eyebrow{color:#626b63;font-size:13px;font-weight:600;margin:0 0 12px}h1{font-size:clamp(30px,7vw,44px);line-height:1.12;letter-spacing:-1.2px;font-weight:650;margin:0 0 28px}.facts{border-top:1px solid #dce1da;border-bottom:1px solid #dce1da;padding:16px 0;margin-bottom:28px}.facts p{margin:4px 0}.description{white-space:pre-wrap;overflow-wrap:anywhere}a{display:block;text-align:center;margin-top:36px;padding:14px 20px;border-radius:12px;background:#285f46;color:white;text-decoration:none;font-weight:600}a:focus-visible{outline:3px solid #849a89;outline-offset:4px}.note{font-size:13px;color:#626b63;text-align:center;margin-top:14px}.cancelled{color:#973d32;font-weight:600}small{color:#626b63;font-size:12px}@media(prefers-color-scheme:dark){body{background:#141a16;color:#e6ebe6}.brand{color:#a6cfb2}.eyebrow,.note,small{color:#a5afa6}.facts{border-color:#354036}a{background:#a6cfb2;color:#173223}.cancelled{color:#f0a699}}
</style></head><body><main><div class="brand">Gather2Gether</div><p class="eyebrow">${preview ? 'A free event, an open invitation' : 'An invitation from your community'}</p><h1>${escapeHtml(title)}</h1>
${preview?.cancelled ? '<p class="cancelled">This event has been cancelled.</p>' : ''}
${date ? `<div class="facts"><p>${escapeHtml(when)} <small>${escapeHtml(zone)}</small></p>${area ? `<p>${escapeHtml(area)}</p>` : ''}</div>` : ''}
<p class="description">${escapeHtml(description)}</p><a href="gather2gether://event/${eventId}?invite=1">Open in Gather2Gether</a>
<p class="note">${preview ? 'Sign in to see the meeting point and respond.' : 'The host is keeping event details in the app.'}<br>If you haven’t installed the app yet, save this link for later.</p></main></body></html>`, {status:200,headers:headers('text/html; charset=utf-8')});
}

function headers(contentType) {
  return {'Cache-Control':'no-store','Content-Type':contentType,
    'Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    'Permissions-Policy':'camera=(), microphone=(), geolocation=()', 'Referrer-Policy':'no-referrer',
    'X-Content-Type-Options':'nosniff','X-Frame-Options':'DENY','X-Robots-Tag':'noindex, nofollow'};
}
