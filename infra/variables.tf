variable "aws_region" {
  description = "Region for every resource. Budgets is a global service but its API only answers in us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = <<-EOT
    Named profile to authenticate with. Leave null to use the standard
    resolution chain (AWS_PROFILE, then `default`).

    Set it when `default` is not the account you want. On this machine the
    admin profile is an IAM Identity Center one:

      aws sso login --profile AdministratorAccess-675789572470

    Note that `aws login` is a different mechanism — console credentials for
    local development — and will not authenticate an SSO profile.
  EOT
  type        = string
  default     = null
}

variable "expected_account_id" {
  description = <<-EOT
    Refuse to apply unless the caller is this account. Leave null to skip the
    check.

    Worth setting when the target account is shared with other projects: a
    misresolved profile otherwise creates a second copy of everything in the
    wrong account, and the only symptom is a surprising bill.
  EOT
  type        = string
  default     = null
}

variable "project" {
  description = "Name prefix and Project tag on every resource, so a teardown can be verified by tag."
  type        = string
  default     = "catalog-personalization"
}

variable "instance_type" {
  description = "Graviton. The plan is explicit that t3.micro is too small for a JVM and that this must be t4g.small."
  type        = string
  default     = "t4g.small"

  validation {
    condition     = startswith(var.instance_type, "t4g.")
    error_message = "The image is built for linux/arm64, so the instance must be Graviton (t4g.*)."
  }
}

variable "app_port" {
  description = "Port the container publishes. Must match server.port in application.yml."
  type        = number
  default     = 8080
}

variable "app_ingress_cidrs" {
  description = <<-EOT
    Who may reach the app port. Defaults to the whole internet because "deployed
    and reachable" is Day 1's acceptance criterion and the only routes served are
    /api/ping and actuator health. Narrow it to your own /32 if you would rather
    it not be public.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "budget_limit_usd" {
  description = "Monthly cost budget. The plan sets this at $25 against a $100 cap."
  type        = string
  default     = "25"
}

variable "budget_alert_email" {
  description = <<-EOT
    Where budget alerts go. No default on purpose: an unmonitored budget alert is
    the same as no budget alert. Set it in terraform.tfvars, which is gitignored.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be a single valid email address."
  }
}
