#!/usr/bin/env bash
# 共通: kirocrew の Python / パッケージ位置、ハブ API、cloud.json 編集
set -euo pipefail
: "${AWS_REGION:?source env first}"
: "${CREW_NAME:?source env first}"
KIROCREW_PORT="${KIROCREW_PORT:-5476}"
HUB="http://127.0.0.1:${KIROCREW_PORT}"

# kirocrew が入っている venv の python(one-liner 導入なら ~/.kiro/crew-venv)
kc_python() {
  if [ -n "${KIROCREW_PYTHON:-}" ]; then echo "$KIROCREW_PYTHON"; return; fi
  # 動いているゲートウェイと同じ Python を最優先(同梱パッケージの vendor/ に置く wheel はゲートウェイ側のものでないと効かない)
  local gw argv0; gw=$(pgrep -f "kirocrew gateway" | head -1 || true)
  if [ -n "$gw" ] && [ -r "/proc/$gw/cmdline" ]; then
    argv0=$(tr '\0' '\n' < "/proc/$gw/cmdline" | head -1)   # venv の python をそのまま(readlink すると venv の外の素の python になる)
    if [ -x "$argv0" ] && "$argv0" -c "import kiro_crew" 2>/dev/null; then echo "$argv0"; return; fi
  fi
  local shebang; shebang=$(head -1 "$(command -v kirocrew)" | sed -E 's/^#! *//; s/ .*//')
  if [ -x "$shebang" ]; then echo "$shebang"; return; fi
  echo "$HOME/.kiro/crew-venv/bin/python"
}
kc_pkg() { "$(kc_python)" -c "import kiro_crew,os;print(os.path.dirname(kiro_crew.__file__))"; }
kc_templates() { echo "$(kc_pkg)/cloud/templates"; }
kc_runtime() { echo "$(kc_pkg)/apps/builtins/aws_control/crew/runtime"; }

# ハブのダッシュボードトークン(数分で失効するので都度発行)
hub_token() { kirocrew token --ttl 2h 2>/dev/null | grep -oE "token=[A-Za-z0-9_.-]+" | head -1 | cut -d= -f2; }
hub_get()  { local out; out=$(curl -s -m 60 "${HUB}$1?token=$(hub_token)"); [ -n "$out" ] || { echo "ハブ API が空応答: $1(gateway が落ちているか、トークン発行に失敗)" >&2; return 1; }; echo "$out"; }
hub_post() { local out; out=$(curl -s -m "${3:-120}" -X POST "${HUB}$1?token=$(hub_token)" -H "Content-Type: application/json" -d "$2"); [ -n "$out" ] || { echo "ハブ API が空応答: $1" >&2; return 1; }; echo "$out"; }

hub_check() {
  curl -s -m 5 "${HUB}/api/health" | grep -q '"ok": true' || {
    echo "ハブの kirocrew gateway が ${HUB} で動いていません。別ターミナルで 'kirocrew config set instances.enabled true && kirocrew gateway' を実行してください" >&2; exit 1; }
}

# cloud.json の一部を書き換える(他のキーは保持)
cloud_json_set() { # $1 = JSON オブジェクト(トップレベルにマージ)
  "$(kc_python)" - "$1" <<'PY'
import json, os, sys
p = os.path.expanduser("~/.kiro/crew/cloud.json")
d = {}
try: d = json.load(open(p))
except Exception: pass
d.update(json.loads(sys.argv[1]))
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2); os.chmod(p, 0o600)
print("cloud.json updated:", ", ".join(d.keys()))
PY
}

stack_output() { aws cloudformation describe-stacks --region "$AWS_REGION" --stack-name "$1" --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text; }
account_id() { aws sts get-caller-identity --query Account --output text; }
