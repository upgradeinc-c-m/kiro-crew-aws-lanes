#!/usr/bin/env bash
# cloud.json の microvm ブロックを base スタックの出力から書く(bundle_dir と ID シークレットは Fargate と共用)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
WORK="${WORK_DIR:-$HOME/.cache/kirocrew-aws-lanes}"
BUNDLE="${BUNDLE_DIR:-$WORK/bundle/$CREW_NAME}"; [ -f "$BUNDLE/manifest.json" ] || { echo "bundle がありません: fargate/02-build-image.sh を先に実行($BUNDLE)" >&2; exit 1; }
SECRET_ARN=$(aws secretsmanager describe-secret --region "$AWS_REGION" --secret-id "kirocrew/crew/$CREW_NAME/KIRO_IDENTITY" --query ARN --output text)
BASE_IMG=$(aws lambda-microvms list-managed-microvm-images --region "$AWS_REGION" --query 'items[0].imageArn' --output text)
cloud_json_set "$("$(kc_python)" -c "
import json
print(json.dumps({'profile': '${AWS_PROFILE:-}', 'region': '$AWS_REGION', 'microvm': {
  'base_image_arn': '$BASE_IMG',
  'build_role_arn': '$(stack_output kirocrew-microvm-base ImageBuildRoleArn)',
  'recipe_bucket': '$(stack_output kirocrew-microvm-base RecipeBucketName)',
  'bundle_dir': '$BUNDLE',
  'kms_key_id': '$(stack_output kirocrew-microvm-base LaneKmsKeyArn)',
  'activation_role_arn': '$(stack_output kirocrew-microvm-base HybridActivationRoleArn)',
  'identity_secret_ref': '$SECRET_ARN',
  'execution_role_arn': '$(stack_output kirocrew-microvm-base ExecutionRoleArn)',
  'log_group': '/kirocrew/microvm/$CREW_NAME',
  'wall_seconds': ${MICROVM_WALL_SECONDS:-3600}}}))")"
hub_check; hub_get /api/cloud/provisioners | "$(kc_python)" -c "import sys,json; print([p['id'] for p in json.load(sys.stdin)['provisioners']])"
