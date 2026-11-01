#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/../lib/launch.sh" microvm "${1:-light}"
