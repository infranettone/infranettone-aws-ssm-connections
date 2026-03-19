#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly COMPOSE_FILE="$ROOT_DIR/main/docker-compose.yml"
readonly SERVICE_NAME="app-template"
readonly CONTAINER_WORKDIR="/workspace"
readonly CONTAINER_RUN_SCRIPT="/workspace/scripts/entrypoints/container.sh"

detect_awscli_arch() {
  local raw_arch="${DOCKER_DEFAULT_PLATFORM:-${TARGETPLATFORM:-}}"

  if [[ -z "$raw_arch" ]]; then
    raw_arch="$(uname -m)"
  fi

  raw_arch="${raw_arch,,}"

  case "$raw_arch" in
    *amd64*|*x86_64*|*x86-64*|*x64*|*i386*|*i486*|*i586*|*i686*)
      echo "amd64"
      ;;
    *arm64*|*aarch64*|*armv8*|*armv9*|*arm*)
      echo "arm64"
      ;;
    *)
      echo "amd64"
      ;;
  esac
}

detect_docker_gid() {
  local docker_gid=""

  docker_gid="$(getent group docker | cut -d: -f3 || true)"
  if [[ -z "$docker_gid" ]]; then
    docker_gid="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || true)"
  fi

  [[ -n "$docker_gid" ]] || {
    echo "Could not detect Docker GID (docker group or /var/run/docker.sock)." >&2
    exit 1
  }

  echo "$docker_gid"
}

main() {
  local awscli_arch=""
  local docker_gid=""
  local host_uid=""
  local host_gid=""
  local host_user="ubuntu"

  command -v docker >/dev/null 2>&1 || {
    echo "Required command not found: docker" >&2
    exit 1
  }

  awscli_arch="$(detect_awscli_arch)"
  docker_gid="$(detect_docker_gid)"
  host_uid="$(id -u)"
  host_gid="$(id -g)"

  echo "Detected AWS CLI architecture: $awscli_arch"
  echo "Using Docker GID: $docker_gid"
  echo "Using UID:GID mapping: ${host_uid}:${host_gid} (container user: ${host_user})"

  DOCKER_GID="$docker_gid" \
  AWSCLI_ARCH="$awscli_arch" \
  HOST_UID="$host_uid" \
  HOST_GID="$host_gid" \
  HOST_USER="$host_user" \
  docker compose -f "$COMPOSE_FILE" up --build -d

  time docker exec -it -w "$CONTAINER_WORKDIR" "$SERVICE_NAME" bash "$CONTAINER_RUN_SCRIPT" "$@"
}

main "$@"
