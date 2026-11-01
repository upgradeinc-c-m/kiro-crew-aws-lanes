output "instance_id" {
  value = aws_instance.crew.id
}

output "ssm_session" {
  description = "シェルで入る(ログイン操作や doctor の確認に)"
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.crew.id}"
}

output "dashboard_port_forward" {
  description = "手元の 5476 をインスタンスの 5476 に転送してからブラウザで開く"
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.crew.id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"5476\"],\"localPortNumber\":[\"5476\"]}'"
}
