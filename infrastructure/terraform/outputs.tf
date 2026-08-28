output "supabase_project_ref" {
  description = "Supabase project reference used by the application."
  value       = supabase_project.app.id
}

output "supabase_url" {
  description = "Public Supabase API URL."
  value       = "https://${supabase_project.app.id}.supabase.co"
}

output "supabase_db_password" {
  description = "Generated database password used only by deployment tooling."
  value       = random_password.database.result
  sensitive   = true
}

output "cloudflare_pages_subdomain" {
  description = "Cloudflare Pages hostname for Flutter web deployments."
  value       = cloudflare_pages_project.web.subdomain
}

output "cloudflare_edge_api_url" {
  description = "Public Cloudflare Pages Functions API base URL."
  value       = "https://${cloudflare_pages_project.web.subdomain}/api/v1"
}
