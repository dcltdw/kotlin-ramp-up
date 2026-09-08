terraform {
  # Pinned loosely here and exactly in .terraform.lock.hcl, which is committed.
  # The lock file is the reproducibility mechanism; a tight constraint here just
  # makes provider upgrades noisier without adding safety.
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }

  # Local state, deliberately. An S3 backend plus a lock table is the right
  # answer for a team and pure overhead for a five-day single-operator project.
  # The consequence is that terraform.tfstate is the only record of what exists
  # in AWS — read infra/README.md before running this from anywhere but the
  # primary clone.
}
