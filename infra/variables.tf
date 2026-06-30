variable "yourname" {
  description = "Lowercase suffix for globally unique Azure resource names, e.g. charles."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.yourname))
    error_message = "Use 3-12 lowercase letters/numbers only. ACR names must be globally unique."
  }
}

variable "location" {
  description = "Azure region for the resource group and registries."
  type        = string
  default     = "eastus"
}

variable "expires_on" {
  description = "Human-readable lab cleanup date tag, e.g. 2026-06-29."
  type        = string
  default     = "after-demo"
}

variable "budget_email" {
  description = "Email for Azure Cost Management budget alerts. Leave empty to skip budget creation."
  type        = string
  default     = ""
}

variable "monthly_budget_amount" {
  description = "Monthly lab budget alert amount in USD. Budgets alert; they do not stop Azure billing."
  type        = number
  default     = 5
}

variable "budget_start_date" {
  description = "Budget start date in RFC3339 format; use the first day of the current month."
  type        = string
  default     = "2026-06-01T00:00:00Z"
}

variable "tags" {
  description = "Tags applied to Azure resources."
  type        = map(string)
  default = {
    project    = "container-pipeline"
    managed_by = "terraform"
  }
}
