# Security notes

## Implemented controls

- Row Level Security is enabled on every app-facing table.
- Organizer identity is always derived from `auth.uid()` on the server.
- Join capacity is enforced under a database lock, preventing race-condition
  overbooking. The same transaction promotes the oldest waitlisted member when
  a joined place is released.
- Security-definer functions use an empty `search_path`, validate inputs, and
  expose only the minimum required data.
- Event operations pass through a Cloudflare Pages Function that verifies the
  Supabase session, constrains request size and fields, and maps backend errors
  to a small safe error vocabulary.
- Forum tables deny direct client access. Fixed-signature RPCs enforce post and
  reply length, per-user database rate limits, locked discussions, mutual block
  filtering, duplicate-report prevention, and a private moderation queue.
- Community and profile JPEGs live in a private Cloudflare R2 bucket. The
  database exposes only a `has_image` marker to forum feeds, and authenticated
  RPCs authorize each object read before the edge API streams it.
- On-device media preparation re-encodes to JPEG, strips EXIF/GPS metadata,
  caps dimensions, and enforces a 5 MiB limit. The edge API independently checks
  declared and actual size plus JPEG signatures before storing an object.
- Forum drafts use one overwriteable staging object per user, limiting abandoned
  storage. Terraform expires the `staging/` prefix after 24 hours as a fallback.
  Place tags require a paired public-place name and address, and the composer
  warns users never to post a home or private address.
- The Cloudflare Function forwards the user's JWT and publishable key. It has no
  service-role key and cannot bypass Supabase RLS.
- Anonymous users cannot read profiles, events, RSVPs, reports, or blocks.
- Event saves, reminders, announcements, attendee messages, feedback, and
  notifications deny direct client access. Fixed-signature functions scope
  plans and the notification inbox to `auth.uid()`, restrict event discussion
  to hosts and participating members, and derive organizer authority from the
  authenticated session.
- Shared invitation pages contain only an opaque event identifier and an app
  deep link. They do not query or expose private profile, attendee, location, or
  database data. Event details remain behind the authenticated mobile API.
- Device reminders are scheduled locally only after the member explicitly
  chooses a reminder time. Declining OS notification permission leaves the
  private in-app reminder available and does not weaken server authorization.
- Remote notification tokens deny direct table access and are managed only by
  owner-scoped registration functions. Manual sign-out removes the current
  token; account deletion removes every associated token by cascade. A separate
  scheduled Worker can claim only the bounded push outbox through service-role
  functions. Invalid provider tokens are disabled and transient failures use a
  bounded retry schedule.
- Notification category preferences and quiet hours are checked while push rows
  are claimed, so a compromised or stale client cannot bypass the member's
  delivery choices. Quiet-hour evaluation uses a validated local UTC offset and
  defers non-essential delivery rather than discarding the notification.
- Profiles store only rounded coordinates; no background location or location
  history is collected.
- Upcoming public events may appear on an organizer's profile. Past event
  activity is private by default and exposed to other authenticated members
  only after the profile owner opts in. Public attendance requires an explicit
  attendance confirmation; owner views and block checks are enforced inside
  the profile-event RPC rather than relying on client-side hiding.
- Recommendation signals are private aggregate rows scoped to `auth.uid()`;
  direct table access is denied. They contain content IDs and action types, not
  search text, raw GPS history, or third-party tracking identifiers. Repeated
  views are de-duplicated for six hours, ranking influence decays over time,
  and signals older than 180 days are removed as the member continues using the
  app.
- Recommendation retrieval uses declared interests locally from the first visit
  and at most twelve distinct items from the last thirty days. Repeated views
  do not amplify rank. Existing saves and attendance are read without a new
  tracking log; hidden/blocked content and poorly rated events are excluded
  from positive evidence. Resetting excludes old operational activity without
  deleting saved plans. Interests remain in PostgreSQL.
- After one deliberate choice, the first 24 public candidates may be
  cross-encoder reranked through the private model Worker and OpenRouter. The provider receives an
  anonymous preference summary containing action labels and truncated public
  content, never the user ID, profile fields, exact member location, searches,
  private messages, or comment text. Requests deny providers that enable data
  collection, exact results are cached for six hours, and an atomic throttle
  allows at most one model attempt per member and feed type in that interval.
  Views alone never trigger this call. Failure falls back to the database ranking.
- Recommendation opt-outs, hidden categories, and per-content dismissals are
  owner-scoped database state with no direct table access. The edge filters
  dismissed content before any optional model reranking request.
- Assistant messages deny direct table access. Security-definer RPCs scope
  history, deletion, rate limits, and replies to `auth.uid()`.
- Assistant event lookup combines a GiST geography index, a GIN full-text index,
  future-event filters, mutual blocks, and a hard result limit before calling a
  model. The model cannot query PostgreSQL or invent authoritative availability.
- The OpenRouter key is an account-level Cloudflare Secrets Store binding on a
  private model Worker. Pages reaches it through a service binding; neither
  service logs, returns, or sends the key to the mobile client.
- Optional event drafting, translation, and discussion summaries have strict
  structured-output schemas and per-member hourly quotas. Translation and
  summary source text is fetched through authorization-checked database
  functions rather than accepted from the mobile request.
- Natural-language event filters, event quality review, and moderation triage
  use strict input and output schemas, bounded text, per-member quotas, and the
  same private model-service boundary. Moderation triage only orders an existing
  queue; it cannot mutate content, reports, or accounts.
- Moderator access is derived from authenticated JWT app metadata and checked
  again inside fixed database functions. Every report action records the actor,
  action, target, and note in an append-only audit table unavailable to clients.
- Data export is owner-scoped and includes the member's recommendation signals
  and controls for transparency, while deliberately excluding push tokens,
  private object-storage keys, credentials, model caches, and rate-limit state.
- Offline event snapshots are stored per authenticated account in platform
  secure storage. Offline mode is read-only and visibly labelled; RSVP, report,
  moderation, profile, and hosting mutations still require the live API.
- Auth sessions use Android Keystore encryption and iOS Keychain.
- Hosted Supabase Auth disables email/password authentication; the app exposes
  only Google OAuth and creates profiles after the first successful Google
  sign-in.
- Android cloud backup is disabled for encrypted auth material.
- Cloudflare serves HSTS, CSP, anti-framing, MIME-sniffing, referrer, and
  permissions-policy headers.
- Cloudflare requests emit structured outcome logs containing request IDs,
  routes, status, and duration but no JWTs, prompts, profile values, device
  tokens, or provider credentials. Standalone Workers enable sampled traces;
  together with the versioned health check, these support operational
  monitoring without broadening data collection.
- Terraform protects the Supabase project from accidental deletion.
- The product has no payment or price data path.

The MapLibre client loads public OpenFreeMap vector tiles on demand. The tile
provider receives the device IP address and requested tile area, but the app
does not send the user's account identity. Address completion sends the typed
search text and an optional current-location ranking bias to the authenticated
Pages Function, which forwards only those fields to Geoapify. Geoapify does not
receive the Supabase JWT, user ID, or account profile. The provider credential
stays in the Pages environment, and autocomplete responses are bounded and
normalized before reaching the client. The app does not collect background
location or retain a location trail. Before a large-scale launch, review both
providers' capacity, privacy terms, and service guarantees for the expected
audience.

## Credential rules

The Flutter app may contain only:

- the Supabase project URL;
- the Supabase publishable key;
- the public Cloudflare edge API URL.
- Firebase's public mobile project, sender, app, API-key, and iOS bundle
  identifiers.

The Pages Function environment may contain the same public Supabase URL and
publishable key. `GEOAPIFY_API_KEY` must be supplied as a Pages secret and is
used only by the authenticated autocomplete route. The OpenRouter credential
must be supplied only through the `OPENROUTER_API_KEY` account-level Secrets
Store binding on the private model Worker. The push dispatcher is the sole
exception for a Supabase service-role key: it stores that key and the dedicated
Firebase service-account email/private key only as Worker secrets, and its code
invokes only service-role outbox functions. The service-role credential itself
can bypass RLS, so access to that Worker and its secrets must be tightly
restricted and audited. Pages and the model Worker must not contain a database
password, Supabase personal access token, service-role key, or JWT signing
secret.

Never place a Cloudflare token, Supabase personal access token, database
password, service-role/secret key, or JWT signing secret in Dart code, web
assets, CI logs, or committed variable files.

Any model credential pasted into chat or another third-party system must be
rotated after initial setup. Update the Secrets Store value through Wrangler's
masked interactive prompt, never through a command-line `--value` argument.

Terraform state contains the generated database password and Google OAuth client
secret even though Terraform marks them sensitive. Move state to an encrypted,
access-controlled remote backend before team or CI use.

## Required credential rotation

Credentials pasted into chat must be considered exposed. Rotate:

1. the Cloudflare API token;
2. the Supabase personal access token;
3. the old `ads project` database password and JWT secret.

Rotating the old project's JWT secret invalidates its legacy anon/service-role
JWT keys and may break its existing clients. Coordinate that rotation with the
owner of the old application. The new Gather2Gether project does not use the old
project's database password or JWT secret.

## Before public launch

- Configure custom SMTP and verify confirmation/reset email flows.
- Enable Supabase CAPTCHA and review Auth rate limits.
- Require MFA and short-lived sessions for every moderator account before
  assigning the moderator role in production.
- Add image safety scanning and an image-aware moderation workflow before
  opening photo posting to a large public audience.
- Route the structured Cloudflare logs and standalone Worker traces to
  production alerts; verify PII scrubbing, access control, sampling, and
  retention limits in that sink.
- Publish privacy, safety, acceptable-use, and data-deletion policies.
- Perform dependency, RLS, and abuse-case reviews before each release.
- Add per-user Cloudflare rate-limit bindings before opening registration at
  scale; database capacity checks must remain authoritative because edge rate
  limits are not transaction locks.
- Publish assistant-specific retention and AI-subprocessor disclosures. The app
  currently retains at most 200 messages per user until they clear history or
  delete their account.
- Include recommendation reranking in the AI-subprocessor disclosure, including
  the action labels and public-content summaries sent to OpenRouter and the
  selected inference provider's retention terms.

### Event audiences

Event visibility supports public, unlisted, followers, following, and selected
members. Audience usernames are validated transactionally and stored as profile
IDs in an RLS-protected table with no client table grants. Only event managers
receive the recipient usernames. The follower relation is evaluated relative to
the original organizer, including edits by co-hosts.

Database checks cover discovery, profiles, event details, invite links, meeting
photos, RSVPs, saves, discussion, conflicts, notifications, and queued pushes.
Old saves or RSVPs cannot bypass a restricted audience. Direct event updates are
revoked in favor of the validated RPCs. Restricted events cannot enable anonymous
invite previews; automatic embedding and model reranking exclude their content.
Previously delivered content, including offline snapshots, cannot be recalled.
