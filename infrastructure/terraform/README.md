# Terraform infrastructure

This module creates and manages:

- one dedicated Supabase project with a generated database password;
- constrained Supabase API settings;
- one Cloudflare Pages project for the Flutter web build and Pages Functions API.

It intentionally does not manage the PostgreSQL schema. Apply the versioned SQL
under `supabase/migrations/` with the Supabase CLI after `terraform apply`.

Terraform creates the Pages project. `wrangler pages deploy` publishes both the
Flutter artifact and the root `/functions` directory to that project. The
checked-in Worker variables are public identifiers; deployment credentials stay
outside the repository.

Wrangler owns Pages deployment artifacts and Functions runtime configuration;
Terraform ignores `deployment_configs` to prevent the two tools from fighting
over Cloudflare-generated defaults. Terraform continues to own the Pages project
identity and production branch.

Real `terraform.tfvars`, Terraform state, and `.terraform/` are ignored. Keep
state in an encrypted remote backend for any shared or CI deployment.
