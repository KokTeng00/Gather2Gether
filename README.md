# Gather2Gether

Gather2Gether is a mobile-only Flutter app for discovering free events nearby,
creating an event, responding **Join** or **Tentative**, and discussing local
ideas in a moderated community forum. One Dart codebase targets Android and iOS.

## MVP features

- Google-only account creation and sign-in through Supabase Auth
- Foreground-only location permission
- PostGIS nearby-event search at 5, 10, 25, or 50 km
- Draggable Gather Guide with private chat history, nearby-event questions, app
  help, preparation tips, a closable panel, and a profile settings toggle
- Interactive OpenStreetMap view with event markers and map/list switching
- Free event creation with venue, date/time, and capacity
- Atomic Join/Tentative/Cancel RSVP updates
- Cloudflare edge API for event validation and request orchestration
- Profile and approximate home area (coordinates rounded to about 1 km)
- Professional profile with avatar, community activity, real contribution
  counts, identity editing, and tabbed preference/security/account settings
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

Pages Function -> internal service binding -> model Worker
                                      |
                         Cloudflare Secrets Store
                                      |
                       OpenRouter / Gemini 3.1 Flash Lite

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

Gather Guide performs deterministic, indexed PostGIS/full-text event retrieval
before its single model call. Event locations use the existing GiST index;
weighted title/category/venue text uses a generated `tsvector` with a GIN index.
Only the bounded event matches and recent user-owned messages are sent to the
model. Chat history is stored in PostgreSQL behind fixed-signature RPCs and is
never readable across accounts.

## Local setup

Requirements:

- Flutter 3.38+ and Dart 3.10+
- Android Studio/SDK for Android
- A full Xcode installation for iOS builds

```bash
cp .env.example.json .env.json
flutter pub get
flutter devices
flutter run -d DEVICE_ID --dart-define-from-file=.env.json
```

Only the public Supabase URL, publishable key, and Cloudflare edge API URL belong
in `.env.json`. The file is ignored to prevent accidental environment drift
between developers.

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
flutter build apk --debug --dart-define-from-file=.env.json
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

Production uses `google/gemini-3.1-flash-lite` with minimal reasoning for short
response time. Create a separate local-only secret (omit `--remote`) when using
Wrangler local development; production secret values are not available locally.

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
