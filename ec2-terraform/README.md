# Kiro Crew on EC2(Terraform)

`kirocrew cloud launch` の代わりに Terraform で同等の環境を作る。受信ポートは開けず、接続は SSM だけ。

```bash
terraform init
terraform apply -var profile=<aws-profile>
# 任意: API キーを SSM SecureString に置いてから
#   aws ssm put-parameter --name /kiro/crew/api-key --type SecureString --value ksk_...
#   terraform apply -var kiro_api_key_parameter=/kiro/crew/api-key
```

起動後:

1. `terraform output -raw ssm_session` でシェルに入り、`sudo -iu crew` → `kiro-cli login --use-device-flow`(API キーを置かない場合)
2. `sudo -iu crew kirocrew token --ttl 2h` でダッシュボードのリンクを発行
3. `terraform output -raw dashboard_port_forward` を手元で実行し、ブラウザで `http://localhost:5476/?token=...` を開く

片付けは `terraform destroy`。
