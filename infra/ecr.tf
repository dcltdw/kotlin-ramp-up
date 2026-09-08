resource "aws_ecr_repository" "app" {
  name                 = local.name
  image_tag_mutability = "MUTABLE" # :latest is re-pushed on every redeploy

  image_scanning_configuration {
    scan_on_push = true
  }

  # Without this, `terraform destroy` fails on a repository that still holds
  # images — which it always will — and the teardown stops half-finished. The
  # whole point of writing the teardown on Day 1 is that it works unattended.
  force_delete = true

  tags = { Name = local.name }
}

# Keep only the last few images. Storage is $0.10/GB-month so this is about
# tidiness rather than cost, but an unbounded repo after a week of Day 5
# redeploys is needless.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 5 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
