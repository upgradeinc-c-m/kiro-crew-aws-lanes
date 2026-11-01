#!/usr/bin/env bash
# 検証で作ったものを消す(取り消せない)。実行前に出力を確認すること。
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
R="$AWS_REGION"
echo "== Fargate tasks"
CLUSTER=$(stack_output kirocrew-fargate-base ClusterName 2>/dev/null || true)
if [ -n "$CLUSTER" ]; then
  for t in $(aws ecs list-tasks --region "$R" --cluster "$CLUSTER" --query 'taskArns[]' --output text); do aws ecs stop-task --region "$R" --cluster "$CLUSTER" --task "$t" --reason cleanup >/dev/null && echo "stopped $t"; done
fi
echo "== MicroVMs"
for m in $(aws lambda-microvms list-microvms --region "$R" --query 'items[].microvmArn' --output text 2>/dev/null); do aws lambda-microvms terminate-microvm --region "$R" --microvm-identifier "$m" >/dev/null 2>&1 && echo "terminated $m" || true; done
for img in $(aws lambda-microvms list-microvm-images --region "$R" --query "items[?starts_with(name,'kirocrew-')].imageArn" --output text 2>/dev/null); do aws lambda-microvms delete-microvm-image --region "$R" --image-identifier "$img" >/dev/null 2>&1 && echo "deleted image $img" || true; done
echo "== stacks"
for s in "kirocrew-fargate-crew-$CREW_NAME" kirocrew-fargate-base kirocrew-microvm-base; do
  aws cloudformation describe-stacks --region "$R" --stack-name "$s" >/dev/null 2>&1 && { aws cloudformation delete-stack --region "$R" --stack-name "$s"; echo "deleting $s"; }
done
echo "== ECR $ECR_REPO"
aws ecr delete-repository --region "$R" --repository-name "$ECR_REPO" --force >/dev/null 2>&1 && echo "deleted repo" || true
echo "== secrets / log groups"
aws secretsmanager delete-secret --region "$R" --secret-id "kirocrew/crew/$CREW_NAME/KIRO_IDENTITY" --force-delete-without-recovery >/dev/null 2>&1 && echo "deleted identity secret" || true
for s in $(aws secretsmanager list-secrets --region "$R" --filters Key=name,Values=kirocrew/crew/ --query 'SecretList[].Name' --output text); do aws secretsmanager delete-secret --region "$R" --secret-id "$s" --force-delete-without-recovery >/dev/null 2>&1 && echo "deleted $s"; done
for lg in "/kirocrew/microvm/$CREW_NAME"; do aws logs delete-log-group --region "$R" --log-group-name "$lg" 2>/dev/null && echo "deleted $lg" || true; done
echo "== (レシピバケットは base スタック削除前に空にする必要があります)"
B=$(stack_output kirocrew-microvm-base RecipeBucketName 2>/dev/null || true); [ -n "$B" ] && aws s3 rm "s3://$B" --recursive --region "$R" >/dev/null 2>&1 || true
for s in "kirocrew-fargate-crew-$CREW_NAME" kirocrew-fargate-base kirocrew-microvm-base; do aws cloudformation wait stack-delete-complete --region "$R" --stack-name "$s" 2>/dev/null || true; done
echo "== EC2 lane: 'kirocrew cloud destroy' と ec2-terraform/ の 'terraform destroy' は別途実行"
echo "done"
