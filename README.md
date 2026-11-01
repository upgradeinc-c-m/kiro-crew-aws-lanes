# Kiro Crew を自分の AWS アカウントで動かす(EC2 / Fargate / Lambda MicroVM)

Zenn 記事「Kiro CLIとKiro Crewを改めて入門する」の検証で使った、3 つのレーンのセットアップ一式です。
Kiro Crew 0.11.1 で確認しました。Fargate と MicroVM のレーンは公式には Preview で、`cloud.json` の手書きと provisioner API での起動しかありません。このリポジトリはその手順をスクリプトにしたものです。

| レーン | 何が動くか | サンドボックス | 入口 |
| --- | --- | --- | --- |
| EC2 | 常駐の Gateway | あり(user namespace) | `kirocrew cloud launch` または `ec2-terraform/` |
| Fargate | 使い捨ての crew(ECS タスク 1 つ) | なし(`internal_only` で同意) | `fargate/` |
| Lambda MicroVM | 使い捨ての crew(Firecracker VM 1 つ) | なし(VM 境界に依存) | `microvm/` |

## 前提

- 手元(ハブ)に Kiro Crew 0.11.x をインストールし、`kiro-cli login` 済み。`kirocrew config set instances.enabled true` のうえ `kirocrew gateway` を起動しておく
- AWS CLI v2、Session Manager plugin、Docker(Fargate のイメージビルド)、Terraform(EC2 の IaC を使う場合)
- `~/.kiro/agents/<CREW_NAME>.json` に crew の agent spec があること(`kiro-cli agent create` で作るか既存のものを置く)
- Kiro のプランは Pro 以上。Fargate / MicroVM は Crew のサインインで得た ID ドキュメントを Secrets Manager に置く

```bash
cp env.example env   # 値を埋める
source ./env
```

## EC2

```bash
# 製品機能(CloudFormation)。Identity Center なら --idp-region が必要
kirocrew cloud doctor --profile "$AWS_PROFILE" --region "$AWS_REGION"
kirocrew cloud launch --profile "$AWS_PROFILE" --region "$AWS_REGION" --size light --idp-region us-east-1 -y
# または Terraform
cd ec2-terraform && terraform init && terraform apply -var profile="$AWS_PROFILE"
```

Terraform 版は SSM 接続のみ、user-data で kiro-cli と Crew を入れて常駐化します。詳細は `ec2-terraform/README.md`。

## Fargate

```bash
fargate/01-foundation.sh        # 権限境界、base スタック(クラスタ + SG)、ECR、crew スタック(ロール + ロググループ)
fargate/02-build-image.sh       # ベースイメージ(署名付きフィードの wheel)→ crew バンドル → crew イメージ → ECR
lib/identity-secret.sh          # Crew のサインイン(デバイスコードを承認)→ KasToken を Secrets Manager へ
fargate/03-write-cloud-json.sh  # cloud.json の fargate ブロックを書き、provisioners に aws_fargate が出ることを確認
fargate/04-launch.sh [light]    # POST /api/cloud/launch(confirm_recipient 付き)→ 完了まで待つ
fargate/05-turn.sh "質問"       # SSM 経由で接続し、Chat Completions 形式のターン API に送る
```

- `02-build-image.sh` は x86_64 でビルドします。ARM64 で動かすなら `CPU_ARCH=ARM64 DOCKER_PLATFORM=linux/arm64` を設定してから `01` と `02` を実行してください
- NAT のないパブリックサブネットでは `assign_public_ip` が `true` でないとイメージを取得できません(デフォルト true)
- タスクは `FARGATE_TASK_TTL`(既定 3600 秒)で自動終了し、状態は残りません

## Lambda MicroVM

```bash
microvm/01-foundation.sh        # base スタック(KMS、レシピバケット、ロール)とロググループ
microvm/02-stage-wheel.sh       # wheel からダッシュボード資産を除いて runtime/vendor に置く
microvm/03-write-cloud-json.sh  # cloud.json の microvm ブロック(bundle と ID シークレットは Fargate と共用)
microvm/04-launch.sh            # 初回はイメージビルド込みで 8 分程度
microvm/05-turn.sh "質問"       # ゲストは全ルート認証必須なので、ハブの crew-turn API 経由
```

MicroVM は `MICROVM_WALL_SECONDS`(既定 3600 秒)で消え、会話も残りません。

## 片付け

```bash
./cleanup.sh                    # タスク停止、MicroVM 終了、スタック削除、ECR、シークレット、ロググループ
kirocrew cloud destroy --profile "$AWS_PROFILE" --region "$AWS_REGION"
cd ec2-terraform && terraform destroy -var profile="$AWS_PROFILE"
```

## ハマりどころ

- `login_target` に Identity Center を渡すと Fargate / MicroVM は preflight で拒否されます。資格情報はシークレットから渡るので省略します(スクリプトは送りません)
- 起動ジョブは同時に 1 つだけです。ハブのダッシュボードトークンは数分で失効するので、スクリプトは呼び出しごとに発行しています
- Fargate のターン API は `model` に crew 名が必要で、`stream: true` でないと応答が返ってこないことがありました
- MicroVM に置く wheel は `kiro_crew/static/` を含むと 64MiB の上限を超えます(`02-stage-wheel.sh` が取り除きます)

## 注意

Fargate と MicroVM では、crew のモデル認証情報がタスクや VM の中から読める状態で動きます(公式ドキュメントの `internal_only` の説明どおり)。自分のアカウントで自分の crew を動かす用途に限ってください。
