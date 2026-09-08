#!/usr/bin/env bash
#
# Destroy everything this project created, then prove it is gone.
#
# Written on Day 1, before anything was running, because that is the only time
# it gets written calmly. The verification step at the end is the part that
# matters: `terraform destroy` reporting success only means Terraform is happy
# with its own state file, not that the account is clean.
#
# Usage:  scripts/teardown.sh            # prompts before destroying
#         scripts/teardown.sh --yes      # no prompt
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$REPO_ROOT/infra"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }

command -v terraform >/dev/null || fail "terraform not found"
command -v aws >/dev/null || fail "aws cli not found"

# Print the identity before destroying anything. This is the one script where
# acting on the wrong account would be actively destructive.
#
# `aws login` and `aws sso login` are different mechanisms; an IAM Identity
# Center profile needs the latter.
CALLER="$(aws sts get-caller-identity --query '[Account,Arn]' --output text 2>/dev/null)" \
  || fail "AWS session is not valid. For an IAM Identity Center profile: aws sso login --profile <name>"

printf 'Destroying as:\n  profile  : %s\n  account  : %s\n  identity : %s\n' \
  "${AWS_PROFILE:-default}" "$(cut -f1 <<<"$CALLER")" "$(cut -f2 <<<"$CALLER")"

[[ -f "$INFRA_DIR/terraform.tfstate" ]] \
  || fail "No terraform.tfstate in infra/ — nothing to destroy from here. If resources exist anyway, see the 'Lost state' section of infra/README.md."

PROJECT="$(terraform -chdir="$INFRA_DIR" output -raw project 2>/dev/null || echo catalog-personalization)"
REGION="$(terraform -chdir="$INFRA_DIR" output -raw aws_region 2>/dev/null || echo us-east-1)"

step "What will be destroyed"
terraform -chdir="$INFRA_DIR" plan -destroy -no-color | tail -30

if [[ "${1:-}" != "--yes" ]]; then
  echo
  read -r -p "Destroy all of the above? Type 'destroy' to confirm: " reply
  [[ "$reply" == "destroy" ]] || fail "aborted; nothing was changed"
fi

step "Destroying"
# The ECR repository has force_delete = true, so images do not block this.
terraform -chdir="$INFRA_DIR" destroy -auto-approve

# --- verify ------------------------------------------------------------------

step "Verifying the account is actually clean"
# Independent of Terraform state: ask the tagging API what still carries our
# Project tag. Every resource in infra/ gets it via provider default_tags.
LEFTOVERS="$(aws resourcegroupstaggingapi get-resources \
  --region "$REGION" \
  --tag-filters "Key=Project,Values=$PROJECT" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output text 2>/dev/null || echo "QUERY_FAILED")"

if [[ "$LEFTOVERS" == "QUERY_FAILED" ]]; then
  printf '\033[1;33mCould not query the tagging API — verify by hand in the console.\033[0m\n'
elif [[ -z "$LEFTOVERS" ]]; then
  printf '\033[1;32mNothing left tagged Project=%s in %s.\033[0m\n' "$PROJECT" "$REGION"
else
  printf '\033[1;31mStill present:\033[0m\n'
  # --output text returns tab-separated ARNs; one per line, without letting the
  # shell glob or split them.
  tr '\t' '\n' <<<"$LEFTOVERS" | sed 's/^/  /'
  fail "teardown incomplete — the ARNs above still exist"
fi

# The budget is a global resource and does not appear in the regional tagging
# query above, so check it separately.
step "Checking the budget is gone"
ACCT="$(aws sts get-caller-identity --query Account --output text)"
if aws budgets describe-budget --account-id "$ACCT" \
     --budget-name "$PROJECT-monthly" >/dev/null 2>&1; then
  fail "budget '$PROJECT-monthly' still exists"
else
  printf '\033[1;32mBudget removed.\033[0m\n'
fi

step "Reminder: what teardown does NOT touch"
cat <<'NOTE'
  - The Contentful space. It is free-tier and holds the hand-built content
    model; deleting it would cost real work to rebuild.
  - Your local terraform.tfstate, now describing nothing. Safe to keep.
  - Local docker images. `docker image prune` if you want the disk back.
NOTE
