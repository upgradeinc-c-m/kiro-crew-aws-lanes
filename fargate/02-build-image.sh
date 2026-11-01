#!/usr/bin/env bash
# Crew コンテナイメージ: ベース(同梱 Dockerfile + 署名付きフィードの wheel)→ crew 層(Dockerfile.crew + packaging.build のバンドル)→ ECR
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
RT=$(kc_runtime); PY=$(kc_python); ACCT=$(account_id)
REPO="${ACCT}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
WORK="${WORK_DIR:-$HOME/.cache/kirocrew-aws-lanes}"; mkdir -p "$WORK/runtime" "$WORK/bundle"
CHANNEL="${KIROCREW_CHANNEL:-stable}"
PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"   # base スタックの CpuArchitecture と合わせる(ARM64 なら linux/arm64)

echo "== 1/5 wheel(署名付きフィード)"
FEED=$(curl -fsSL "https://updates.crew.kiro.dev/feed/${CHANNEL}/latest-cli.json")
WHEEL_URL=$(echo "$FEED" | "$PY" -c "import sys,json; print(json.load(sys.stdin)['wheel_url'])")
WHEEL_SHA=$(echo "$FEED" | "$PY" -c "import sys,json; print(json.load(sys.stdin)['sha256'])")
VERSION=$(echo "$FEED" | "$PY" -c "import sys,json; print(json.load(sys.stdin)['version'])")
cp -r "$RT/." "$WORK/runtime/"; rm -f "$WORK/runtime/vendor/"*.whl
curl -fL --retry 5 --retry-all-errors -C - "$WHEEL_URL" -o "$WORK/runtime/vendor/$(basename "$WHEEL_URL")"
echo "${WHEEL_SHA}  $WORK/runtime/vendor/$(basename "$WHEEL_URL")" | sha256sum -c -

echo "== 2/5 base image (kirocrew $VERSION, $PLATFORM)"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${ACCT}.dkr.ecr.${AWS_REGION}.amazonaws.com" >/dev/null
docker build --platform "$PLATFORM" -f "$WORK/runtime/Dockerfile" -t "$REPO:base-$VERSION" "$WORK/runtime"
docker push -q "$REPO:base-$VERSION"
BASE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REPO:base-$VERSION")
echo "base: $BASE_DIGEST"

echo "== 3/5 crew bundle (packaging.build)"
rm -rf "$WORK/bundle/$CREW_NAME"
( cd "$(kc_pkg)/apps/builtins/aws_control/crew" && "$PY" -m packaging.build build --crew "$CREW_NAME" --out "$WORK/bundle/$CREW_NAME" ${BUNDLE_SOURCE:+--source "$BUNDLE_SOURCE"} )
BUNDLE_DIGEST=$("$PY" -c "import json; print(json.load(open('$WORK/bundle/$CREW_NAME/manifest.json'))['digest'])")

echo "== 4/5 crew image"
docker build --platform "$PLATFORM" -f "$WORK/runtime/Dockerfile.crew" \
  --build-arg BASE="$BASE_DIGEST" --build-arg CREW_NAME="$CREW_NAME" --build-arg BUNDLE_DIGEST="$BUNDLE_DIGEST" \
  --build-arg BUNDLE_VERSION=1 --build-arg BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t "$REPO:$CREW_NAME" "$WORK/bundle/$CREW_NAME"
docker push -q "$REPO:$CREW_NAME"
echo "== 5/5 digest"
aws ecr describe-images --region "$AWS_REGION" --repository-name "$ECR_REPO" --image-ids imageTag="$CREW_NAME" --query "imageDetails[0].imageDigest" --output text | sed "s#^#${REPO}@#" | tee "$WORK/crew-image-ref.txt"
echo "bundle dir: $WORK/bundle/$CREW_NAME (MicroVM レーンでも使う)"
