resource "oci_budget_budget" "this" {
  compartment_id         = var.compartment_id
  amount                 = var.budget_amount
  reset_period           = "MONTHLY"
  display_name           = "oci-free-k8s-monthly-budget"
  description            = "Monthly budget alert for oci-free-k8s"
  target_type            = "COMPARTMENT"
  targets                = [var.compartment_id]
  processing_period_type = "MONTH"
}

resource "oci_budget_alert_rule" "at_80_percent" {
  budget_id      = oci_budget_budget.this.id
  type           = "ACTUAL"
  threshold      = 80
  threshold_type = "PERCENTAGE"
  display_name   = "alert-80-percent"
  recipients     = var.budget_alert_email
}

resource "oci_budget_alert_rule" "at_100_percent" {
  budget_id      = oci_budget_budget.this.id
  type           = "ACTUAL"
  threshold      = 100
  threshold_type = "PERCENTAGE"
  display_name   = "alert-100-percent"
  recipients     = var.budget_alert_email
}
