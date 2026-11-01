#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/../lib/launch.sh" aws_fargate "${1:-light}"
