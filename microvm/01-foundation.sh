#!/usr/bin/env bash
# MicroVM レーンの土台: base スタック(KMS、レシピバケット、ビルド/アクティベーション/実行ロール)とロググループ
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
T=$(kc_templates)
aws cloudformation deploy --region "$AWS_REGION" --stack-name kirocrew-microvm-base --template-file "$T/kirocrew-microvm-base.yaml" \
  --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset
LG="/kirocrew/microvm/$CREW_NAME"
aws logs describe-log-groups --region "$AWS_REGION" --log-group-name-prefix "$LG" --query "logGroups[?logGroupName=='$LG']" --output text | grep -q . || \
  aws logs create-log-group --region "$AWS_REGION" --log-group-name "$LG"
aws logs put-retention-policy --region "$AWS_REGION" --log-group-name "$LG" --retention-in-days 7
aws cloudformation describe-stacks --region "$AWS_REGION" --stack-name kirocrew-microvm-base --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output text
echo "managed base image: $(aws lambda-microvms list-managed-microvm-images --region "$AWS_REGION" --query 'items[0].imageArn' --output text)"
