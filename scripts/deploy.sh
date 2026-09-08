#!/usr/bin/env bash
#
# Build, ship, restart, verify. Read this before running it — the plan's Day 3
# rule is that deployment scripts are asked for, read, and then run by hand.
#
# The order matters: the jar is built locally, baked into an arm64 image locally,
# and pushed to ECR. Nothing is compiled on the instance, which is the whole
# reason a 1 GB t4g.small is enough.
#
# Usage:  scripts/deploy.sh
#         scripts/deploy.sh --skip-build     # reuse the jar already in build/libs
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$REPO_ROOT/infra"

SKIP_BUILD=0
[[ "${1:-}" == "--skip-build" ]] && SKIP_BUILD=1

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }

# --- preflight ---------------------------------------------------------------

command -v docker >/dev/null || fail "docker not found"
command -v aws >/dev/null || fail "aws cli not found"
command -v terraform >/dev/null || fail "terraform not found"

# Show which identity this is about to act as, rather than just checking that
# some identity exists. A valid session in the wrong account looks identical to
# a valid session in the right one until the resources show up.
#
# Note: `aws login` and `aws sso login` are different mechanisms. An IAM
# Identity Center profile needs the latter:
#   aws sso login --profile <name> && export AWS_PROFILE=<name>
CALLER="$(aws sts get-caller-identity --query '[Account,Arn]' --output text 2>/dev/null)" \
  || fail "AWS session is not valid. For an IAM Identity Center profile: aws sso login --profile <name>"

echo "  profile    : ${AWS_PROFILE:-default}"
echo "  account    : $(cut -f1 <<<"$CALLER")"
echo "  identity   : $(cut -f2 <<<"$CALLER")"

[[ -f "$INFRA_DIR/terraform.tfstate" ]] \
  || fail "No terraform.tfstate in infra/. Run 'terraform apply' there before deploying."

step "Reading Terraform outputs"
tf_out() { terraform -chdir="$INFRA_DIR" output -raw "$1" 2>/dev/null; }

ECR_URL="$(tf_out ecr_repository_url)" || fail "could not read ecr_repository_url"
REGION="$(tf_out aws_region)"
INSTANCE_ID="$(tf_out instance_id)"
APP_URL="$(tf_out app_url)"
IMAGE="$ECR_URL:latest"

echo "  repository : $ECR_URL"
echo "  instance   : $INSTANCE_ID  ($REGION)"

# --- build -------------------------------------------------------------------

if [[ $SKIP_BUILD -eq 0 ]]; then
  step "Building the jar (ktlint, detekt, tests, Kover all run here)"
  (cd "$REPO_ROOT" && ./gradlew build)
else
  echo "  skipping Gradle build at your request"
fi

ls "$REPO_ROOT"/build/libs/*.jar >/dev/null 2>&1 \
  || fail "no jar in build/libs — run without --skip-build"

step "Building the linux/arm64 image"
# --load then push, rather than --push directly: the default docker driver
# cannot export a manifest list, and this two-step works on every driver. A JVM
# jar is architecture-neutral, so this is a layer copy, not an emulated build.
docker buildx build \
  --platform linux/arm64 \
  --tag "$IMAGE" \
  --load \
  "$REPO_ROOT"

# --- ship --------------------------------------------------------------------

step "Pushing to ECR"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "${ECR_URL%%/*}"
docker push "$IMAGE"

# --- restart -----------------------------------------------------------------

step "Restarting catalog.service on the instance"
# The systemd unit re-authenticates and re-pulls on every start, so a plain
# restart is a complete redeploy. Sent over SSM: no SSH, no open port 22.
CMD_ID="$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment "catalog redeploy" \
  --parameters 'commands=["systemctl restart catalog","sleep 3","systemctl is-active catalog"]' \
  --query 'Command.CommandId' --output text)"

echo "  command id: $CMD_ID"
aws ssm wait command-executed \
  --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" 2>/dev/null || true

STATUS="$(aws ssm get-command-invocation \
  --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query Status --output text)"
echo "  ssm status: $STATUS"

if [[ "$STATUS" != "Success" ]]; then
  aws ssm get-command-invocation --region "$REGION" \
    --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query 'StandardErrorContent' --output text >&2
  fail "restart failed on the instance — see stderr above, then 'aws ssm start-session --target $INSTANCE_ID' and 'journalctl -u catalog -n 50'"
fi

# --- verify ------------------------------------------------------------------

step "Waiting for the service to answer"
# Verify rather than assert. The JVM needs a moment on a t4g.small, so poll.
for i in $(seq 1 30); do
  if curl -fsS --max-time 5 "$APP_URL" >/dev/null 2>&1; then
    echo
    echo "  $APP_URL"
    curl -sS "$APP_URL"; echo
    echo
    printf '\033[1;32mDeployed and reachable.\033[0m\n'
    exit 0
  fi
  printf '  attempt %d/30\r' "$i"
  sleep 5
done

fail "service did not answer at $APP_URL within 150s. Check 'aws ssm start-session --target $INSTANCE_ID' then 'journalctl -u catalog -n 50'"
