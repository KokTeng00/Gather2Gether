# Beta release setup

The current release work prepares Android signing, optional Apple sign-in,
optional remote push, and public policy/support routes. Do not distribute a
build until the external setup and device checks below are complete.

## Credential incident

The previously tracked `infrastructure/terraform/gather2gether.tfplan` included
the database password, Cloudflare API token, configured Supabase management credential, and
Google OAuth client secret. Those token/secret values matched local deployment
configuration at review time. The GitHub repository is private, but treat all
four credentials as exposed to anyone who could read its history.

The plan was removed from GitHub's `main` history on 2026-09-12 using a narrowly
scoped force-with-lease. All 15 retained commits were checked; the tip's only
tree change was removal of the plan. The local branch now matches the cleaned
history, with all pending beta edits preserved. Local stashes, Codex checkpoints,
reflogs, old clones and cached copies may still retain the previous commits.
Credential replacement is therefore required even after history cleanup. As of
2026-09-13, the Supabase management credential has been replaced, the database
password successfully rotated, the Cloudflare deployment token rolled, and the
Google OAuth client secret replaced. The old Google secret is disabled and
rejected by Google; an existing user's Google login succeeded after disabling it.

Ignore rules and `npm run
check:repository` prevent deployment artifacts and private configuration from
returning to Git; CI runs that check.

A first database-password rotation attempt failed because the stored management
credential was invalid. On 2026-09-13, a new project-scoped management token was
created with the owner's approval, expiring **2027-09-12**, and saved directly into
ignored local Terraform configuration with mode 600. A freshly inspected targeted
plan then rotated the password successfully without recreating the project.
The new password connects with verified TLS; the previous password is rejected.
Terraform's project, password resource and sensitive output agree. Do not reuse
old saved plans to deploy.

Production now has all 28 migrations, including event audiences, report protections
and administrator AAL2 enforcement. Email sign-in is disabled, Google remains
enabled, and TOTP is enabled. Database SSL enforcement is active and a non-TLS
connection is rejected. A private database backup was created before migrations;
a full restore drill and real-device Google/MFA checks are still pending. See
[the security review](SECURITY_REVIEW_2026-09-13.md) for evidence and remaining limits.
The embedding function is deployed as v4 with bounded requests and explicit user
session validation. Public-key-only calls previously returned embeddings; they now
return 401, as do public keys used as Bearer tokens and forged user JWTs.

The Cloudflare Pages API and assistant model Worker were also deployed from the
reviewed security-fix commit on 2026-09-13. Production health and anonymous/browser
API rejection checks passed. The rolled Cloudflare token retains its existing
Pages/R2 permissions and no-expiration setting; unrelated tokens were untouched.
The new Google secret is stored in both Supabase's Google provider and ignored
local Terraform variables. Client ID, redirect URI and OAuth scopes are unchanged.
The browser-to-Supabase login was verified from the existing user's updated
sign-in timestamp, with user and profile counts unchanged. Native callback
handoff and the mobile PKCE/session flow still require real-device verification.

For future rotations:

1. Replace the Supabase personal access token through the account dashboard and
   save it directly into ignored deployment configuration. Do not paste it into chat.
   The current repair token is limited to this project. It does not include API key
   or billing reads used by the provider's full refresh, nor broader project writes
   required by some Auth updates. Do not broaden it to all-account access to work
   around those restrictions. Use a separately reviewed permission change or the
   dashboard for those operations.
2. Recreate the targeted rotation plan with a valid token, inspect it, and apply:

   ```sh
   mkdir -p .secrets
   chmod 700 .secrets
   terraform -chdir=infrastructure/terraform plan \
     -replace=random_password.database -target=supabase_project.app \
     -out=../../.secrets/database-password-rotation.tfplan
   terraform -chdir=infrastructure/terraform apply \
     ../../.secrets/database-password-rotation.tfplan
   ```

   The project must be updated in place, with only the password generator
   replaced. Stop if a plan would recreate the Supabase project. Terraform keeps
   the new password in its protected local state; keep this state private.
3. Replace the Cloudflare token and Google OAuth client secret in their provider
   consoles and deployment configuration. Update Supabase's Google provider with
   the new Google secret before revoking the old secret, then verify sign-in.
   Revoke superseded management tokens after all known consumers are updated.
4. Collaborators must replace their old clones or carefully rebase onto the
   cleaned history. Do not merge the old history back into `main`. No remote
   tags or other branches existed when the cleanup was published; unrelated
   local stashes and Codex checkpoint references were preserved.

## Android signing

`python3 scripts/prepare_android_signing.py` creates a private upload keystore
once, with random passwords. It refuses to overwrite existing signing material.
Back up `.secrets/android-upload.jks` and `android/key.properties` securely before
the first upload. Both files are ignored. Never use the debug key for a beta.

CI or another machine can supply `ANDROID_KEYSTORE_PATH`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`
instead. Relative keystore paths are resolved from `android/`.

```sh
npm run check:beta -- --platform=android --config=.env.json
flutter build appbundle --release --dart-define-from-file=.env.json
```

The signed bundle was successfully built on 2026-09-12 at
`build/app/outputs/bundle/release/app-release.aab` (58.7 MB). Missing Android
command-line tools on this Mac were installed from the official download and
verified against its published SHA-256 before the successful build.
Release Gradle tasks fail if signing material is missing. Debug builds do not
require it. Increment the build number before uploading subsequent bundles.

For a directly installable APK for Android testing, run from the repository root:

```sh
flutter build apk --release --dart-define-from-file=.env.json --build-number=2
```

The output is `build/app/outputs/flutter-apk/app-release.apk`. On 2026-09-13,
version **1.0.0 (2)** was built and copied to
`build/releases/Gather2Gether-1.0.0-build2.apk` for sharing (89.9 MB).
This universal APK contains ARM64, ARM32 and x86_64 libraries and requires
Android 7.0/API 24 or newer. APK signature verification passed, the certificate
matches the existing release keystore, and ZIP page alignment verification
passed. A SHA-256 sidecar and build metadata are in the same directory.
These checks do not replace installing and testing on a physical Android phone.

Share the APK file through a file download link or directly with testers. They
can open it on Android and allow installation from that source when prompted.
APK files cannot be installed on iOS. Keep the existing signing key for updates
and use a higher build number for the next release. Share only the APK, never
the signing material or private deployment configuration. Remote push is still
disabled and Firebase remains in `gather2gether-5a108`; the proposed Firebase
project consolidation was cancelled by the owner.

## Apple sign-in and signing

Apple account setup is pending. Enroll in Apple Developer, register
`com.gather2gether.gather2gether`, and configure Sign in with Apple. The app uses
Supabase's browser OAuth flow and its existing secure PKCE callback handling.

Create a Services ID, configure the Supabase callback shown in the Auth dashboard,
and create the Apple client-secret JWT. Set `apple_oauth_enabled`,
`apple_oauth_client_id` and `apple_oauth_client_secret` in ignored Terraform vars.
Apply the Auth configuration, then set `APPLE_SIGN_IN_ENABLED: true` in the mobile
JSON. The Apple button is shown on iOS alongside Google only when this is enabled.
Rotate the Apple client-secret JWT before expiry (maximum six months).

Copy `ios/Flutter/Signing.xcconfig.example` to `Signing.xcconfig`, select your
Apple team, and configure App Store Connect/provisioning. If remote push is
enabled, uncomment `CODE_SIGN_ENTITLEMENTS`, enable Push Notifications for the
App ID, and upload an APNs authentication key in Firebase. The entitlement uses
development for Debug and production for Release/Profile.

```sh
npm run check:beta -- --platform=ios --config=.env.json
flutter build ipa --release --dart-define-from-file=.env.json
```

Test new and returning Apple accounts, Hide My Email, cancellation, account
deletion and provider-token revocation before submitting the iOS beta. Apple
provider-token revocation needs an explicit end-to-end check; the database
account-deletion RPC alone does not prove it happened at Apple.

## Firebase (optional remote notifications)

Firebase project `gather2gether-5a108` (project/sender number `52184746647`)
is created under the selected personal account, `ngkokteng00@gmail.com`, on the
Spark plan. Android and iOS apps are registered for the bundle/package ID below.
FCM HTTP v1 is enabled. Analytics was left disabled. Do not use the connected
work Google Cloud account.

Both apps use `com.gather2gether.gather2gether`. Their public app IDs, API keys
and sender ID are saved in the ignored `.env.json`; the dispatcher project ID
is set in `wrangler.push.jsonc`. API keys retain Firebase's default API
restrictions; application restrictions still need validation with signed builds.

Android generates its native Firebase string resources from the same Dart
defines when remote push is enabled, so notifications can start a closed app.
No separate Google Services Gradle plugin/config file is needed. FCM automatic
token generation is disabled in both native manifests; signed-in registration
enables it at runtime. iOS initializes Firebase using the explicit Dart options.

The dedicated sender `gather2gether-push@gather2gether-5a108.iam.gserviceaccount.com`
has only `roles/firebasecloudmessaging.admin` in this project. Its one RSA key
was generated locally, with only the public certificate uploaded to Google.
The key expires on **2027-09-12**; rotate it before that date. Private material
is stored in `.secrets/firebase-push-service-account.json` and
`.secrets/firebase-push-private-key.pem` with mode 600. Never place sender
credentials in the mobile JSON or Git.

The push Worker is deployed to the existing personal Cloudflare account with
`REMOTE_PUSH_ENABLED=false`. Its `FIREBASE_SERVICE_ACCOUNT_EMAIL` and
`FIREBASE_PRIVATE_KEY` secrets are configured. Google authentication and an
FCM `validate_only` request succeeded; no message was sent. The remaining
server requirement is `SUPABASE_SERVICE_ROLE_KEY`, which is not available in
the local configuration. Supply the existing server key through the Supabase
dashboard and store it only as a Worker secret before enabling delivery.

Set `REMOTE_PUSH_ENABLED` to `true` in the app and dispatcher only when the
provider, app registration and Worker secrets are configured. Deploy the push
Worker and rebuild the app. Without this flag, Firebase is not initialized and
the dispatcher does not claim or send push rows. Local reminders and in-app
notifications remain available.

On iOS, APNs setup and physical-device testing remain required even after the
Firebase project exists. Verify notifications with the app open, backgrounded
and terminated; test taps, denied permissions, quiet hours and sign-out cleanup.

## Public information and feedback

Review `workers/public-information.js`, including provider and retention details.
Set the actual `APP_OPERATOR_NAME` and `SUPPORT_EMAIL` in the Pages `vars` in
`wrangler.jsonc`. These are public values. They remain unset until the owner is
ready to supply public contact details; do not invent them or use a personal
account email as a public support address without permission.

The app links to `/privacy`, `/terms`, `/account-deletion`, and `/support` before
sign-in and from Settings → About. Routes return 503 until the contact details
are configured. Deploy Pages after those details and text are reviewed, then run:

```sh
npm run check:production -- --beta
```

This verifies health, anonymous/browser API rejection and public page availability.
It does not verify database migrations, signed-in flows or remote push delivery.
Use the beta distribution platform's feedback/crash reports and configure a
monitored support inbox and backend alerts before inviting external testers.

## Release verification

On 2026-09-12, all 178 Flutter tests and 127 backend tests passed. Flutter
analysis, Terraform validation, the iOS simulator build, and all three Cloudflare
dry-run builds passed. The Android bundle signature was verified; an additional
Android build confirmed all native Firebase resource values match the app config. The live API health
and anonymous/browser rejection checks passed without creating test users.
All 26 migrations and all 8 SQL regression suites passed in a disposable
PostgreSQL 17 container using the official Supabase Auth schema. The two native
map integration tests also passed on the iPhone 17 simulator.
Those initial checks did not resolve the credential incident. The subsequent
rotations and production deployments above address the recorded credentials and
backend fixes; the remaining external setup and device checks still apply.


Run `flutter analyze`, `flutter test`, `npm run test:edge`, `npm run check:edge`,
`npm run check:assistant`, `npm run check:push`, and the platform beta check.
Run `npm run test:db` with Docker running to apply every migration and SQL
regression in a disposable database. The runner downloads pinned official
Supabase images as needed, initializes Auth, and removes its container afterward.
The database has no external network, published ports or persistent data. It
accepts no live database connection string. CI runs the same check.
Do not use the old live smoke script to create test users during this setup.

On a fresh installation on each target platform, check sign-in, onboarding,
discovery, event creation/join/cancel, private audiences, invite links, denied
location/notification permissions, offline reads, and account deletion. A passing
build or health endpoint cannot replace these checks.

References: [Flutter Android release](https://docs.flutter.dev/deployment/android),
[Supabase Apple OAuth](https://supabase.com/docs/guides/auth/social-login/auth-apple),
[Firebase Flutter messaging](https://firebase.google.com/docs/cloud-messaging/flutter/get-started).
