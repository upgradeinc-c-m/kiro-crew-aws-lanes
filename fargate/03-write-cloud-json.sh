#!/usr/bin/env bash
# cloud.json の fargate ブロックを base/crew スタックの出力と ECR のダイジェストから書く
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
WORK="${WORK_DIR:-$HOME/.cache/kirocrew-aws-lanes}"
IMAGE=$(cat "$WORK/crew-image-ref.txt")
SECRET_ARN=$(aws secretsmanager describe-secret --region "$AWS_REGION" --secret-id "kirocrew/crew/$CREW_NAME/KIRO_IDENTITY" --query ARN --output text)
CLUSTER=$(stack_output kirocrew-fargate-base ClusterName); SG=$(stack_output kirocrew-fargate-base SecurityGroupId)
SUBNETS=$(stack_output kirocrew-fargate-base SubnetIds); ARCH=$(stack_output kirocrew-fargate-base CpuArchitecture)
cloud_json_set "$("$(kc_python)" -c "
import json
print(json.dumps({'profile': '${AWS_PROFILE:-}', 'region': '$AWS_REGION', 'fargate': {
  'cluster': '$CLUSTER', 'subnets': '$SUBNETS'.split(','), 'security_groups': ['$SG'],
  'image': '$IMAGE', 'secrets': [['kirocrew/crew/$CREW_NAME/KIRO_IDENTITY', '$SECRET_ARN']],
  'cpu_architecture': '$ARCH', 'assign_public_ip': json.loads('${ASSIGN_PUBLIC_IP:-true}'),
  'task_ttl_seconds': ${FARGATE_TASK_TTL:-3600}, 'internal_only': True}}))")"
echo "確認: GET /api/cloud/provisioners に aws_fargate が出るか"
hub_check; hub_get /api/cloud/provisioners | "$(kc_python)" -c "import sys,json; print([p['id'] for p in json.load(sys.stdin)['provisioners']])"
