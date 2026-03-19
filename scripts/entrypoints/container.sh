#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly CONFIG_FILE="$ROOT_DIR/config.txt"

source "$ROOT_DIR/scripts/lib/core/ui.sh"
source "$ROOT_DIR/scripts/lib/features/aws_context.sh"
source "$ROOT_DIR/scripts/lib/features/quality.sh"

find_available_local_port() {
  local port=""

  for port in 15432 15433 15434 15435 15436 15437 15438 15439 15440; do
    if ! timeout 1 bash -lc "</dev/tcp/127.0.0.1/$port" >/dev/null 2>&1; then
      printf "%s" "$port"
      return 0
    fi
  done

  die "Could not find an available local port for the RDS tunnel."
}

find_available_internal_port() {
  local port=""

  for port in $(seq 25432 25480); do
    if ! timeout 1 bash -lc "</dev/tcp/127.0.0.1/$port" >/dev/null 2>&1; then
      printf "%s" "$port"
      return 0
    fi
  done

  die "Could not find an available internal port for the RDS tunnel."
}

wait_for_local_port() {
  local port="$1"
  local max_attempts="${2:-20}"
  local attempt=""

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if timeout 1 bash -lc "</dev/tcp/127.0.0.1/$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

cleanup_rds_tunnel() {
  local ssm_pid="${1:-}"
  local relay_pid="${2:-}"
  local log_file="${3:-}"

  if [[ -n "$ssm_pid" ]] && kill -0 "$ssm_pid" >/dev/null 2>&1; then
    kill "$ssm_pid" >/dev/null 2>&1 || true
    wait "$ssm_pid" >/dev/null 2>&1 || true
  fi

  if [[ -n "$relay_pid" ]] && kill -0 "$relay_pid" >/dev/null 2>&1; then
    kill "$relay_pid" >/dev/null 2>&1 || true
    wait "$relay_pid" >/dev/null 2>&1 || true
  fi

  if [[ -n "$log_file" ]]; then
    rm -f "$log_file"
  fi
}

run_rds_psql_tunnel() {
  local secret_string=""
  local db_host=""
  local db_port=""
  local db_name=""
  local db_user=""
  local db_password=""
  local local_port=""
  local internal_port=""
  local log_file=""
  local ssm_pid=""
  local relay_pid=""

  [[ "${CONNECTION_TARGET:-}" == "RDS" ]] || die "The current connection target is not RDS."
  [[ -n "${RDS_BASTION_INSTANCE_ID:-}" ]] || die "RDS bastion instance is not configured."

  require_command aws jq psql session-manager-plugin socat timeout

  secret_string="$(fetch_current_secret_string)"
  secret_string_is_json "$secret_string" || die "The selected AWS secret must be valid JSON for the RDS connection."

  db_host="$(get_secret_json_field "host" "$secret_string" || true)"
  db_port="$(get_secret_json_field "port" "$secret_string" || true)"
  db_name="$(get_secret_json_field "dbname" "$secret_string" || true)"
  db_user="$(get_secret_json_field "username" "$secret_string" || true)"
  db_password="$(get_secret_json_field "password" "$secret_string" || true)"

  [[ -n "$db_host" ]] || die "The selected secret does not contain the required 'host' field."
  [[ -n "$db_port" ]] || die "The selected secret does not contain the required 'port' field."
  [[ -n "$db_user" ]] || die "The selected secret does not contain the required 'username' field."
  [[ -n "$db_password" ]] || die "The selected secret does not contain the required 'password' field."

  if [[ -z "$db_name" ]]; then
    db_name="$(get_secret_json_field "database" "$secret_string" || true)"
  fi
  [[ -n "$db_name" ]] || db_name="postgres"

  local_port="$(find_available_local_port)"
  internal_port="$(find_available_internal_port)"
  log_file="$(mktemp /tmp/rds-ssm-tunnel.XXXXXX.log)"

  info "Starting SSM port forwarding session to $db_host:$db_port through $RDS_BASTION_INSTANCE_ID"
  aws ssm start-session \
    --target "$RDS_BASTION_INSTANCE_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --document-name "AWS-StartPortForwardingSessionToRemoteHost" \
    --parameters "host=$db_host,portNumber=$db_port,localPortNumber=$internal_port" \
    >"$log_file" 2>&1 &
  ssm_pid=$!

  trap 'cleanup_rds_tunnel "$ssm_pid" "$relay_pid" "$log_file"' RETURN

  if ! wait_for_local_port "$internal_port" 20; then
    warn "SSM tunnel did not become available in time."
    if [[ -s "$log_file" ]]; then
      warn "SSM log:"
      sed 's/^/  /' "$log_file" >&2
    fi
    return 1
  fi

  info "Exposing tunnel on 0.0.0.0:$local_port for host access"
  socat TCP-LISTEN:"$local_port",bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:"$internal_port" \
    > /dev/null 2>&1 &
  relay_pid=$!

  if ! wait_for_local_port "$local_port" 20; then
    warn "Tunnel relay did not become available in time."
    if [[ -s "$log_file" ]]; then
      warn "SSM log:"
      sed 's/^/  /' "$log_file" >&2
    fi
    return 1
  fi

  info "Tunnel ready on localhost:$local_port and host:${local_port}"
  info "Opening interactive psql session against database '$db_name'"

  PGPASSWORD="$db_password" psql \
    --host=127.0.0.1 \
    --port="$local_port" \
    --username="$db_user" \
    --dbname="$db_name"

  trap - RETURN
  cleanup_rds_tunnel "$ssm_pid" "$relay_pid" "$log_file"
}

show_current_context() {
  info "Current configuration:"
  info "  AWS profile: $AWS_PROFILE"
  info "  AWS region: $AWS_REGION"
  info "  AWS secret: $AWS_SECRET_NAME"
  info "  Connection target: $CONNECTION_TARGET"

  if [[ "${CONNECTION_TARGET:-}" == "RDS" && -n "${RDS_BASTION_INSTANCE_ID:-}" ]]; then
    info "  RDS bastion instance: $RDS_BASTION_INSTANCE_ID"
  fi
}

show_secret_preview() {
  local secret_string=""
  local secret_kind="plain-text"
  local app_name=""

  secret_string="$(fetch_current_secret_string)"

  if secret_string_is_json "$secret_string"; then
    secret_kind="json"
    app_name="$(get_secret_json_field "appName" "$secret_string" || true)"
  fi

  info "Secret loaded successfully."
  info "  Type: $secret_kind"

  if [[ -n "$app_name" ]]; then
    info "  appName: $app_name"
  fi
}

show_secret_json() {
  local secret_string=""

  require_command jq

  secret_string="$(fetch_current_secret_string)"
  secret_string_is_json "$secret_string" || die "The selected secret is not valid JSON."

  jq . <<<"$secret_string"
}

run_project_placeholder() {
  info "Project action placeholder."
  info "Implement your custom workflow in scripts/entrypoints/container.sh."
}

run_main_menu() {
  local selected_option=""
  local -a menu_options=()

  menu_options=(
    "Reconfigure AWS profile/region/secret"
    "Show current configuration"
    "Show secret preview"
    "Show secret JSON"
  )

  if [[ "${CONNECTION_TARGET:-}" == "RDS" && -n "${RDS_BASTION_INSTANCE_ID:-}" ]]; then
    menu_options+=("Open RDS tunnel and launch psql")
  fi

  menu_options+=(
    "Run project placeholder"
    "Exit"
  )

  while true; do
    selected_option="$(select_from_options $'Choose an option: ' menu_options)"

    case "$selected_option" in
      "Reconfigure AWS profile/region/secret")
        reconfigure_context "$CONFIG_FILE"
        ;;
      "Show current configuration")
        show_current_context
        ;;
      "Show secret preview")
        show_secret_preview
        ;;
      "Show secret JSON")
        show_secret_json
        ;;
      "Open RDS tunnel and launch psql")
        run_rds_psql_tunnel
        ;;
      "Run project placeholder")
        run_project_placeholder
        ;;
      "Exit")
        break
        ;;
      *)
        die "Unexpected menu option: $selected_option"
        ;;
    esac
  done
}

main() {
  initialize_context "$CONFIG_FILE"
  run_main_menu
}

case "${1:-}" in
  quality|local-quality)
    shift
    run_local_quality "$@"
    ;;
  "")
    main "$@"
    ;;
  *)
    die "Unsupported command: $1. Use: $0 [quality|local-quality]"
    ;;
esac
