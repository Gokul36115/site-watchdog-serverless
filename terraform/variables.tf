variable "sites" {
  description = "Websites to check"
  type        = list(string)
}

variable "telegram_chat_id" {
  description = "My Telegram chat ID (where alerts go)"
  type        = string
}

variable "token_param_name" {
  description = "SSM parameter that holds the bot token (created by hand, not by Terraform)"
  type        = string
  default     = "/site-watchdog/telegram-token"
}

variable "schedule" {
  description = "How often the check runs"
  type        = string
  default     = "rate(15 minutes)"
}

variable "auth0_domain" {
  description = "My Auth0 tenant domain (the token issuer)"
  type        = string
}

variable "auth0_audience" {
  description = "Identifier of the Auth0 API; tokens must be issued for this audience"
  type        = string
}

variable "dashboard_origin" {
  description = "Where the dashboard page is hosted (allowed to call the API from a browser)"
  type        = string
}
