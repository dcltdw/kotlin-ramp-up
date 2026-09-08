# A small dedicated VPC rather than the default one. Two reasons, both about
# teardown: `terraform destroy` removes everything here completely, and the
# default VPC's contents vary per account so a destroy against it is never
# provably clean.
#
# There is deliberately no NAT Gateway. The plan calls it out as the most common
# way a budget like this evaporates unnoticed — about $32/month plus data
# charges, which is more than the instance. A public subnet with a security
# group is the correct shape for a personal project, and the instance reaches
# ECR and SSM over the internet gateway.

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = local.name }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = local.name }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "app" {
  name = "${local.name}-app"

  # ASCII only, and deliberately so: EC2 rejects CreateSecurityGroup outright if
  # GroupDescription contains anything beyond ASCII, with "Character sets beyond
  # ASCII are not supported". An em dash here failed the first apply after 13
  # other resources had already been created. Variable descriptions are
  # Terraform-local and unaffected; this one is sent to the AWS API.
  description = "App port inbound; all egress. No SSH - access is via SSM Session Manager."
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-app" }
}

resource "aws_vpc_security_group_ingress_rule" "app" {
  for_each = toset(var.app_ingress_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "Catalog service HTTP"
  cidr_ipv4         = each.value
  from_port         = var.app_port
  to_port           = var.app_port
  ip_protocol       = "tcp"
}

# Note what is absent: no rule for port 22. SSM Session Manager works purely
# outbound, so the instance needs no inbound SSH at all and there is no key pair
# anywhere in this configuration.

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.app.id
  description       = "ECR pulls, SSM control channel, dnf updates"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
