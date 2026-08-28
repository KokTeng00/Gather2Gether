# Gather2Gether

Gather2Gether is a mobile-only Flutter app for discovering free events nearby,
creating an event, responding **Join** or **Tentative**, and discussing local
ideas in a moderated community forum. One Dart codebase targets Android and iOS.

## MVP features

- Email/password account creation and sign-in
- Foreground-only location permission
- PostGIS nearby-event search at 5, 10, 25, or 50 km
- Interactive OpenStreetMap view with event markers and map/list switching
- Free event creation with venue, date/time, and capacity
- Atomic Join/Tentative/Cancel RSVP updates
- Cloudflare edge API for event validation and request orchestration
- Profile and approximate home area (coordinates rounded to about 1 km)
- Event reporting and user-blocking database foundations
- Authenticated forum posts, replies, reports, block filtering, and abuse limits
- No price fields, payment SDK, or payment collection

## Architecture

```text
Flutter (Android / iOS)
        |
        | Supabase Auth for sign-in
        v
Cloudflare Pages Functions
  Authenticated event API; no public browser app
        |
        | public publishable key + user JWT
        v
Supabase Auth + PostgreSQL + PostGIS + RLS + transactional RPCs

Terraform
  Supabase project/settings + Cloudflare Pages project
```

Cloudflare validates and normalizes event and forum requests, verifies the Supabase user
session, and forwards the user's JWT. Supabase remains the final authorization
and transaction boundary. The edge Function has no service-role key. The mobile
client never receives a database password, JWT signing secret, service-role key,
Supabase personal token, or Cloudflare token.

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

Terraform owns the dedicated Supabase project and Cloudflare Pages project.
Database tables and policies remain SQL migrations because schema history is
safer and easier to review outside Terraform state.

```bash
cp infrastructure/terraform/terraform.tfvars.example \
  infrastructure/terraform/terraform.tfvars

terraform -chdir=infrastructure/terraform init
terraform -chdir=infrastructure/terraform plan
terraform -chdir=infrastructure/terraform apply
```

The Supabase project has `prevent_destroy = true`. Terraform state contains the
generated database password, so use an encrypted remote backend with restricted
access before adding CI/CD or teammates.

Apply database migrations after Terraform creates the project:

```bash
export SUPABASE_ACCESS_TOKEN="..."
export SUPABASE_DB_PASSWORD="$(terraform -chdir=infrastructure/terraform output -raw supabase_db_password)"
PROJECT_REF="$(terraform -chdir=infrastructure/terraform output -raw supabase_project_ref)"

npx supabase@latest link --project-ref "$PROJECT_REF"
npx supabase@latest db push --dry-run
npx supabase@latest db push
```

Deploy the `/functions` edge API after setting `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID`:

```bash
npm exec --yes --package=node@22 --package=wrangler@latest -- \
  wrangler pages deploy cloudflare/public --branch main
```

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
