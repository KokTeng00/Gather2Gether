# Security notes

## Implemented controls

- Row Level Security is enabled on every app-facing table.
- Organizer identity is always derived from `auth.uid()` on the server.
- Join capacity is enforced under a database lock, preventing race-condition
  overbooking.
- Security-definer functions use an empty `search_path`, validate inputs, and
  expose only the minimum required data.
- Event operations pass through a Cloudflare Pages Function that verifies the
  Supabase session, constrains request size and fields, and maps backend errors
  to a small safe error vocabulary.
- Forum tables deny direct client access. Fixed-signature RPCs enforce post and
  reply length, per-user database rate limits, locked discussions, mutual block
  filtering, duplicate-report prevention, and a private moderation queue.
- The Cloudflare Function forwards the user's JWT and publishable key. It has no
  service-role key and cannot bypass Supabase RLS.
- Anonymous users cannot read profiles, events, RSVPs, reports, or blocks.
- Profiles store only rounded coordinates; no background location or location
  history is collected.
- Auth sessions use Android Keystore encryption and iOS Keychain.
- Android cloud backup is disabled for encrypted auth material.
- Cloudflare serves HSTS, CSP, anti-framing, MIME-sniffing, referrer, and
  permissions-policy headers.
- Terraform protects the Supabase project from accidental deletion.
- The product has no payment or price data path.

The map loads public OpenStreetMap tiles on demand. As with any map tile
provider, the provider receives the device IP address and requested tile area.
The app does not send the user's account identity to the tile provider, and it
does not collect background location or retain a location trail. Before a
large-scale launch, use a production tile service or properly operated cache
with a privacy agreement and service capacity suitable for the audience.

## Credential rules

The Flutter app may contain only:

- the Supabase project URL;
- the Supabase publishable key;
- the public Cloudflare edge API URL.

The Cloudflare Function environment may contain the same public Supabase URL and
publishable key. It must never contain a database password, Supabase personal
access token, service-role key, or JWT signing secret.

Never place a Cloudflare token, Supabase personal access token, database
password, service-role/secret key, or JWT signing secret in Dart code, web
assets, CI logs, or committed variable files.

Terraform state contains the generated database password even though Terraform
marks it sensitive. Move state to an encrypted, access-controlled remote
backend before team or CI use.

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
- Add an admin moderation UI with MFA-protected admin accounts.
- Add production error monitoring with PII scrubbing and retention limits.
- Publish privacy, safety, acceptable-use, and data-deletion policies.
- Perform dependency, RLS, and abuse-case reviews before each release.
- Add per-user Cloudflare rate-limit bindings before opening registration at
  scale; database capacity checks must remain authoritative because edge rate
  limits are not transaction locks.
