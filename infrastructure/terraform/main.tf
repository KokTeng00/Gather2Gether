resource "random_password" "database" {
  length           = 32
  special          = true
  override_special = "!#$%&*+-=?@"
}

resource "supabase_project" "app" {
  organization_id   = var.supabase_organization_id
  name              = var.app_name
  database_password = random_password.database.result
  region            = var.supabase_region

  lifecycle {
    prevent_destroy = true
  }
}

resource "supabase_settings" "app" {
  project_ref = supabase_project.app.id

  api = jsonencode({
    db_schema            = "public,storage,graphql_public"
    db_extra_search_path = "public,extensions"
    max_rows             = 1000
  })
}

resource "cloudflare_pages_project" "web" {
  account_id        = var.cloudflare_account_id
  name              = var.app_name
  production_branch = var.production_branch

  lifecycle {
    # Wrangler owns deployment artifacts and Pages Functions runtime config.
    # Terraform owns the project identity and production branch.
    ignore_changes = [deployment_configs]
  }
}
