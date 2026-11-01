#!/usr/bin/env bash
# provisioner API で起動して完了まで待つ。使い方: launch.sh <provider_id: aws_fargate|microvm> [size_key]
set -euo pipefail
source "$(dirname "$0")/common.sh"
PROVIDER="$1"; SIZE="${2:-light}"
hub_check
CONFIRM=$(hub_get /api/cloud/provisioners | "$(kc_python)" -c "
import sys,json; d=json.load(sys.stdin); rows=[p for p in d['provisioners'] if p['id']=='$PROVIDER']
if not rows: sys.exit('レーン $PROVIDER が provisioners にありません。cloud.json のブロックが不完全です: ' + ', '.join(p['id'] for p in d['provisioners']))
print(rows[0]['confirm_before_launch'])")
echo "confirm_before_launch: ${CONFIRM:0:120}..."
BODY=$("$(kc_python)" -c "import json; print(json.dumps({'provider_id':'$PROVIDER','profile':'${AWS_PROFILE:-}','region':'$AWS_REGION','size_key':'$SIZE','confirm_recipient':'''$CONFIRM'''}))")
JOB=$(hub_post /api/cloud/launch "$BODY" | "$(kc_python)" -c "import sys,json; d=json.load(sys.stdin); print(d.get('id') or sys.exit(d.get('error','launch failed')))")
echo "launch job: $JOB"
for i in $(seq 1 120); do
  sleep 10
  hub_get "/api/cloud/launch/$JOB" | "$(kc_python)" -c "
import sys,json; d=json.load(sys.stdin); st=d.get('status')
print(st, '|', ' / '.join(f\"{s['key']}:{s['state']}\" for s in d.get('steps',[])), '|', d.get('instance_id') or '')
if st=='failed': sys.exit('失敗: ' + d.get('error',''))
sys.exit(0 if st=='done' else 3)" && break || { rc=$?; [ $rc -eq 3 ] || exit $rc; }
done
echo "done. ハブの Settings → Remote Crew に追加されています"
