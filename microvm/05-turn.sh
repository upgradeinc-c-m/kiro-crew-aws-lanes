#!/usr/bin/env bash
# MicroVM のゲストは全ルート認証必須なので、ハブの crew-turn API 経由で 1 ターン送る
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
hub_check; PY=$(kc_python)
ID=$(hub_get /api/instances | "$PY" -c "
import sys,json; d=json.load(sys.stdin); items=d.get('instances', d)
rows=[i for i in items if str(i.get('ssm_target','')).startswith('mi-')]
print(rows[-1]['id'] if rows else sys.exit('MicroVM の crew がインスタンス一覧にありません'))")
echo "instance: $ID"
# 起動直後は disconnected のことがあるので接続してから送る
hub_post "/api/instances/$ID/connect" '{}' 180 | "$PY" -c "import sys,json; d=json.load(sys.stdin); print('state:', d.get('state'), d.get('error',''))"
for i in $(seq 1 12); do
  hub_get "/api/instances/$ID/status" | "$PY" -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('state')=='connected' else 1)" && break; sleep 5
done
MSG="${1:-Reply with exactly one word: pong}"
hub_post "/api/instances/$ID/crew-turn" "$("$PY" -c "import json; print(json.dumps({'thread':'verify-1','message':'''$MSG''','stream':False}))")" 600
echo
