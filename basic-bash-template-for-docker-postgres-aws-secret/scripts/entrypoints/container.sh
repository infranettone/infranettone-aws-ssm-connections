#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly CONFIG_FILE="$ROOT_DIR/config.txt"

source "$ROOT_DIR/scripts/lib/core/ui.sh"
source "$ROOT_DIR/scripts/lib/features/aws_context.sh"
source "$ROOT_DIR/scripts/lib/features/quality.sh"

show_current_context() {
  info "Current configuration:"
  info "  AWS profile: $AWS_PROFILE"
  info "  AWS region: $AWS_REGION"
  info "  AWS secret: $AWS_SECRET_NAME"
}

show_secret_preview() {
  local secret_kind="plain-text"
  local app_name=""

  if secret_string_is_json; then
    secret_kind="json"
    app_name="$(get_secret_json_field "appName" || true)"
  fi

  info "Secret loaded successfully."
  info "  Type: $secret_kind"

  if [[ -n "$app_name" ]]; then
    info "  appName: $app_name"
  fi
}

run_project_placeholder() {
  info "Project action placeholder."
  info "Implement your custom workflow in scripts/entrypoints/container.sh."
}

run_main_menu() {
  local selected_option=""
  local -a menu_options=(
    "Reconfigure AWS profile/region/secret"
    "Show current configuration"
    "Show secret preview"
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
