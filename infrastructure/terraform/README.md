# Terraform infrastructure

This module creates and manages:

- one dedicated Supabase project with a generated database password;
- constrained Supabase API settings;
- a private, Western Europe R2 bucket for profile and community JPEG media;
- an R2 lifecycle rule that removes abandoned `staging/` uploads after 24 hours;
- one Cloudflare Pages project for the Flutter web build and Pages Functions API.

It intentionally does not manage the PostgreSQL schema. Apply the versioned SQL
under `supabase/migrations/` with the Supabase CLI after `terraform apply`.

Terraform creates the Pages project. `wrangler pages deploy` publishes both the
Flutter artifact and the root `/functions` directory to that project. The
checked-in Worker variables are public identifiers; deployment credentials stay
outside the repository.

Apply Terraform before deploying Pages Functions so the
`${app_name}-${environment}-user-media` bucket exists for the checked-in
`USER_MEDIA` binding. Then apply the SQL migrations before deploying the edge
API; the media routes depend on the new permission-checked RPCs. The bucket has
no public domain, and objects are served only through authenticated API routes.

The Supabase Auth settings update disables email/password authentication and
manages the mobile callback allow-list and Google provider. The Google client
secret is a sensitive Terraform input and is still stored in Terraform state,
so the remote state backend must be encrypted and access-restricted. Supabase's
Terraform provider performs partial settings updates, preserving unmanaged Auth
fields.

Wrangler owns Pages deployment artifacts and Functions runtime configuration;
Terraform ignores `deployment_configs` to prevent the two tools from fighting
over Cloudflare-generated defaults. Terraform continues to own the Pages project
identity and production branch.

Real `terraform.tfvars`, Terraform state, and `.terraform/` are ignored. Keep
state in an encrypted remote backend for any shared or CI deployment.
