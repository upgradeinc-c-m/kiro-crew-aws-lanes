#!/usr/bin/env bash
# ハブ経由で Fargate crew に接続し、タスクのターン API(OpenAI Chat Completions 形式)へ 1 ターン送る
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
hub_check; PY=$(kc_python)
ID=$(hub_get /api/instances | "$PY" -c "
import sys,json; d=json.load(sys.stdin); items=d.get('instances', d)
rows=[i for i in items if (i.get('method') or i.get('connection_method'))=='fargate']
print(rows[-1]['id'] if rows else sys.exit('Fargate の crew がインスタンス一覧にありません'))")
echo "instance: $ID"
URL=$(hub_post "/api/instances/$ID/connect" '{}' 180 | "$PY" -c "import sys,json; d=json.load(sys.stdin); print(d.get('turn_url') or sys.exit(d))")
echo "turn_url: $URL"
curl -s -m 10 "${URL%/v1/chat/completions}/health"; echo
MSG="${1:-Reply with exactly one word: pong}"
curl -s -N -m 600 -X POST "$URL" -H "Content-Type: application/json" \
  -d "$("$PY" -c "import json; print(json.dumps({'model':'$CREW_NAME','messages':[{'role':'user','content':'''$MSG'''}],'stream':True}))")"
