// Review this notice and configure the public operator/contact before publishing.
const pages = {
  '/privacy': ['Privacy notice', `
    <h2>Information we use</h2>
    <p>We use your sign-in provider identifier and email to maintain your account. Your profile may include a name, username, photo, city, interests, accessibility preferences and approximate home area. We also store the events, RSVPs, posts, replies, reports, follows, blocks and preferences you create.</p>
    <p>Location access is foreground-only. Saved home coordinates are rounded to about one kilometre. Nearby searches send search coordinates to our services. Venue and meeting-point coordinates are stored with events. We do not maintain a GPS location history.</p>
    <h2>Sharing and audiences</h2>
    <p>Profile and community content is visible to eligible signed-in members. Event audiences, attendee visibility and blocks restrict access. Hosts can enable an anonymous invitation preview of selected event text and a broad area. Meeting points, addresses, attendee lists and private photos require sign-in and permission. Avoid putting private details in text you choose to share publicly.</p>
    <h2>Providers and AI</h2>
    <p>Supabase provides accounts and database storage. Cloudflare serves the API and stores uploaded photos. Google, and Apple when enabled, authenticate accounts. Map requests go to OpenFreeMap; address queries go through our API to Geoapify. Providers receive the data needed to serve these requests, including network identifiers.</p>
    <p>When you use Gather Guide or an AI writing, translation or summary tool, relevant messages and selected event or discussion text are sent through Cloudflare and OpenRouter to the configured inference provider, Google Gemini. Do not put sensitive personal information into AI requests.</p>
    <p>Optional recommendation reranking uses Voyage through OpenRouter. It receives action labels and public-content summaries without your account ID, profile, precise location or private chats. Disable personalization or reset activity in Settings. Provider processing is subject to providers’ own terms and retention practices.</p>
    <p>If remote notifications are enabled, Firebase Cloud Messaging and Apple Push Notification service process device tokens and notification payloads. Device-local reminders and the in-app inbox work without remote push.</p>
    <h2>Retention and controls</h2>
    <p>Account and activity records remain until removed or your account is deleted, subject to moderation and operational requirements. Gather Guide retains at most 200 messages per member until history or the account is deleted. Recommendation scoring reads recent activity; older aggregate signals are pruned after 180 days as the feature is used.</p>
    <p>Recently viewed event snapshots are encrypted on your device and scoped to your account. Previously delivered content, screenshots and offline copies cannot be recalled after audience changes. Backup copies follow the hosting providers’ retention schedules.</p>
    <p>Settings includes account-data export, deletion, notification controls, approximate-location settings, visibility choices and recommendation controls. Contact us about access, correction, deletion or other privacy requests. See <a href="/account-deletion">account deletion</a> for instructions.</p>
  `],
  '/terms': ['Community rules and beta terms', `
    <p>Gather2Gether helps people arrange free activities. Beta features may change or be unavailable. Confirm important plans directly with your host.</p>
    <h2>Take care of one another</h2>
    <p>Meet in public places, respect boundaries, and provide accurate details. Decide whether an activity, location and group are suitable for you. Event age labels are guidance, not identity verification or supervision.</p>
    <h2>Content and conduct</h2>
    <p>Do not post threats, harassment, discrimination, sexual exploitation, illegal material, scams or spam. Do not publish another person’s private information or photos without permission. Only share content you have the right to use.</p>
    <p>Use report and block for harmful content or behaviour. Moderators may hide content and review reports. For immediate danger, contact local emergency services; this app is not an emergency channel.</p>
    <h2>Hosts and participants</h2>
    <p>Hosts should keep capacity, meeting instructions and cancellations current. Cancel your RSVP when you cannot attend. An RSVP does not guarantee an activity will take place. Review AI suggestions before publishing or relying on them.</p>
    <p>Contact us about moderation decisions, accessibility or these rules. You may stop using the beta and delete your account at any time.</p>
  `],
  '/account-deletion': ['Delete your account', `
    <p>Open <strong>You → Settings → Account &amp; profile → Delete account</strong> in Gather2Gether and complete the confirmation. Deletion permanently removes your account, profile, hosted events, RSVPs, posts, uploaded photos, conversations and feedback.</p>
    <p>You can export account data from Account settings first. Deleting Gather2Gether does not delete your Google or Apple account. Copies already shared with others and backups may remain until removed or expired.</p>
    <p>If you cannot sign in, email the contact below from the address associated with your account and request deletion. We will verify ownership before taking action. Never send a password or sign-in code.</p>
  `],
  '/support': ['Help and beta feedback', `
    <p>For bugs, include what you were doing, what you expected, what happened, your app version, phone model and operating-system version. Screenshots can help; remove personal information first.</p>
    <p>Report unsafe content in the app so moderators can find the relevant event, post or reply. Use block to limit contact with another member.</p>
    <p>Contact us below for sign-in, accessibility, privacy or account-deletion help. Do not include passwords, access tokens or sensitive personal information.</p>
  `],
};

const escapeHtml = value => String(value).replace(/[&<>"']/g,
  c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));

export function publicInformationResponse(path, env = {}, method = 'GET') {
  const page = pages[path.replace(/\/$/, '')];
  if (!page) return null;
  const headers = {
    'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store',
    'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'no-referrer',
  };
  if (!['GET', 'HEAD'].includes(method)) {
    return new Response(null, {status: 405, headers: {...headers, Allow: 'GET, HEAD'}});
  }
  const operator = typeof env.APP_OPERATOR_NAME === 'string' ? env.APP_OPERATOR_NAME.trim() : '';
  const email = typeof env.SUPPORT_EMAIL === 'string' ? env.SUPPORT_EMAIL.trim() : '';
  if (!operator || operator.length > 160 || !/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(email)) {
    return new Response(method === 'HEAD' ? null : 'This information is temporarily unavailable. Please try again later.', {
      status: 503, headers: {...headers, 'Content-Type': 'text/plain; charset=utf-8'},
    });
  }
  const [title, content] = page;
  const body = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title} · Gather2Gether</title>
  <style>body{margin:0;background:#f8f8f5;color:#1b211d;font:16px/1.65 system-ui,sans-serif}main{max-width:720px;margin:auto;padding:36px 24px 60px}nav{display:flex;flex-wrap:wrap;gap:16px}a{color:#285f46;overflow-wrap:anywhere}h1{font-size:32px;line-height:1.2}h2{font-size:21px;margin-top:28px}footer{border-top:1px solid #ccd5cc;margin-top:36px;padding-top:20px}a:focus-visible{outline:3px solid #285f46;outline-offset:4px}@media(prefers-color-scheme:dark){body{background:#151715;color:#e8ece6}a{color:#9bd3ad}}</style></head>
  <body><main><p>Gather2Gether</p><h1>${title}</h1>${content}<footer><p>Operated by ${escapeHtml(operator)}.<br>Support and privacy: <a href="mailto:${escapeHtml(email)}">${escapeHtml(email)}</a></p>
  <nav><a href="/privacy">Privacy</a><a href="/terms">Community rules</a><a href="/account-deletion">Delete account</a><a href="/support">Help &amp; feedback</a></nav></footer></main></body></html>`;
  return new Response(method === 'HEAD' ? null : body, {status: 200, headers});
}
