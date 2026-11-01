#!/usr/bin/env bash
# Crew のサインイン(デバイスフロー)を始め、承認後に vault の KasToken を Secrets Manager の
# kirocrew/crew/<CREW_NAME>/KIRO_IDENTITY に置く。値は画面に出さない。
set -euo pipefail
source "$(dirname "$0")/common.sh"
hub_check; PY=$(kc_python)
if [ "${SKIP_SIGNIN:-0}" != "1" ]; then
  if [ -n "${KIRO_START_URL:-}" ]; then
    BODY=$("$PY" -c "import json; print(json.dumps({'provider':'idc','start_url':'$KIRO_START_URL','region':'${KIRO_IDP_REGION:-us-east-1}'}))")
  else
    BODY='{"provider":"builder_id"}'
  fi
  R=$(hub_post /api/kas-login/device "$BODY" 90)
  echo "$R" | "$PY" -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: sys.exit(d)
print('ブラウザで承認してください:', d['verification_uri_complete']); print('code:', d['user_code'])"
  LID=$(echo "$R" | "$PY" -c "import sys,json; print(json.load(sys.stdin)['login_id'])")
  for i in $(seq 1 60); do
    sleep 10
    ST=$(hub_post /api/kas-login/poll "{\"login_id\":\"$LID\"}" 60 | "$PY" -c "import sys,json; d=json.load(sys.stdin); print(d.get('status') or d.get('code') or d)")
    echo "  $ST"; case "$ST" in authorized|unknown_login_id) break;; esac
  done
fi
TMP=$(mktemp); chmod 600 "$TMP"; trap 'rm -f "$TMP"' EXIT
env -u KIRO_API_KEY "$PY" - "$TMP" <<'PY'
import sys
from kiro_crew.auth import bridge
tok = bridge.default_token_store().resolve()
if tok is None: sys.exit("vault に ID がありません。サインインが完了していません")
open(sys.argv[1], "w").write(tok.to_json()); print("identity:", tok.identity, tok.provider)
PY
NAME="kirocrew/crew/$CREW_NAME/KIRO_IDENTITY"
aws secretsmanager create-secret --region "$AWS_REGION" --name "$NAME" --secret-string "file://$TMP" --query ARN --output text 2>/dev/null \
  || aws secretsmanager put-secret-value --region "$AWS_REGION" --secret-id "$NAME" --secret-string "file://$TMP" --query ARN --output text
