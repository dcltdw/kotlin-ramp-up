data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${local.name}-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "${local.name}-instance" }
}

# This is what replaces an SSH key pair. The SSM agent ships in Amazon Linux
# 2023 already running; all it needs is permission to register and hold open a
# control channel, and then `aws ssm start-session` works with no inbound port.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Pull-only, and scoped to this one repository. The instance never pushes —
# pushing is the laptop's job, per the plan's "do not compile on the box".
data "aws_iam_policy_document" "ecr_pull" {
  statement {
    sid = "AuthToECR"
    # GetAuthorizationToken is account-wide by design: it takes no resource.
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullThisRepoOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "ecr_pull" {
  name   = "${local.name}-ecr-pull"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.ecr_pull.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${local.name}-instance"
  role = aws_iam_role.instance.name

  tags = { Name = "${local.name}-instance" }
}
