#!/usr/bin/env bash
# Fargate レーンの土台: 権限境界、ECS クラスタ(base スタック)、crew ごとのロール(crew スタック)、ECR
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
T=$(kc_templates); ACCT=$(account_id)
echo "== 1/4 permissions boundaries (kirocrew cloud iam-boundary)"
kirocrew cloud iam-boundary --profile "${AWS_PROFILE:-default}" --region "$AWS_REGION" 2>/dev/null | grep -E "✓|boundary" || true
echo "== 2/4 base stack (ECS cluster + egress-only SG)"
VPC="${VPC_ID:-$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)}"
SUBNETS="${SUBNET_IDS:-$(aws ec2 describe-subnets --region "$AWS_REGION" --filters Name=vpc-id,Values="$VPC" --query 'Subnets[].SubnetId' --output text | tr '\t' ',')}"
aws cloudformation deploy --region "$AWS_REGION" --stack-name kirocrew-fargate-base --template-file "$T/kirocrew-fargate-base.yaml" \
  --parameter-overrides VpcId="$VPC" "SubnetIds=$SUBNETS" CpuArchitecture="${CPU_ARCH:-X86_64}" \
  --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset
echo "== 3/4 ECR repository $ECR_REPO"
aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPO" >/dev/null 2>&1 || \
  aws ecr create-repository --region "$AWS_REGION" --repository-name "$ECR_REPO" --query repository.repositoryUri --output text
echo "== 4/4 crew stack for $CREW_NAME (exec role, task role, log group)"
aws cloudformation deploy --region "$AWS_REGION" --stack-name "kirocrew-fargate-crew-$CREW_NAME" --template-file "$T/kirocrew-fargate-crew.yaml" \
  --parameter-overrides Crew="$CREW_NAME" \
    PermissionsBoundaryArn="arn:aws:iam::${ACCT}:policy/kirocrew-crew-boundary" \
    ExecutionPermissionsBoundaryArn="arn:aws:iam::${ACCT}:policy/kirocrew-crew-exec-boundary" \
    EcrRepositoryArn="arn:aws:ecr:${AWS_REGION}:${ACCT}:repository/${ECR_REPO}" \
  --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset
aws cloudformation describe-stacks --region "$AWS_REGION" --stack-name "kirocrew-fargate-crew-$CREW_NAME" --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output text
