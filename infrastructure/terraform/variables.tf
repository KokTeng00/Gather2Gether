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

variable "production_branch" {
  description = "Branch label used for Cloudflare Pages production deployments."
  type        = string
  default     = "main"
}
