#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOST_ENTRYPOINT="$SCRIPT_DIR/scripts/entrypoints/host.sh"

[[ -f "$HOST_ENTRYPOINT" ]] || {
  echo "Host entrypoint not found: $HOST_ENTRYPOINT" >&2
  exit 1
}

exec bash "$HOST_ENTRYPOINT" "$@"
