provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Repo      = "dcltdw/kotlin-ramp-up"
    }
  }
}

data "aws_caller_identity" "current" {}

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
