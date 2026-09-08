provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Repo      = "dcltdw/kotlin-ramp-up"
    }
  }
}

data "aws_caller_identity" "current" {}

# Fail the plan rather than the bill. If expected_account_id is set and the
# resolved credentials point somewhere else, stop before creating anything — a
# misresolved profile is otherwise silent, and its first symptom is a duplicate
# stack in an account you did not mean to touch.
#
# A precondition rather than a `check` block on purpose: `check` only emits a
# warning and lets the apply proceed, which is useless as a guard. A failed
# precondition fails the plan, and aws_caller_identity is read during plan, so
# nothing is created.
resource "terraform_data" "account_guard" {
  input = data.aws_caller_identity.current.account_id

  lifecycle {
    precondition {
      condition = (
        var.expected_account_id == null ||
        data.aws_caller_identity.current.account_id == var.expected_account_id
      )
      error_message = format(
        "Wrong AWS account: credentials resolve to %s, but expected_account_id is %s. Check AWS_PROFILE, or set aws_profile in terraform.tfvars.",
        data.aws_caller_identity.current.account_id,
        coalesce(var.expected_account_id, "unset"),
      )
    }
  }
}

# Latest Amazon Linux 2023 for arm64, resolved from the SSM public parameter
# rather than a hardcoded AMI id. Hardcoded ids are region-specific and go stale;
# this is the published pointer AWS keeps current.
#
# Note the consequence: a new AL2023 release changes this value, and Terraform
# will then want to replace the instance. That is acceptable here — the instance
# is stateless, and everything worth keeping lives in the image or in Contentful.
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# Only one AZ is used. A single public subnet is all the plan calls for, and a
# second AZ would buy nothing without a load balancer in front.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = var.project

  # Where the instance pulls from. Built here rather than read from the ECR
  # resource so that user_data does not depend on image push order.
  image_uri = "${aws_ecr_repository.app.repository_url}:latest"
}
