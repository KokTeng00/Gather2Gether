# Gather2Gether

Gather2Gether is a mobile-only Flutter app for discovering free events nearby,
creating an event, managing the full plan from invitation through feedback, and
discussing local ideas in a moderated community forum. One Dart codebase targets
Android and iOS.

## MVP features

- Google-only account creation and sign-in through Supabase Auth
- Foreground-only location permission
- PostGIS nearby-event search at 5, 10, 25, or 50 km, with date, time,
  category, available-place, and followed-organizer filters
- A single Search alerts view for creating, applying, and removing reusable
  discovery alerts, plus a dedicated feed for followed organizers
- Draggable Gather Guide with private chat history, nearby-event questions, app
  help, preparation tips, a closable panel, and a profile settings toggle
- Global OpenFreeMap vector map with tappable event markers and map/list switching
- Free event creation with worldwide Geoapify address completion, venue,
  date/time, capacity, accessibility and suitability details, plus a
  pre-filled Create again action
- Plans hub for Going, Maybe/Waitlist, Hosting, Saved, and Past events
- Atomic Join/Tentative/Waitlist/Cancel RSVP updates with automatic promotion
- Device and in-app reminders, native calendar handoff, and map directions
- Organizer editing, cancellation, attendee announcements, RSVP reconfirmation,
  and automatic release/promotion of unconfirmed places
- Saved events, moderated attendee questions, attendance confirmation, and
  private post-event feedback
- Privacy-aware attendee lists, per-event attendee visibility, and discussion
  notification muting that keeps essential event updates enabled
- Shareable invitation landing pages with authenticated mobile deep links
- High-accuracy hybrid event and discussion recommendations from recent views,
  RSVPs, likes, and replies, with nearby/fresh cold-start feeds
- Cloudflare edge API for event validation and request orchestration
- Profile and approximate home area (coordinates rounded to about 1 km)
- Professional profile with avatar, community activity, upcoming hosted events,
  owner-controlled past-event visibility, real contribution counts, identity
  editing, and grouped preference/security/privacy/account settings
- Event reporting and user-blocking database foundations
- Authenticated forum posts, replies, reports, block filtering, and abuse limits
- Privacy-safe community JPEGs and public-place tags, backed by private R2
  storage and authenticated media routes
- No price fields, payment SDK, or payment collection

## Architecture

```text
Flutter (Android / iOS)
        |
        | Supabase Auth for sign-in
        v
Cloudflare Pages Functions
  Authenticated event, forum, profile, and private-media API
        |
        | public publishable key + user JWT
        v
Supabase Auth + PostgreSQL + PostGIS + RLS + transactional RPCs

Pages Functions -> private Cloudflare R2 user-media bucket

Flutter -> OpenFreeMap global vector tiles

Flutter -> Pages Functions -> Geoapify address autocomplete

Pages Function -> internal service binding -> model Worker
                                      |
                         Cloudflare Secrets Store
                                      |
                   OpenRouter / Gemini + Voyage Rerank 2.5

Terraform
  Supabase project/settings + Cloudflare Pages project
```

Cloudflare validates and normalizes event, forum, profile, and media requests,
verifies the Supabase user session, and forwards the user's JWT. Supabase
remains the final authorization and transaction boundary. The edge Function has
no service-role key. Media objects stay in a non-public R2 bucket; PostgreSQL
stores only validated object references. The mobile client never receives a
database password, JWT signing secret, service-role key, Supabase personal
token, or Cloudflare token.

The Plans lifecycle is also server-authoritative. PostgreSQL serializes capacity
changes and RSVP updates, promotes the oldest waitlisted member when a joined
place opens, and creates private in-app notifications for promotions, host
updates, cancellations, questions, and due reminders. Native reminders mirror
the server preference on the device; if notification permission is declined,
the private in-app inbox remains available. Event discussions are restricted to
the host and members who joined, selected Maybe, or entered the waitlist.
Upcoming public events appear on their organizer's profile. Past profile
activity is private by default; members may opt in to sharing public events they
hosted or explicitly confirmed attending. The database applies that choice even
when the profile-event RPC is called outside the Flutter interface.

Gather Guide performs deterministic, indexed PostGIS/full-text event retrieval
before its single model call. Event locations use the existing GiST index;
weighted title/category/venue text uses a generated `tsvector` with a GIN index.
Only the bounded event matches and recent user-owned messages are sent to the
model. Chat history is stored in PostgreSQL behind fixed-signature RPCs and is
never readable across accounts.

Discover and Community interest search use hybrid retrieval. A cosine HNSW
index finds conceptual matches from `gte-small` embeddings, while a weighted
GIN full-text index preserves strong exact-word, venue, place, and address
matches; reciprocal-rank fusion combines both candidate lists. Event documents
cover title, category, venue, address, and description. Community documents
cover title, topic, body, public place name, and public place address. PostGIS
still enforces the member's configured distance radius for event results.

Default feeds use a two-stage recommender. PostgreSQL aggregates one private row
per member, content item, and signal type; repeated views are counted at most
once every six hours. Views are weak signals, while RSVPs, likes, and replies
have more influence, and all influence decays over time. Candidate retrieval
combines category/author affinity, a weighted centroid of the existing
`gte-small` content embeddings, distance, freshness, and popularity.

After at least two distinct interactions, OpenRouter's
`voyageai/rerank-2.5` cross-encoder reranks only the first 24 candidates. The API
blends that relevance score with the database order so location, recency, and
popularity continue to matter. Each exact ordering is cached for six hours and
is invalidated when behavior or candidates change. An atomic database throttle
permits at most one model attempt per member and feed type every six hours,
including across concurrent refreshes. Provider failures return the database
order, so feeds remain available without AI. Cold-start members also stay
entirely on the local nearby/fresh ranking. Signals older than 180 days are
removed as members continue using the app.

Community presentation interleaves three personalized discussions with one
latest active discussion. IDs are de-duplicated across both sources; if either
source is exhausted, the other fills the remainder of the 30-item feed. Search
results and a member's own-post list retain their direct ordering.

The reranker receives no account identifier, profile fields, exact member
location, search text, or comment text. It receives only action labels attached
to public content summaries plus the public candidate content needed to rank
the shortlist. The request denies providers that enable data collection.

## Local setup

Requirements:

- Flutter 3.38+ and Dart 3.10+
- Android Studio/SDK for Android
- JDK 21+ for Android builds (required by the MapLibre Android plugin)
- A full Xcode installation for iOS builds

```bash
cp .env.example.json .env.json
flutter pub get
flutter devices
flutter run -d DEVICE_ID --dart-define-from-file=.env.json
```

If Flutter is still selecting an older JDK bundled with Android Studio, point it
at a locally installed JDK 21 or newer:

```bash
flutter config --jdk-dir /path/to/jdk-21-or-newer
```

Only the public Supabase URL, publishable key, Cloudflare edge API URL, and
optional public map style URL belong in `.env.json`. The file is ignored to
prevent accidental environment drift between developers.

### Map and address setup

The map uses MapLibre with OpenFreeMap's global vector tiles and needs no API
key. `MAP_STYLE_URL` in `.env.json` is public and optional; the app defaults to
OpenFreeMap's Liberty style.

Address suggestions use Geoapify through the authenticated Pages Function. The
provider key stays on the server and must never be placed in `.env.json` or the
Flutter bundle. Create a free key in the
[Geoapify project dashboard](https://myprojects.geoapify.com), then copy the
ignored local template for Pages development:

```bash
cp .dev.vars.example .dev.vars
```

Set `GEOAPIFY_API_KEY` in `.dev.vars`. For the deployed Pages project, use
Wrangler's masked prompt and then redeploy:

```bash
npx wrangler pages secret put GEOAPIFY_API_KEY --project-name gather2gether
```

Autocomplete is intentionally global: it applies the device location only as a
ranking bias, never as a country filter. Both providers' required attribution
is displayed in the app.

### Google sign-in setup

Create a **Web application** OAuth client in Google Auth Platform. Configure the
consent screen with the `openid`, email, and profile scopes, then add the
Supabase callback URL shown on the Supabase Google provider page as an authorized
redirect URI. For a hosted project it has this form:

```text
https://PROJECT_REF.supabase.co/auth/v1/callback
```

Put the client ID and secret in the ignored
`infrastructure/terraform/terraform.tfvars`, then run `terraform apply`.
Terraform enables the Supabase Google provider and allows the mobile callback
`gather2gether://login-callback`. Google redirects to Supabase first; Supabase
then returns to the app, where `supabase_flutter` exchanges the PKCE code and
stores the resulting Supabase session in the device's secure storage. Email and
password authentication is disabled; a user's profile is created automatically
on their first Google sign-in.

For a local Supabase stack, add
`http://127.0.0.1:54321/auth/v1/callback` to the same Google OAuth client and
export the credentials before starting Supabase:

```bash
export SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID="...apps.googleusercontent.com"
export SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_SECRET="..."
npx supabase@latest start
```

The Google client secret belongs only in Google/Supabase configuration. Never
add it to `.env.json`, Dart defines, the Flutter bundle, or source control.

## Verification

```bash
flutter analyze
flutter test
npm run test:edge
npm run check:edge
flutter build apk --debug --dart-define-from-file=.env.json
```

The Supabase regression suite includes transactional lifecycle coverage for
saved-search alerts, followed-organizer alerts, attendee privacy, discussion
notification preferences, and RSVP reconfirmation:

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/practical_event_tools.sql
```

The disposable live-system smoke test creates two temporary users and verifies
Cloudflare Functions, Supabase auth/profile creation, event discovery,
Tentative/Join, reporting, capacity, and RLS, then deletes all test data:

```bash
export SUPABASE_ACCESS_TOKEN="..."
bash scripts/smoke_test.sh
```

## Infrastructure deployment

Terraform owns the dedicated Supabase project, Cloudflare Pages project,
private R2 media bucket and staging-object lifecycle. It also enforces
Google-only authentication and the mobile callback allow-list. Database tables
and policies remain SQL migrations because schema history is safer and easier
to review outside Terraform state.

```bash
cp infrastructure/terraform/terraform.tfvars.example \
  infrastructure/terraform/terraform.tfvars

terraform -chdir=infrastructure/terraform init
terraform -chdir=infrastructure/terraform plan
terraform -chdir=infrastructure/terraform apply
```

The Supabase project has `prevent_destroy = true`. Terraform state contains the
generated database password and Google OAuth client secret, so use an encrypted
remote backend with restricted access before adding CI/CD or teammates.

Apply database migrations after Terraform creates the project and R2 bucket:

```bash
export SUPABASE_ACCESS_TOKEN="..."
export SUPABASE_DB_PASSWORD="$(terraform -chdir=infrastructure/terraform output -raw supabase_db_password)"
PROJECT_REF="$(terraform -chdir=infrastructure/terraform output -raw supabase_project_ref)"

npx supabase@latest link --project-ref "$PROJECT_REF"
npx supabase@latest db push --dry-run
npx supabase@latest db push
```

Deploy the private model Worker first, then the `/functions` edge API. Cloudflare
requires the service-binding target and the Terraform-managed `USER_MEDIA` R2
bucket to exist before Pages is deployed:

```bash
npm exec --yes --package=node@22 --package=wrangler@latest -- \
  wrangler deploy --config wrangler.assistant.jsonc
npm exec --yes --package=node@22 --package=wrangler@latest -- \
  wrangler pages deploy cloudflare/public --branch main
```

The OpenRouter credential is an account-level Secrets Store binding on the
private `gather2gether-assistant-model` Worker, not a Pages variable or mobile
configuration value. Pages calls that Worker through the `ASSISTANT_MODEL`
service binding, so the secret never enters the public API process. Create it
through Wrangler's masked prompt and bind it as `OPENROUTER_API_KEY` in
`wrangler.assistant.jsonc`:

```bash
wrangler secrets-store store list --remote
wrangler secrets-store secret create STORE_ID \
  --name OPENROUTER_API_KEY --scopes workers --remote
```

Production uses `google/gemini-3.1-flash-lite` with minimal reasoning for Gather
Guide and `voyageai/rerank-2.5` for the high-accuracy recommendation shortlist.
The same private OpenRouter credential serves both routes. Create a separate
local-only secret (omit `--remote`) when using Wrangler local development;
production secret values are not available locally.

The checked-in `wrangler.jsonc` contains only public runtime configuration. Pages
Functions execute validation and orchestration at Cloudflare; database integrity,
RLS, and atomic RSVP capacity remain enforced in Supabase. This split reduces the
amount of business logic in the client, but requests still depend on both vendors
and it is not a database failover strategy. The Pages root returns `404`; only the
mobile clients consume the authenticated `/api/v1` endpoints. API requests that
carry a browser `Origin` header are rejected.

## Security

See [docs/SECURITY.md](docs/SECURITY.md) for the trust boundaries, location
privacy model, credential handling, and production checklist.
