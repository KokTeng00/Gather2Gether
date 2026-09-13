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

  # The provider sends partial settings updates. HIBP is intentionally not
  # enabled here because it depends on the Supabase subscription plan.
  auth = jsonencode({
    password_min_length              = 10
    site_url                         = "gather2gether://login-callback"
    uri_allow_list                   = "gather2gether://login-callback"
    external_email_enabled           = false
    external_google_enabled          = true
    external_google_client_id        = var.google_oauth_client_id
    external_google_secret           = var.google_oauth_client_secret
    external_google_skip_nonce_check = false
    external_apple_enabled           = var.apple_oauth_enabled
    external_apple_client_id         = var.apple_oauth_client_id
    external_apple_secret            = var.apple_oauth_client_secret
    external_apple_skip_nonce_check  = false
  })

  lifecycle {
    precondition {
      condition = !var.apple_oauth_enabled || (
        length(trimspace(var.apple_oauth_client_id)) > 0 &&
        length(trimspace(var.apple_oauth_client_secret)) > 0
      )
      error_message = "Apple OAuth requires both the Services ID and an unexpired client-secret JWT."
    }
  }
}

resource "cloudflare_r2_bucket" "user_media" {
  account_id    = var.cloudflare_account_id
  name          = "${var.app_name}-${var.environment}-user-media"
  location      = "weur"
  storage_class = "Standard"
}

resource "cloudflare_r2_bucket_lifecycle" "user_media" {
  account_id  = var.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.user_media.name

  rules = [{
    id = "expire-staging-after-24-hours"
    conditions = {
      prefix = "staging/"
    }
    enabled = true
    delete_objects_transition = {
      condition = {
        max_age = 86400
        type    = "Age"
      }
    }
  }]
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
