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
