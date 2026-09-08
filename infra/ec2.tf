resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  # No key_name. Access is SSM Session Manager; there is no key pair to manage,
  # lose, or rotate.

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    region           = var.aws_region
    image_uri        = local.image_uri
    app_port         = var.app_port
    container_memory = var.container_memory
  })

  # user_data changes should rebuild the box rather than silently do nothing.
  # Without this the attribute updates in state and the running instance keeps
  # its original boot script, which is a genuinely confusing failure.
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20 # gp3; 8 GB fills up fast once images accumulate
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  tags = { Name = local.name }

  # The instance needs the repository to exist before user_data renders a URI
  # for it, and the pull permission attached before the unit first runs.
  depends_on = [
    aws_ecr_repository.app,
    aws_iam_role_policy.ecr_pull,
    aws_iam_role_policy_attachment.ssm,
  ]
}
