#!/usr/bin/env bash

die() {
  local message="$1"
  echo "Error: $message" >&2
  exit 1
}

info() {
  local message="$1"
  echo "$message"
}

warn() {
  local message="$1"
  echo "Warning: $message" >&2
}

select_from_options() {
  local prompt="$1"
  local -n options_ref="$2"
  local selected=""
  local previous_ps3="${PS3-}"

  PS3="$prompt"
  select selected in "${options_ref[@]}"; do
    if [[ -n "${selected:-}" ]]; then
      PS3="$previous_ps3"
      printf "%s" "$selected"
      return 0
    fi
    echo "Invalid option, please try again."
  done
}
