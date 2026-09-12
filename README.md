# Gather2Gether

Gather2Gether is a mobile-only Flutter app for discovering free events nearby,
creating an event, managing the full plan from invitation through feedback, and
discussing local ideas in a moderated community forum. One Dart codebase targets
Android and iOS.

## MVP features

- Google-only account creation and sign-in through Supabase Auth
- Guided first-run setup for interests, accessibility needs, discovery radius,
  and optional approximate home area
- Foreground-only location permission
- PostGIS event search around home or a chosen city at 5, 10, 25, 50, or 100 km,
  with single-day/custom date ranges, time,
  category, available-place, followed-organizer, indoor/outdoor, language,
  age, beginner-friendly, and wheelchair-accessible filters
- Editable Search alerts that can be renamed, refreshed from the current
  filters, paused, resumed, and delivered as in-app or remote notifications
- Draggable Gather Guide with private chat history, nearby-event questions, app
  help, preparation tips, a closable panel, and a profile settings toggle
- Global OpenFreeMap vector map with tappable event markers and map/list switching
- Free event creation with worldwide Geoapify address completion, drafts,
  public or unlisted invitations, bounded weekly/monthly recurrence, co-hosts,
  accessibility and suitability details, plus a pre-filled Create again action
- Plans hub for Going, Maybe/Waitlist, Hosting, Drafts, Saved, and Past events
- Exact meeting-point pins, short arrival instructions, and an optional private
  entrance photo, separate from the venue address
- Atomic Join/Tentative/Waitlist/Cancel RSVP updates with automatic promotion;
  hosts can allow one friend, with whole-party capacity and waitlist handling
- Overlap checks against your joined and hosted plans before joining another event
- Device, in-app, and FCM remote reminders, native calendar handoff, and map
  directions; notification taps open the relevant event
- Category-level notification controls with local-time quiet hours enforced by
  the server-side delivery claim as well as the mobile settings UI
- Organizer editing, cancellation, attendee announcements, RSVP reconfirmation,
  automatic release/promotion of unconfirmed places, recurring-series edit
  scopes, an attendance roster, and a host outcome dashboard
- Saved events, moderated attendee questions, attendance confirmation, and
  private post-event feedback
- Privacy-aware attendee lists, per-event attendee visibility, and discussion
  notification muting that keeps essential event updates enabled
- Shareable invitation landing pages with authenticated mobile deep links and
  host-enabled public previews; addresses, meeting pins, photos, and attendees
  stay behind sign-in
- Interest-based event and discussion recommendations from the first visit,
  refined by a few recent choices, with nearby/fresh fallbacks, plain-language
  recommendation reasons, per-item “Not for me”, category hiding, and reset or
  full opt-out controls
- Cloudflare edge API for event validation and request orchestration
- Profile and approximate home area (coordinates rounded to about 1 km)
- Professional profile with avatar, community activity, upcoming hosted events,
  owner-controlled past-event visibility, real contribution counts, identity
  editing, and grouped preference/security/privacy/account settings
- Report, block/unblock, blocked-member management, and permanent account
  deletion controls, plus a portable in-app account-data export
- Authenticated forum posts, replies, reports, block filtering, and abuse limits
- Community date polls with two or three choices and multiple availability votes;
  authors can turn one date into an event, which each voter joins separately
- Member-visible report status, a role-gated moderator queue and audit trail,
  and optional AI prioritization that leaves enforcement to a human moderator
- Privacy-safe community JPEGs and public-place tags, backed by private R2
  storage and authenticated media routes
- Optional AI-assisted event drafting, on-demand event translation, and
  reviewable discussion summaries with action items, natural-language event
  filters, and pre-publish event quality checks; every result remains editable
  or explicitly user-triggered
- Account-scoped encrypted offline snapshots for event discovery, plans, and
  event details, with explicit offline banners and no offline mutations
- Per-event discussion read cursors with an on-demand “What changed” summary
- Structured Pages/API logs, model/push logs with sampled traces, a versioned
  health contract, a production smoke check, and pull-request release gates
- Quiet light/dark layouts with date-led event lists and clear planning controls
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

Supabase notification outbox -> scheduled Cloudflare Worker -> FCM / APNs

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
Hosts can choose Public, Unlisted, My followers, People I follow, or Specific
people when creating or editing an event. Specific audiences accept up to 50
usernames, resolved to stable profile IDs. Restricted events appear in Discover
and on the host's profile only for eligible members. Follow changes and blocks
apply immediately to future reads; old saves and RSVPs do not grant access.
Hosts and co-hosts retain access. Restricted audiences disable public invite
previews and automatic content embedding/reranking. Previously viewed offline
snapshots may still contain details until refreshed.

Upcoming visible events appear on their organizer's profile. Past profile
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

Default feeds use the member's selected interests immediately, with no activity
history or model call required. PostgreSQL maps broad onboarding choices such as
Sports and Games to event topics and discussion text. Interests remain inside
the database. Location and practical filters constrain event eligibility before
the candidate limit; filtered and unfiltered mobile feeds use the same scorer.

At most twelve distinct items from the last thirty days refine those interests.
Only the strongest action per item counts; repeated views do not add weight.
Existing saves and attendance records supplement RSVPs, likes, and replies
without another tracking log. Hidden or blocked content and poorly rated events
are excluded from positive evidence. Bounded category/author affinity and
similarity to individual `gte-small` content embeddings are combined with
distance, timing, followed organizers, available places, and existing plans.

After one deliberate choice (a save, RSVP, attendance, like, or reply),
OpenRouter's `voyageai/rerank-2.5` may rerank the first 24 candidates. Passive
views alone never trigger a model call. The blend gives 60% to database order
and 40% to model relevance; nearly tied model scores preserve the database order.
Exact orderings are cached for six hours and keyed to evidence, interests,
controls, candidate order, and content updates. An atomic throttle permits at
most one model attempt per member and feed type every six hours. Failures fall
back to the same local interest-based ranking. Existing aggregate signals are
still pruned after 180 days; ranking reads only the last thirty days.

Members remain in control of this personalization. They can disable ranking,
hide categories, dismiss individual event or discussion recommendations, and
reset those choices. Resetting excludes old save/attendance activity from
ranking while preserving the actual saved plans and selected interests. Hidden
IDs and preferences are applied before model reranking. Event reasons identify
actual evidence, for example "Matches your interest in Photography".

The ranking weights are initial product assumptions, not calibrated attendance
probabilities. Synthetic regression scenarios cover first-visit and sparse-data
behavior; real-world accuracy still needs evaluation against a nearby/date feed.

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
- A full Xcode installation for iOS 15+ builds

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

Only the public Supabase URL, publishable key, Cloudflare edge API URL,
optional public map style URL, and Firebase mobile client identifiers belong
in `.env.json`. Firebase's platform API keys identify a mobile app; they are not
the server credential used to send messages. Restrict them to the matching app
IDs in Google Cloud. The file is ignored to prevent accidental environment
drift between developers.

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

Place search is shared by event creation and discussion place tags. It starts
with autocomplete and uses one forward-geocoding fallback when the full venue
name is not matched. An explicitly typed city is separated from the venue name;
common German campus-hall abbreviations are expanded, and unrelated or duplicate
results are removed. For example, `Mannheim UniSport Halle` resolves to the
provider's `Sporthalle der Universität`, Theodor-Heuss-Anlage 15.

Search is global: the device location is a ranking bias, never a country filter.
Both requests share an eight-second deadline, return at most five suggestions,
and keep the existing Geoapify key on the server. Place coverage still depends
on Geoapify's data. Both providers' required attribution is displayed in the app.

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

### Remote notification setup

Create Android and iOS apps in one Firebase project using the package/bundle ID
`com.gather2gether.gather2gether`, enable the FCM HTTP v1 API, and copy their
public project, sender, API-key, and app-ID values into `.env.json`. The app
initializes Firebase from these Dart defines, registers a token only after
Supabase sign-in, tracks token refreshes, and removes the current token before a
manual sign-out. If the Firebase values are absent, the app continues with its
private in-app inbox and local reminders.

For iOS, open `ios/Runner.xcworkspace`, enable the Push Notifications capability
and the Background Modes for Background fetch and Remote notifications, then
upload an APNs `.p8` authentication key for the iOS app in Firebase. Keep
Firebase method swizzling enabled. Test Apple delivery on a physical device.

Create a dedicated Google service account with only the Firebase Cloud Messaging
API Admin role (`roles/firebasecloudmessaging.admin`). Set its `client_email` and
`private_key`, plus the Supabase service-role key, as masked secrets on the
scheduled Worker. Never copy the service-account JSON or Supabase service-role
key into `.env.json`.

Update `FIREBASE_PROJECT_ID` in `wrangler.push.jsonc`, then configure and deploy
the dispatcher using Node 22 or newer:

```bash
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY --config wrangler.push.jsonc
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_EMAIL --config wrangler.push.jsonc
npx wrangler secret put FIREBASE_PRIVATE_KEY --config wrangler.push.jsonc
npm run deploy:push
```

The one-minute Cron Trigger generates due event reminders, claims delivery rows
with `FOR UPDATE SKIP LOCKED`, sends through FCM HTTP v1, disables invalid tokens,
and retries transient failures with bounded exponential backoff. Delivery is
at-least-once, so provider/network failure around acknowledgement can rarely
produce a duplicate notification.

### Moderator setup

The moderation dashboard appears only when the signed-in user's trusted JWT
`app_metadata.role` is `moderator` or `admin`; the database repeats that check
for every queue read and action. Assign this metadata only through a trusted
Supabase admin environment after requiring MFA for that account. Never accept a
moderator role from user-editable profile fields or `user_metadata`.

## Verification

```bash
flutter analyze
flutter test
npm run test:edge
npm run check:edge
npm run check:assistant
npm run check:push
flutter build apk --debug --dart-define-from-file=.env.json
```

The Supabase regression suite includes transactional lifecycle coverage for
saved-search alerts, followed-organizer alerts, attendee privacy, discussion
notification preferences, RSVP reconfirmation, whole-party capacity, safe invite
previews, date polls, and custom search areas:

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/practical_event_tools.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/push_delivery.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/product_operations.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/event_planning.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/interest_first_recommendations.sql
```

The planning release uses `supabase/migrations/20260912000100_event_planning.sql`.
Interest-first recommendations add `supabase/migrations/20260912000200_interest_first_recommendations.sql`.
Event audiences add `supabase/migrations/20260912000300_event_audiences.sql`;
verify access rules with `supabase/tests/event_audiences.sql`.
Apply migrations first, deploy Pages Functions next, then release the mobile app.
The API keeps the existing event routes for older clients; new readers request
`planning=1`. No new external services or secrets are needed. Invitation previews
are off by default, including for existing events, and hosts enable them per event.

For the native map and meeting-pin checks, run:

```bash
flutter test integration_test/event_map_native_test.dart -d <device-id>
```

After deploying API version 2, verify the unauthenticated production health
contract (override `GATHER2GETHER_API_URL` for a custom domain):

```bash
npm run check:production
```

`.github/workflows/verify.yml` runs formatting, analysis, Flutter tests, edge
tests, and all three Cloudflare dry-run builds for every pull request and main
branch push.

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

Deploy the private model Worker first, then the `/functions` edge API and the
separately credentialed push dispatcher. Cloudflare requires the service-binding
target and the Terraform-managed `USER_MEDIA` R2 bucket to exist before Pages is
deployed:

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
Guide and `voyageai/rerank-2.5` for optional recommendation reranking.
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
