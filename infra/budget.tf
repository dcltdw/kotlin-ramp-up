# The guardrail the plan asks for on Day 1, before anything is running.
#
# Two notifications rather than one, because they answer different questions:
# ACTUAL at 80% says "you have already spent $20 this month", while FORECASTED
# at 100% says "at this rate you will pass $25" — which is the one that arrives
# early enough to act on. An alert that only fires after the money is gone is a
# receipt, not a guardrail.
#
# Note this budget covers the whole account, not just this project. That is
# intentional: the plan's $100 cap is an account-level concern, and a
# tag-filtered budget would miss anything created outside this Terraform.
resource "aws_budgets_budget" "monthly" {
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
