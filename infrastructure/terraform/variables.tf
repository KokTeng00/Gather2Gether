variable "app_name" {
  description = "DNS-safe application and Cloudflare Pages project name."
  type        = string
  default     = "gather2gether"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,56}[a-z0-9]$", var.app_name))
    error_message = "app_name must be a lowercase DNS-safe name between 2 and 58 characters."
  }
}

variable "environment" {
  description = "Deployment environment label."
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "environment must be development, staging, or production."
  }
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Cloudflare Pages and Workers R2 Storage write access."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account identifier."
  type        = string
}

variable "supabase_access_token" {
  description = "Supabase personal access token with project admin access."
  type        = string
  sensitive   = true
}

variable "supabase_organization_id" {
  description = "Supabase organization slug or ID containing the project."
  type        = string
}

variable "supabase_region" {
  description = "Existing Supabase project's AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "google_oauth_client_id" {
  description = "Google Auth Platform Web application OAuth client ID used by Supabase Auth."
  type        = string

  validation {
    condition     = length(trimspace(var.google_oauth_client_id)) > 0
    error_message = "google_oauth_client_id must not be empty."
  }
}

variable "google_oauth_client_secret" {
  description = "Google Auth Platform Web application OAuth client secret used only by Supabase Auth."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.google_oauth_client_secret)) > 0
    error_message = "google_oauth_client_secret must not be empty."
  }
}

variable "production_branch" {
  description = "Branch label used for Cloudflare Pages production deployments."
  type        = string
  default     = "main"
}

variable "apple_oauth_enabled" {
  description = "Enable only after configuring Sign in with Apple in Apple Developer."
  type        = bool
  default     = false
}

variable "apple_oauth_client_id" {
  description = "Apple Services ID for the browser OAuth flow through Supabase."
  type        = string
  default     = ""
}

variable "apple_oauth_client_secret" {
  description = "Apple OAuth client-secret JWT; rotate before its six-month expiry."
  type        = string
  sensitive   = true
  default     = ""
}
