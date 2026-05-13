variable "compartment_id" {
  type        = string
  description = "OCI compartment OCID (used as budget target)"
}

variable "budget_amount" {
  type        = number
  description = "Monthly budget limit in USD"
}

variable "budget_alert_email" {
  type        = string
  description = "Email address to receive budget alerts"
}
