variable "region" {
  description = "EC2 を起動するリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "profile" {
  description = "AWS CLI のプロファイル名(null なら環境変数)"
  type        = string
  default     = null
}

variable "name" {
  description = "リソース名の接頭辞"
  type        = string
  default     = "kiro-crew"
}

variable "instance_type" {
  description = "インスタンスタイプ。Crew の目安は RAM 10GB 以上(16GB 推奨)"
  type        = string
  default     = "m7g.large"
}

variable "arch" {
  description = "AMI のアーキテクチャ(arm64 / x86_64)。instance_type と合わせる"
  type        = string
  default     = "arm64"
}

variable "root_volume_gb" {
  description = "ルートボリュームのサイズ(GB)。埋め込みモデル 610MB と KAS エンジンを含む"
  type        = number
  default     = 40
}

variable "subnet_id" {
  description = "起動するサブネット。null ならデフォルト VPC の最初のサブネット。インターネットへの egress が必要"
  type        = string
  default     = null
}

variable "kiro_api_key_parameter" {
  description = "KIRO_API_KEY を入れた SSM SecureString パラメータ名。null なら設定しない(後で kiro-cli login を行う)"
  type        = string
  default     = null
}

variable "crew_channel" {
  description = "Kiro Crew のインストールチャネル(stable / insider / nightly)"
  type        = string
  default     = "stable"
}
