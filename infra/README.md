# Infrastructure

Terraform for the Day 1 deploy: one `t4g.small` on a public subnet, running the
arm64 container out of ECR, reachable on port 8080, with a $25 budget alert and
a teardown that verifies itself.

## What this creates

| Resource | Why |
|:--|:--|
| VPC, public subnet, internet gateway, route table | A dedicated VPC so `destroy` is provably complete. **No NAT Gateway** — the plan calls it out as the commonest way this budget would evaporate (~$32/month, more than the instance). |
| Security group | Inbound on the app port only. **No port 22.** |
| ECR repository | Push target for the arm64 image. `force_delete = true`, so images never block a teardown. |
| IAM role + instance profile | `AmazonSSMManagedInstanceCore` for shell access, plus pull-only ECR rights scoped to this one repository. |
| EC2 instance | `t4g.small`, Amazon Linux 2023 arm64, IMDSv2 required, 20 GB encrypted gp3. Runs the container under systemd. |
| Budget | $25/month, alerting at 80% actual and 100% forecasted. |

**No key pair, and no SSH.** Access is SSM Session Manager, so there is no
inbound port 22 and no private key to manage.

## Cost

About **$0.53/day**, so roughly **$2.60 for a five-day sprint**:

| Item | Rate | 5 days |
|:--|--:|--:|
| `t4g.small` on-demand, us-east-1 | ~$0.0168/hr | ~$2.02 |
| Public IPv4 address | $0.005/hr | ~$0.60 |
| gp3 root volume, 20 GB | $0.08/GB-month | ~$0.27 |
| ECR storage | $0.10/GB-month | ~$0.02 |
| **Total** | | **~$2.90** |

Well inside the plan's $100 cap and its "under $50" expectation. The public
IPv4 charge is unavoidable since Feb 2024 — AWS bills every public address,
Elastic or auto-assigned.

**The instance bills while stopped-but-not-terminated** for its EBS volume
only (~$0.05/day). If you are done for more than a day or two, run the teardown
rather than stopping the box.

## Prerequisites

```sh
aws sso login --profile AdministratorAccess-675789572470
export AWS_PROFILE=AdministratorAccess-675789572470
aws sts get-caller-identity            # must succeed, and show the right account

cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars               # set budget_alert_email
```

**`aws login` and `aws sso login` are different mechanisms, and only one works
here.** `aws login` is the newer flow for local development against AWS
Management Console credentials. The admin profile on this machine is an IAM
Identity Center profile (`sso_session = annotated-maps`, account
`675789572470`), which needs `aws sso login`. The `default` profile carries no
role or SSO configuration at all, so an expired-session error from a call with
no `--profile` is about `default`, not about the profile you want.

`terraform.tfvars` is gitignored. The email has no default on purpose: an
unmonitored budget alert is the same as no budget alert.

### If the account is shared with another project

Set `expected_account_id` in `terraform.tfvars`. A precondition then fails the
**plan** if credentials resolve anywhere else, which is the difference between
noticing a misresolved profile and paying for a duplicate stack you did not know
existed.

Note also that the budget in `budget.tf` is **account-wide**, not filtered by
tag — deliberately, because the plan's $100 cap is an account-level concern. In
a shared account it will therefore include the other project's spend. If you
want it scoped to this project only, add a `cost_filter` on the `Project` tag,
and accept that it will then miss anything created outside this Terraform.

## First deploy

```sh
cd infra
terraform init
terraform plan            # read it
terraform apply

cd ..
scripts/deploy.sh         # build, push, restart, verify
```

`terraform apply` does **not** start the service — on first boot no image has
been pushed yet, so starting would produce a crash loop that looks like a real
fault. `user-data` enables the unit and stops there; `scripts/deploy.sh` pushes
the first image and starts it.

Expect `apply` to take 2-3 minutes, and the first `deploy.sh` another 2-4 while
the instance installs Docker and pulls the image.

## Redeploy

```sh
scripts/deploy.sh
```

The systemd unit re-authenticates to ECR and re-pulls `:latest` on every start,
so a restart is a complete redeploy. Nothing needs to change in Terraform, and
the public IP is unaffected.

Day 3 asks for at least two redeploys, and Day 5 for load-test iterations —
this is the loop for both.

## Getting a shell

```sh
aws ssm start-session --target "$(terraform -chdir=infra output -raw instance_id)"
```

Then, on the box:

```sh
sudo systemctl status catalog
sudo journalctl -u catalog -n 100 -f
cat /etc/catalog.env
sudo cat /var/log/cloud-init-output.log   # what user-data actually did
```

## Teardown

```sh
scripts/teardown.sh
```

It plans the destroy, asks for confirmation, destroys, and then **verifies
independently of Terraform state** — querying the resource-tagging API for
anything still carrying `Project=catalog-personalization`, and checking the
budget separately since it is global and does not appear in a regional tag
query. A `destroy` that "succeeded" only means Terraform is content with its own
state file.

It deliberately does not touch the **Contentful space** — free-tier, and it
holds the hand-built content model.

## Two things that will bite

**State is a local file.** `infra/terraform.tfstate` is the only record of what
exists in AWS, and it is gitignored. Consequences:

- Run `apply` and `destroy` from **the primary clone**, never from a
  `.claude/worktrees/` checkout. A worktree gets deleted after its PR merges,
  and the state file goes with it — leaving billable resources with no way to
  destroy them cleanly.
- Back it up before anything drastic: `cp infra/terraform.tfstate{,.bak}`.

**Lost state.** If the state file is gone but resources exist, do not re-apply —
you will get a second copy of everything. Find the strays by tag and either
import them or delete them by hand:

```sh
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=catalog-personalization \
  --query 'ResourceTagMappingList[].ResourceARN' --output text
```

Then terminate the instance, delete the ECR repository, delete the budget, and
delete the VPC last — its dependencies must go first.

## A note on AMI updates

The AMI comes from the AL2023 SSM public parameter, not a hardcoded id, so it is
always current. The consequence: when AWS publishes a new AL2023 release,
`terraform plan` will want to **replace the instance**. That is fine here — the
box is stateless, everything of value lives in the image or in Contentful, and
`deploy.sh` puts it back. Just do not be surprised by it mid-sprint.
