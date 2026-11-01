# Kiro Crew を 1 台の EC2(Amazon Linux 2023)で動かす最小構成。
# - 受信ポートは開けない(SSH も不可)。接続は SSM Session Manager のポートフォワードだけ。
# - user-data で kiro-cli と kirocrew を入れ、systemd サービスとして常駐させる。
# - 素の Linux なので user namespace が使え、Crew のサンドボックスがそのまま効く。

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-${var.arch == "arm64" ? "arm64" : "x86_64"}"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_vpc" "default" {
  count   = var.subnet_id == null ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.subnet_id == null ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

data "aws_subnet" "selected" {
  id = var.subnet_id != null ? var.subnet_id : sort(data.aws_subnets.default[0].ids)[0]
}

# ---- IAM: SSM 接続と(任意の)API キー取得だけ ----
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "api_key" {
  count = var.kiro_api_key_parameter == null ? 0 : 1
  statement {
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.kiro_api_key_parameter}"]
  }
}

resource "aws_iam_role_policy" "api_key" {
  count  = var.kiro_api_key_parameter == null ? 0 : 1
  name   = "${var.name}-read-api-key"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.api_key[0].json
}

data "aws_caller_identity" "current" {}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-instance-profile"
  role = aws_iam_role.instance.name
}

# ---- SG: 受信なし、送信のみ ----
resource "aws_security_group" "crew" {
  name        = "${var.name}-sg"
  description = "Kiro Crew: no ingress, egress only (SSM)"
  vpc_id      = data.aws_subnet.selected.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---- EC2 ----
resource "aws_instance" "crew" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = [aws_security_group.crew.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  associate_public_ip_address = true # NAT が無い検証用。private subnet + NAT なら false

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    region        = var.region
    api_key_param = var.kiro_api_key_parameter == null ? "" : var.kiro_api_key_parameter
    crew_channel  = var.crew_channel
  })
  user_data_replace_on_change = true

  tags = { Name = var.name }
}
