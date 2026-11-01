#!/usr/bin/env bash
# MicroVM レーンは同梱パッケージの runtime/vendor に wheel を 1 つ要求する。
# デスクトップ用の wheel はダッシュボード資産(kiro_crew/static/)で 64MiB の上限を超えるので取り除いて置く。
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
PY=$(kc_python); RT=$(kc_runtime); WORK="${WORK_DIR:-$HOME/.cache/kirocrew-aws-lanes}"; mkdir -p "$WORK"
CHANNEL="${KIROCREW_CHANNEL:-stable}"
FEED=$(curl -fsSL "https://updates.crew.kiro.dev/feed/${CHANNEL}/latest-cli.json")
WHEEL_URL=$(echo "$FEED" | "$PY" -c "import sys,json; print(json.load(sys.stdin)['wheel_url'])")
WHEEL_SHA=$(echo "$FEED" | "$PY" -c "import sys,json; print(json.load(sys.stdin)['sha256'])")
SRC="$WORK/$(basename "$WHEEL_URL")"
[ -f "$SRC" ] && echo "$WHEEL_SHA  $SRC" | sha256sum -c - >/dev/null 2>&1 || curl -fL --retry 5 --retry-all-errors -C - "$WHEEL_URL" -o "$SRC"
echo "$WHEEL_SHA  $SRC" | sha256sum -c -
rm -f "$RT/vendor/"*.whl
"$PY" - "$SRC" "$RT/vendor/$(basename "$WHEEL_URL")" <<'PY'
import zipfile, sys, os
src, dst = sys.argv[1], sys.argv[2]
zin = zipfile.ZipFile(src); names = zin.namelist()
record = [n for n in names if n.endswith(".dist-info/RECORD")][0]
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
    for info in zin.infolist():
        if info.filename.startswith("kiro_crew/static/"): continue
        if info.filename == record:
            keep = [l for l in zin.read(info).decode().splitlines() if not l.split(",")[0].startswith("kiro_crew/static/")]
            zout.writestr(info, "\n".join(keep) + "\n"); continue
        zout.writestr(info, zin.read(info))
print(f"staged {dst}: {os.path.getsize(src)} -> {os.path.getsize(dst)} bytes (static assets removed)")
PY
