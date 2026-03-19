#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly CONTAINER_ENTRYPOINT="$ROOT_DIR/scripts/entrypoints/container.sh"

[[ -f "$CONTAINER_ENTRYPOINT" ]] || {
  echo "Container entrypoint not found: $CONTAINER_ENTRYPOINT" >&2
  exit 1
}

exec bash "$CONTAINER_ENTRYPOINT" "$@"
